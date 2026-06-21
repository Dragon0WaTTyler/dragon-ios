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
    let summaryHTML: String
    let contentHTML: String
    let imageURL: String
    let videoURL: String
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

            guard currentItem != nil else {
                return
            }

            currentItem?.apply(attributes: attributeDict, for: name)
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
        var descriptionHTML = ""
        var summaryHTML = ""
        var contentHTML = ""
        var publishedText = ""
        var imageCandidates: [String] = []
        var videoCandidates: [String] = []

        mutating func apply(text: String, for elementName: String) {
            let trimmedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else {
                return
            }

            switch elementName {
            case "title":
                if title.isEmpty {
                    title = trimmedValue
                }
            case "link":
                if link.isEmpty {
                    link = trimmedValue
                }
            case "guid", "id":
                if id.isEmpty {
                    id = trimmedValue
                }
            case "description":
                if descriptionHTML.isEmpty {
                    descriptionHTML = text
                }
            case "summary":
                if summaryHTML.isEmpty {
                    summaryHTML = text
                }
            case "content", "encoded":
                if contentHTML.isEmpty {
                    contentHTML = text
                }
            case "pubdate", "published", "updated":
                if publishedText.isEmpty {
                    publishedText = trimmedValue
                }
            case "thumbnail", "image":
                if imageCandidates.isEmpty {
                    imageCandidates.append(trimmedValue)
                }
            case "video":
                if videoCandidates.isEmpty {
                    videoCandidates.append(trimmedValue)
                }
            default:
                break
            }
        }

        mutating func apply(attributes: [String: String], for elementName: String) {
            func firstAttribute(_ keys: [String]) -> String? {
                keys.compactMap { attributes[$0] }.first
            }

            if elementName == "link",
               let href = firstAttribute(["href"]),
               !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let relationship = attributes["rel"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if relationship == nil || relationship == "alternate" || relationship == "self" {
                    link = href
                }
            }

            let urlValue = firstAttribute(["url", "href", "src"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !urlValue.isEmpty else {
                return
            }

            let normalizedType = [
                attributes["type"],
                attributes["medium"],
                attributes["role"]
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if elementName == "thumbnail" {
                imageCandidates.append(urlValue)
                return
            }

            if elementName == "enclosure" || elementName == "content" || elementName == "group" || elementName == "image" {
                if normalizedType.contains("video") || DragonRSSParser.extractYouTubeVideoURL(from: urlValue) != nil {
                    videoCandidates.append(urlValue)
                } else if normalizedType.isEmpty || normalizedType.contains("image") {
                    imageCandidates.append(urlValue)
                }
            }
        }

        func build(feedTitle: String) -> DragonParsedArticle? {
            let resolvedTitle = DragonRSSParser.cleanText(title)
            let resolvedLink = DragonRSSParser.cleanLink(link)
            let resolvedSummaryHTML = DragonRSSParser.preferredHTML(summaryHTML, descriptionHTML: descriptionHTML, contentHTML: contentHTML)
            let resolvedSummary = DragonRSSParser.cleanSummary(
                resolvedSummaryHTML,
                descriptionHTML: descriptionHTML,
                contentHTML: contentHTML
            )

            guard !resolvedTitle.isEmpty || !resolvedLink.isEmpty || !resolvedSummary.isEmpty else {
                return nil
            }

            let parsedDate = DragonRSSParser.parseDate(from: publishedText)
            let rawID = DragonRSSParser.cleanText(id)
            let stableID = rawID.isEmpty
                ? DragonRSSParser.hashedID(link: resolvedLink, title: resolvedTitle, source: feedTitle)
                : rawID

            let resolvedContentHTML = DragonRSSParser.preferredHTML(contentHTML, descriptionHTML: descriptionHTML, contentHTML: summaryHTML)
            let bestImageURL = DragonRSSParser.bestImageURL(
                from: imageCandidates.map(Optional.some) + [
                    DragonRSSParser.extractOGImage(from: contentHTML),
                    DragonRSSParser.extractOGImage(from: descriptionHTML),
                    DragonRSSParser.extractFirstImage(from: contentHTML),
                    DragonRSSParser.extractFirstImage(from: descriptionHTML),
                    DragonRSSParser.extractFirstImage(from: summaryHTML)
                ]
            )

            let bestVideoURL = DragonRSSParser.bestVideoURL(
                from: videoCandidates.map(Optional.some) + [
                    DragonRSSParser.extractYouTubeVideoURL(from: contentHTML),
                    DragonRSSParser.extractYouTubeVideoURL(from: descriptionHTML),
                    DragonRSSParser.extractYouTubeVideoURL(from: summaryHTML),
                    DragonRSSParser.extractYouTubeVideoURL(from: resolvedLink)
                ]
            )

            return DragonParsedArticle(
                id: stableID,
                title: resolvedTitle.isEmpty ? "Untitled article" : resolvedTitle,
                link: resolvedLink,
                source: feedTitle,
                publishedAt: parsedDate,
                summary: resolvedSummary,
                summaryHTML: resolvedSummaryHTML,
                contentHTML: resolvedContentHTML,
                imageURL: bestImageURL ?? "",
                videoURL: bestVideoURL ?? ""
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
        DragonArticleTextCleaner.displayText(value)
    }

    static func cleanLink(_ value: String) -> String {
        cleanText(value)
    }

    static func preferredHTML(_ primary: String, descriptionHTML: String, contentHTML fallbackHTML: String) -> String {
        let candidates = [primary, descriptionHTML, fallbackHTML]
        return candidates.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    static func cleanSummary(_ summaryHTML: String, descriptionHTML: String, contentHTML: String) -> String {
        let rawValue = preferredHTML(summaryHTML, descriptionHTML: descriptionHTML, contentHTML: contentHTML)
        return plainText(fromHTML: rawValue)
    }

    static func plainText(fromHTML html: String) -> String {
        DragonArticleTextCleaner.plainText(fromHTML: html)
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        DragonArticleTextCleaner.decodedEntities(value)
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

    static func extractOGImage(from html: String) -> String? {
        extractMetaContent(from: html, propertyNames: ["og:image", "twitter:image"])
    }

    static func extractMetaContent(from html: String, propertyNames: [String]) -> String? {
        for propertyName in propertyNames {
            let pattern = #"<meta[^>]+(?:property|name)\s*=\s*["']\#(propertyName)["'][^>]+content\s*=\s*["']([^"']+)["'][^>]*>"#
            if let match = firstMatch(for: pattern, in: html, captureGroup: 1) {
                return cleanText(match)
            }
        }
        return nil
    }

    static func extractFirstImage(from html: String) -> String? {
        let patterns = [
            #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#,
            #"<figure[^>]*>[\s\S]*?<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: html, captureGroup: 1),
               let normalized = normalizedMediaURL(match),
               isMeaningfulImageURL(normalized) {
                return normalized
            }
        }

        return nil
    }

    static func bestImageURL(from candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let candidate,
                  let normalized = normalizedMediaURL(candidate),
                  isMeaningfulImageURL(normalized) else {
                continue
            }

            return normalized
        }

        return nil
    }

    static func bestVideoURL(from candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let candidate,
                  let resolved = extractYouTubeVideoURL(from: candidate) else {
                continue
            }

            return resolved
        }

        return nil
    }

    static func extractYouTubeVideoURL(from value: String) -> String? {
        let patterns = [
            #"https?://(?:www\.)?youtube\.com/watch\?[^"'\s<]*v=[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://(?:www\.)?youtube\.com/embed/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://(?:www\.)?youtube\.com/shorts/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://youtu\.be/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"//(?:www\.)?youtube\.com/watch\?[^"'\s<]*v=[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"//youtu\.be/[A-Za-z0-9_-]{11}[^"'\s<]*"#
        ]

        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: decodeHTMLEntities(value), captureGroup: 0) {
                return normalizedMediaURL(match)
            }
        }

        let cleaned = cleanText(value)
        guard cleaned.contains("youtube.com") || cleaned.contains("youtu.be") else {
            return nil
        }
        return normalizedMediaURL(cleaned)
    }

    static func normalizedMediaURL(_ rawValue: String) -> String? {
        let trimmed = DragonArticleTextCleaner.decodedEntities(rawValue)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>(),"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.lowercased().hasPrefix("data:") else {
            return nil
        }

        let candidate = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        let sanitized = candidate.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: sanitized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url.absoluteString
    }

    static func isMeaningfulImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let lowercasedPath = url.path.lowercased()
        if lowercasedPath.hasSuffix(".svg") {
            return false
        }

        let noiseMarkers = [
            "icon",
            "logo",
            "avatar",
            "sprite",
            "favicon",
            "placeholder",
            "blank",
            "emoji"
        ]

        return !noiseMarkers.contains { lowercasedPath.contains($0) || url.absoluteString.lowercased().contains($0) }
    }

    static func firstMatch(for pattern: String, in value: String, captureGroup: Int) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, options: [], range: range),
              let captureRange = Range(match.range(at: captureGroup), in: value) else {
            return nil
        }

        return String(value[captureRange])
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
