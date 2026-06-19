import CryptoKit
import Foundation

struct DragonParsedFeed: Sendable {
    let title: String
    let articles: [DragonParsedArticle]
}

struct DragonParsedArticle: Sendable {
    let id: String
    let title: String
    let link: String
    let source: String
    let publishedAt: Date?
    let summary: String
}

enum DragonRSSParserError: LocalizedError {
    case invalidFeed

    var errorDescription: String? {
        switch self {
        case .invalidFeed:
            return "The feed could not be parsed."
        }
    }
}

struct DragonRSSParser: Sendable {
    func parse(data: Data, fallbackFeedTitle: String) throws -> DragonParsedFeed {
        let delegate = Delegate(fallbackFeedTitle: fallbackFeedTitle)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            throw parser.parserError ?? DragonRSSParserError.invalidFeed
        }

        let feed = delegate.buildFeed()
        guard !feed.title.isEmpty || !feed.articles.isEmpty else {
            throw DragonRSSParserError.invalidFeed
        }

        return feed
    }
}

private extension DragonRSSParser {
    final class Delegate: NSObject, XMLParserDelegate {
        private let fallbackFeedTitle: String
        private var elementStack: [String] = []
        private var currentText = ""
        private var feedTitle = ""
        private var currentItem: ItemBuilder?
        private var parsedItems: [DragonParsedArticle] = []

        init(fallbackFeedTitle: String) {
            self.fallbackFeedTitle = fallbackFeedTitle
        }

        func buildFeed() -> DragonParsedFeed {
            let resolvedFeedTitle = DragonRSSParser.cleanText(feedTitle).isEmpty
                ? fallbackFeedTitle
                : DragonRSSParser.cleanText(feedTitle)

            return DragonParsedFeed(title: resolvedFeedTitle, articles: parsedItems)
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = DragonRSSParser.normalizedName(qName ?? elementName)
            elementStack.append(name)
            currentText = ""

            if name == "item" || name == "entry" {
                currentItem = ItemBuilder()
                return
            }

            guard currentItem != nil, name == "link" else {
                return
            }

            if let href = attributeDict["href"], !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let relationship = attributeDict["rel"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if relationship == nil || relationship == "alternate" || relationship == "self" {
                    currentItem?.link = href
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText.append(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                currentText.append(text)
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = DragonRSSParser.normalizedName(qName ?? elementName)
            let value = currentText
            let parent = elementStack.dropLast().last

            if name == "item" || name == "entry" {
                let sourceTitle = DragonRSSParser.cleanText(feedTitle).isEmpty
                    ? fallbackFeedTitle
                    : DragonRSSParser.cleanText(feedTitle)
                if let article = currentItem?.build(feedTitle: sourceTitle) {
                    parsedItems.append(article)
                }
                currentItem = nil
            } else if currentItem != nil {
                currentItem?.apply(text: value, for: name)
            } else if name == "title", parent == "channel" || parent == "feed" {
                let cleanedTitle = DragonRSSParser.cleanText(value)
                if !cleanedTitle.isEmpty {
                    feedTitle = cleanedTitle
                }
            }

            if !elementStack.isEmpty {
                elementStack.removeLast()
            }
            currentText = ""
        }
    }

    struct ItemBuilder {
        var id = ""
        var title = ""
        var link = ""
        var description = ""
        var summary = ""
        var content = ""
        var publishedText = ""

        mutating func apply(text: String, for elementName: String) {
            let cleanedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedValue.isEmpty else {
                return
            }

            switch elementName {
            case "title":
                if title.isEmpty {
                    title = cleanedValue
                }
            case "link":
                if link.isEmpty {
                    link = cleanedValue
                }
            case "guid", "id":
                if id.isEmpty {
                    id = cleanedValue
                }
            case "description":
                if description.isEmpty {
                    description = cleanedValue
                }
            case "summary":
                if summary.isEmpty {
                    summary = cleanedValue
                }
            case "content", "encoded":
                if content.isEmpty {
                    content = cleanedValue
                }
            case "pubdate", "published", "updated":
                if publishedText.isEmpty {
                    publishedText = cleanedValue
                }
            default:
                break
            }
        }

        func build(feedTitle: String) -> DragonParsedArticle? {
            let resolvedTitle = DragonRSSParser.cleanText(title)
            let resolvedLink = DragonRSSParser.cleanLink(link)
            let resolvedSummary = DragonRSSParser.cleanSummary(summary, description: description, content: content)

            guard !resolvedTitle.isEmpty || !resolvedLink.isEmpty || !resolvedSummary.isEmpty else {
                return nil
            }

            let parsedDate = DragonRSSParser.parseDate(from: publishedText)
            let rawID = DragonRSSParser.cleanText(id)
            let stableID = rawID.isEmpty
                ? DragonRSSParser.hashedID(link: resolvedLink, title: resolvedTitle, source: feedTitle)
                : rawID

            return DragonParsedArticle(
                id: stableID,
                title: resolvedTitle.isEmpty ? "Untitled article" : resolvedTitle,
                link: resolvedLink,
                source: feedTitle,
                publishedAt: parsedDate,
                summary: resolvedSummary
            )
        }
    }

    static func normalizedName(_ value: String) -> String {
        value
            .split(separator: ":", omittingEmptySubsequences: false)
            .last
            .map(String.init)?
            .lowercased() ?? value.lowercased()
    }

    static func cleanText(_ value: String) -> String {
        decodeHTMLEntities(
            value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanLink(_ value: String) -> String {
        cleanText(value)
    }

    static func cleanSummary(_ summary: String, description: String, content: String) -> String {
        let rawValue: String
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawValue = summary
        } else if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawValue = description
        } else {
            rawValue = content
        }

        let withoutTags = rawValue.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        return cleanText(withoutTags)
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        let replacements = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]

        for (entity, replacement) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }

    static func hashedID(link: String, title: String, source: String) -> String {
        let rawValue = [link, title, source]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")

        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func parseDate(from value: String) -> Date? {
        let cleanedValue = cleanText(value)
        guard !cleanedValue.isEmpty else {
            return nil
        }

        for formatter in iso8601Formatters {
            if let date = formatter.date(from: cleanedValue) {
                return date
            }
        }

        for formatter in rssDateFormatters {
            if let date = formatter.date(from: cleanedValue) {
                return date
            }
        }

        return nil
    }

    static let iso8601Formatters: [ISO8601DateFormatter] = {
        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]

        let internetDateTimeWithFractionalSeconds = ISO8601DateFormatter()
        internetDateTimeWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [internetDateTimeWithFractionalSeconds, internetDateTime]
    }()

    static let rssDateFormatters: [DateFormatter] = {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm zzz",
            "d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm Z"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter
        }
    }()
}
