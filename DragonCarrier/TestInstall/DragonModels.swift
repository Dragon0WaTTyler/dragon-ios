import Foundation

struct DragonHealthResponse: Decodable {
    let api_version: String
    let ok: Bool
    let service: String
}

struct DragonHomeResponse: Codable {
    let app_name: String
    let api_version: String
    let ok: Bool
    let server_time: String
    let sections: [DragonSection]
    let service: String

    private enum CodingKeys: String, CodingKey {
        case app_name
        case api_version
        case ok
        case server_time
        case sections
        case service
    }

    init(app_name: String, api_version: String, ok: Bool, server_time: String, sections: [DragonSection], service: String) {
        self.app_name = app_name
        self.api_version = api_version
        self.ok = ok
        self.server_time = server_time
        self.sections = sections
        self.service = service
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.app_name = try container.decodeIfPresent(String.self, forKey: .app_name) ?? "Dragon"
        self.api_version = try container.decode(String.self, forKey: .api_version)
        self.ok = try container.decode(Bool.self, forKey: .ok)
        self.server_time = try container.decodeIfPresent(String.self, forKey: .server_time) ?? ""
        self.sections = try container.decode([DragonSection].self, forKey: .sections)
        self.service = try container.decode(String.self, forKey: .service)
    }
}

struct DragonSection: Codable, Identifiable {
    let api_path: String
    let key: String
    let label: String
    let status: String
    let count: Int?
    let href: String

    private enum CodingKeys: String, CodingKey {
        case api_path
        case key
        case label
        case status
        case count
        case href
    }

    init(api_path: String, key: String, label: String, status: String, count: Int?, href: String) {
        self.api_path = api_path
        self.key = key
        self.label = label
        self.status = status
        self.count = count
        self.href = href
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.label = try container.decode(String.self, forKey: .label)
        self.status = try container.decode(String.self, forKey: .status)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        let decodedHref = try container.decodeIfPresent(String.self, forKey: .href)
        let decodedAPIPath = try container.decodeIfPresent(String.self, forKey: .api_path)
        let fallbackPath = "/api/v1/\(key)"
        self.href = decodedHref ?? decodedAPIPath ?? fallbackPath
        self.api_path = decodedAPIPath ?? decodedHref ?? fallbackPath
    }

    var id: String {
        key
    }

    var displayCount: String {
        guard let count else {
            return "—"
        }

        return String(count)
    }

    var statusDisplayText: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct DragonArticlesResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonArticle]
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
    }

    init(api_version: String, ok: Bool, items: [DragonArticle], count: Int) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonArticle].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
            ?? items.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(api_version, forKey: .api_version)
        try container.encode(ok, forKey: .ok)
        try container.encode(items, forKey: .items)
        try container.encode(count, forKey: .count)
    }
}

struct DragonArticleFulltextStatus: Codable, Equatable {
    let status: String
    let display_label: String
    let display_message: String
    let next_action: String
    let safe_error: String

    init(
        status: String = "disabled",
        display_label: String = "Unavailable",
        display_message: String = "Full article loading is not available right now.",
        next_action: String = "open_original",
        safe_error: String = ""
    ) {
        self.status = status
        self.display_label = display_label
        self.display_message = display_message
        self.next_action = next_action
        self.safe_error = safe_error
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case display_label
        case display_message
        case next_action
        case safe_error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "disabled"
        self.display_label = try container.decodeIfPresent(String.self, forKey: .display_label) ?? "Unavailable"
        self.display_message = try container.decodeIfPresent(String.self, forKey: .display_message) ?? "Full article loading is not available right now."
        self.next_action = try container.decodeIfPresent(String.self, forKey: .next_action) ?? "open_original"
        self.safe_error = try container.decodeIfPresent(String.self, forKey: .safe_error) ?? ""
    }
}

struct DragonArticleDetailResponse: Codable {
    let api_version: String
    let ok: Bool
    let item: DragonArticle

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case item
    }

    init(api_version: String = "v1", ok: Bool, item: DragonArticle) {
        self.api_version = api_version
        self.ok = ok
        self.item = item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.item = try container.decode(DragonArticle.self, forKey: .item)
    }
}

struct DragonArticle: Codable, Identifiable {
    let id: String
    let title: String
    let source: String
    let url: String
    let original_url: String
    let canonical_url: String
    let published_at: String
    let saved_at: String
    let excerpt: String
    let image: String
    let thumbnail: String
    let media_url: String
    let video_url: String
    let video_embed_url: String
    let status: String
    let read_state: String
    let fulltext_status: DragonArticleFulltextStatus
    let content_text: String
    let content_html: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case source_name
        case url
        case original_url
        case originalUrl
        case canonical_url
        case canonicalUrl
        case published_at
        case date
        case saved_at
        case excerpt
        case image
        case image_url
        case imageUrl
        case thumbnail
        case thumbnail_url
        case thumbnailUrl
        case hero_image
        case heroImage
        case og_image
        case ogImage
        case media_image
        case mediaImage
        case enclosure_url
        case enclosureUrl
        case media_url
        case mediaUrl
        case video_url
        case videoUrl
        case video_embed_url
        case videoEmbedUrl
        case embed_url
        case embedUrl
        case youtube_url
        case youtubeUrl
        case youtube_embed_url
        case youtubeEmbedUrl
        case summary
        case description
        case status
        case read_state
        case fulltext_status
        case content_text
        case content_html
    }

    init(
        id: String,
        title: String,
        source: String,
        url: String,
        original_url: String = "",
        canonical_url: String = "",
        published_at: String,
        saved_at: String,
        excerpt: String,
        image: String = "",
        thumbnail: String = "",
        media_url: String = "",
        video_url: String = "",
        video_embed_url: String = "",
        status: String = "",
        read_state: String = "",
        fulltext_status: DragonArticleFulltextStatus = DragonArticleFulltextStatus(),
        content_text: String = "",
        content_html: String = ""
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.url = url
        self.original_url = original_url
        self.canonical_url = canonical_url
        self.published_at = published_at
        self.saved_at = saved_at
        self.excerpt = excerpt
        self.image = image
        self.thumbnail = thumbnail
        self.media_url = media_url
        self.video_url = video_url
        self.video_embed_url = video_embed_url
        self.status = status
        self.read_state = read_state
        self.fulltext_status = fulltext_status
        self.content_text = content_text
        self.content_html = content_html
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonArticle.decodeString(container, forKeys: [.id])
        self.title = DragonArticle.decodeString(container, forKeys: [.title], default: "Untitled article")
        self.source = DragonArticle.decodeString(container, forKeys: [.source, .source_name])
        self.url = DragonArticle.decodeString(container, forKeys: [.url])
        self.original_url = DragonArticle.decodeString(container, forKeys: [.original_url, .originalUrl])
        self.canonical_url = DragonArticle.decodeString(container, forKeys: [.canonical_url, .canonicalUrl])
        self.published_at = DragonArticle.decodeString(container, forKeys: [.published_at, .date])
        self.saved_at = DragonArticle.decodeString(container, forKeys: [.saved_at])
        self.excerpt = DragonArticle.decodeString(container, forKeys: [.excerpt, .summary, .description])
        self.image = DragonArticle.decodeString(
            container,
            forKeys: [
                .image,
                .image_url,
                .imageUrl,
                .hero_image,
                .heroImage,
                .og_image,
                .ogImage,
                .media_image,
                .mediaImage,
                .enclosure_url,
                .enclosureUrl
            ]
        )
        self.thumbnail = DragonArticle.decodeString(
            container,
            forKeys: [
                .thumbnail,
                .thumbnail_url,
                .thumbnailUrl,
                .image,
                .image_url,
                .imageUrl,
                .hero_image,
                .heroImage,
                .og_image,
                .ogImage,
                .media_image,
                .mediaImage,
                .enclosure_url,
                .enclosureUrl
            ]
        )
        self.media_url = DragonArticle.decodeString(
            container,
            forKeys: [.media_url, .mediaUrl, .video_url, .videoUrl, .youtube_url, .youtubeUrl]
        )
        self.video_url = DragonArticle.decodeString(
            container,
            forKeys: [.video_url, .videoUrl, .youtube_url, .youtubeUrl, .media_url, .mediaUrl]
        )
        self.video_embed_url = DragonArticle.decodeString(
            container,
            forKeys: [.video_embed_url, .videoEmbedUrl, .embed_url, .embedUrl, .youtube_embed_url, .youtubeEmbedUrl]
        )
        self.status = DragonArticle.decodeString(container, forKeys: [.status])
        self.read_state = DragonArticle.decodeString(container, forKeys: [.read_state])
        self.fulltext_status = try container.decodeIfPresent(DragonArticleFulltextStatus.self, forKey: .fulltext_status) ?? DragonArticleFulltextStatus()
        self.content_text = DragonArticle.decodeString(container, forKeys: [.content_text])
        self.content_html = DragonArticle.decodeString(container, forKeys: [.content_html])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(source, forKey: .source)
        try container.encode(url, forKey: .url)
        try container.encode(original_url, forKey: .original_url)
        try container.encode(canonical_url, forKey: .canonical_url)
        try container.encode(published_at, forKey: .published_at)
        try container.encode(saved_at, forKey: .saved_at)
        try container.encode(excerpt, forKey: .excerpt)
        try container.encode(image, forKey: .image)
        try container.encode(thumbnail, forKey: .thumbnail)
        try container.encode(media_url, forKey: .media_url)
        try container.encode(video_url, forKey: .video_url)
        try container.encode(video_embed_url, forKey: .video_embed_url)
        try container.encode(status, forKey: .status)
        try container.encode(read_state, forKey: .read_state)
        try container.encode(fulltext_status, forKey: .fulltext_status)
        try container.encode(content_text, forKey: .content_text)
        try container.encode(content_html, forKey: .content_html)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }
}

extension DragonArticle {
    var displayTitle: String {
        let trimmed = DragonArticleTextCleaner.displayText(title)
        return trimmed.isEmpty ? "Untitled article" : trimmed
    }

    var displaySource: String {
        DragonArticleTextCleaner.displayText(source)
    }

    var displayExcerpt: String {
        DragonArticleTextCleaner.displayText(excerpt)
    }

    var publishedDate: Date? {
        DragonArticle.date(from: published_at)
    }

    var publishedDisplayText: String? {
        guard let publishedDate else {
            let rawValue = published_at.trimmingCharacters(in: .whitespacesAndNewlines)
            return rawValue.isEmpty ? nil : rawValue
        }

        return DragonArticle.displayFormatter.string(from: publishedDate)
    }

    var publishedRelativeDisplayText: String? {
        guard let publishedDate else {
            return publishedDisplayText
        }

        return DragonArticle.relativeFormatter.localizedString(for: publishedDate, relativeTo: Date())
    }

    var resolvedImageURL: URL? {
        DragonRemoteMediaURLResolver.firstValidURL(in: [thumbnail, image])
            ?? DragonRemoteMediaURLResolver.firstImageURL(inHTMLValues: [content_html, excerpt])
    }

    var resolvedOriginalURL: URL? {
        DragonRemoteMediaURLResolver.firstValidURL(in: [original_url, canonical_url, url])
    }

    var hasSavedIndicator: Bool {
        !saved_at.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var savedIndicatorLabel: String? {
        hasSavedIndicator ? "Saved" : nil
    }

    var readIndicatorLabel: String? {
        let trimmed = read_state.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var hasReadableContent: Bool {
        !content_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !content_html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isPublishedWithinLast24Hours(referenceDate: Date = Date()) -> Bool {
        guard let publishedDate else {
            return false
        }

        return publishedDate <= referenceDate
            && publishedDate >= referenceDate.addingTimeInterval(-86_400)
    }

    private static func date(from rawValue: String) -> Date? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        for formatter in iso8601Parsers {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        for formatter in fallbackDateParsers {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private static let iso8601Parsers: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        return [fractional, standard]
    }()

    private static let fallbackDateParsers: [DateFormatter] = {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)

        func formatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter
        }

        return [
            formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"),
            formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
            formatter("yyyy-MM-dd HH:mm:ss"),
            formatter("yyyy-MM-dd"),
            formatter("EEE, dd MMM yyyy HH:mm:ss Z"),
            formatter("EEE, dd MMM yyyy HH:mm Z")
        ]
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

enum DragonArticleTextCleaner {
    private static let maxDecodePasses = 3

    static func displayText(_ value: String) -> String {
        clean(value, preserveNewlines: false)
    }

    static func bodyText(_ value: String) -> String {
        clean(value, preserveNewlines: true)
    }

    static func htmlSourceText(_ value: String) -> String {
        clean(value, preserveNewlines: false)
    }

    static func plainText(fromHTML html: String) -> String {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        return cleanHTML(html, preserveNewlines: true)
    }

    static func decodedEntities(_ value: String) -> String {
        var current = value
        for _ in 0..<maxDecodePasses {
            let next = decodeSinglePass(current)
            guard next != current else {
                break
            }
            current = next
        }

        return current
    }

    private static func clean(_ value: String, preserveNewlines: Bool) -> String {
        let decoded = decodedEntities(value)
        let stripped = stripHTMLMarkup(decoded, preserveNewlines: preserveNewlines)
        return normalizeWhitespace(stripped, preserveNewlines: preserveNewlines)
    }

    private static func cleanHTML(_ html: String, preserveNewlines: Bool) -> String {
        let normalizedHTML = decodedEntities(html)
        let stripped = stripHTMLMarkup(normalizedHTML, preserveNewlines: preserveNewlines)
        return normalizeWhitespace(stripped, preserveNewlines: preserveNewlines)
    }

    private static func decodeSinglePass(_ value: String) -> String {
        var decoded = value

        let namedEntities = [
            ("&" + "nbsp;", " "),
            ("&" + "quot;", "\""),
            ("&" + "apos;", "'"),
            ("&" + "lt;", "<"),
            ("&" + "gt;", ">"),
            ("&" + "amp;", "&"),
            ("&" + "ldquo;", "“"),
            ("&" + "rdquo;", "”"),
            ("&" + "lsquo;", "‘"),
            ("&" + "rsquo;", "’"),
            ("&" + "hellip;", "…")
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        decoded = decodeNumericEntities(in: decoded)
        decoded = normalizeMalformedArtifacts(in: decoded)

        return decoded
    }

    private static func normalizeMalformedArtifacts(in value: String) -> String {
        var normalized = value
        let replacements: [(String, String)] = [
            ("#8220;&", "“"),
            ("#8221;&", "”"),
            ("#8216;&", "‘"),
            ("#8217;&", "’"),
            ("&#8220;&", "“"),
            ("&#8221;&", "”"),
            ("&#8216;&", "‘"),
            ("&#8217;&", "’")
        ]

        for (artifact, replacement) in replacements {
            normalized = normalized.replacingOccurrences(of: artifact, with: replacement)
        }

        return normalized
    }

    private static func stripHTMLMarkup(_ value: String, preserveNewlines: Bool) -> String {
        var stripped = value
        let lineBreakReplacement = preserveNewlines ? "\n\n" : " "

        let blockPatterns = [
            #"<script\b[\s\S]*?</script>"#,
            #"<style\b[\s\S]*?</style>"#,
            #"<noscript\b[\s\S]*?</noscript>"#,
            #"<svg\b[\s\S]*?</svg>"#,
            #"<nav\b[\s\S]*?</nav>"#,
            #"<header\b[\s\S]*?</header>"#,
            #"<footer\b[\s\S]*?</footer>"#,
            #"<aside\b[\s\S]*?</aside>"#,
            #"<form\b[\s\S]*?</form>"#
        ]

        for pattern in blockPatterns {
            stripped = stripped.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        let separatorPatterns = [
            #"<(?:/)?(?:p|div|li|blockquote|h[1-6]|section|article|main|tr|td|th|ul|ol)\b[^>]*>"#,
            #"<br\b[^>]*>"#,
            #"<hr\b[^>]*>"#
        ]

        for pattern in separatorPatterns {
            stripped = stripped.replacingOccurrences(of: pattern, with: lineBreakReplacement, options: .regularExpression)
        }

        stripped = stripped.replacingOccurrences(
            of: #"</?[A-Za-z][A-Za-z0-9:-]*(?:\s[^>]*)?>"#,
            with: " ",
            options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(of: "<>", with: " ")

        return stripped
    }

    private static func decodeNumericEntities(in value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);", options: []) else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = expression.matches(in: value, options: [], range: range)
        guard !matches.isEmpty else {
            return value
        }

        var result = ""
        var currentIndex = value.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: value),
                  let captureRange = Range(match.range(at: 1), in: value) else {
                continue
            }

            result.append(contentsOf: value[currentIndex..<fullRange.lowerBound])

            let entity = String(value[captureRange])
            let scalarValue: UInt32?
            if entity.lowercased().hasPrefix("x") {
                scalarValue = UInt32(entity.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(entity, radix: 10)
            }

            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.append(Character(scalar))
            } else {
                result.append(contentsOf: value[fullRange])
            }

            currentIndex = fullRange.upperBound
        }

        result.append(contentsOf: value[currentIndex...])
        return result
    }

    private static func normalizeWhitespace(_ value: String, preserveNewlines: Bool) -> String {
        var normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        if preserveNewlines {
            normalized = normalized.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            normalized = normalized.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
            normalized = normalized.replacingOccurrences(of: "[ \t]*\n[ \t]*", with: "\n", options: .regularExpression)
            normalized = normalized.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        } else {
            normalized = normalized.replacingOccurrences(of: "\n", with: " ")
            normalized = normalized.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension DragonArticlesResponse {
    func filteredToRecentArticles(referenceDate: Date = Date()) -> DragonArticlesResponse {
        let recentItems = items.filter { $0.isPublishedWithinLast24Hours(referenceDate: referenceDate) }
        return DragonArticlesResponse(
            api_version: api_version,
            ok: ok,
            items: recentItems,
            count: recentItems.count
        )
    }
}

struct DragonBooksResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonBook]
    let count: Int
    let total: Int
    let limit: Int
    let offset: Int
    let has_more: Bool
    let next_offset: Int?

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
        case limit
        case offset
        case has_more
        case next_offset
    }

    init(
        api_version: String,
        ok: Bool,
        items: [DragonBook],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int = 0,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit ?? count
        self.offset = offset
        let resolvedHasMore = has_more ?? ((offset + count) < (total ?? count))
        self.has_more = resolvedHasMore
        self.next_offset = next_offset ?? (resolvedHasMore ? offset + count : nil)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonBook].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
            ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? count
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        let decodedHasMore = try container.decodeIfPresent(Bool.self, forKey: .has_more)
            ?? ((offset + count) < total)
        self.has_more = decodedHasMore
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
            ?? (decodedHasMore ? offset + count : nil)
    }
}

struct DragonBook: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let authors: [String]
    let cover: String
    let year: String
    let status: String
    let score: String
    let excerpt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case authors
        case cover
        case cover_url
        case status
        case year
        case score
        case excerpt
        case summary
    }

    init(
        id: String,
        title: String,
        author: String,
        authors: [String],
        cover: String,
        year: String,
        status: String,
        score: String,
        excerpt: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.authors = authors
        self.cover = cover
        self.year = year
        self.status = status
        self.score = score
        self.excerpt = excerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonBook.decodeString(container, keys: [.id])
        self.title = DragonBook.decodeString(container, keys: [.title], default: "Untitled book")
        self.author = DragonBook.decodeString(container, keys: [.author])
        self.authors = DragonBook.decodeStringArray(container, keys: [.authors])
        self.cover = DragonBook.decodeString(container, keys: [.cover, .cover_url])
        self.year = DragonBook.decodeString(container, keys: [.year])
        self.status = DragonBook.decodeString(container, keys: [.status])
        self.score = DragonBook.decodeString(container, keys: [.score])
        self.excerpt = DragonBook.decodeString(container, keys: [.excerpt, .summary])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(authors, forKey: .authors)
        try container.encode(cover, forKey: .cover)
        try container.encode(status, forKey: .status)
        try container.encode(year, forKey: .year)
        try container.encode(score, forKey: .score)
        try container.encode(excerpt, forKey: .excerpt)
    }

    var idValue: String {
        id
    }

    var resolvedCoverURL: URL? {
        DragonRemoteMediaURLResolver.firstValidURL(in: [cover])
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }

    private static func decodeStringArray(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [String] {
        for key in keys {
            if let values = try? container.decode([String].self, forKey: key) {
                let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return [trimmed]
                }
            }
        }

        return []
    }
}

private enum DragonRemoteMediaURLResolver {
    static func firstValidURL(in values: [String]) -> URL? {
        values.compactMap(sanitizedURL).first
    }

    static func firstImageURL(inHTMLValues values: [String]) -> URL? {
        for value in values {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            for pattern in imagePatterns {
                if let match = firstMatch(for: pattern, in: value, captureGroup: 1),
                   let url = sanitizedURL(match) {
                    return url
                }
            }
        }

        return nil
    }

    private static func sanitizedURL(_ rawValue: String) -> URL? {
        let trimmed = DragonArticleTextCleaner.decodedEntities(rawValue)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>(),"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var candidates = [trimmed]
        if trimmed.hasPrefix("//") {
            candidates.insert("https:\(trimmed)", at: 0)
        }
        candidates.append(contentsOf: candidates.map { $0.replacingOccurrences(of: " ", with: "%20") })

        for candidate in candidates {
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            return url
        }

        return nil
    }

    private static func firstMatch(for pattern: String, in value: String, captureGroup: Int) -> String? {
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

    private static let imagePatterns = [
        #"<meta[^>]+(?:property|name)\s*=\s*["'](?:og:image|twitter:image)["'][^>]+content\s*=\s*["']([^"']+)["'][^>]*>"#,
        #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#,
        #"<media:content[^>]+url\s*=\s*["']([^"']+)["'][^>]*>"#,
        #"<media:thumbnail[^>]+url\s*=\s*["']([^"']+)["'][^>]*>"#
    ]
}

struct DragonMoviesResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonMovie]
    let count: Int
    let total: Int
    let limit: Int?
    let offset: Int?
    let has_more: Bool
    let next_offset: Int?

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
        case limit
        case offset
        case has_more
        case next_offset
    }

    init(
        api_version: String,
        ok: Bool,
        items: [DragonMovie],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit
        self.offset = offset
        self.has_more = has_more ?? false
        self.next_offset = next_offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonMovie].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        self.has_more = try container.decodeIfPresent(Bool.self, forKey: .has_more) ?? false
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(api_version, forKey: .api_version)
        try container.encode(ok, forKey: .ok)
        try container.encode(items, forKey: .items)
        try container.encode(count, forKey: .count)
        try container.encode(total, forKey: .total)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encode(has_more, forKey: .has_more)
        try container.encodeIfPresent(next_offset, forKey: .next_offset)
    }
}

struct DragonMovie: Codable, Identifiable {
    let id: String
    let title: String
    let year: String
    let poster: String
    let director: String
    let genres: [String]
    let status: String
    let score: String
    let type: String
    let overview: String
    let tmdb_id: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case poster
        case director
        case genres
        case status
        case score
        case type
        case overview
        case tmdb_id
    }

    init(
        id: String,
        title: String,
        year: String,
        poster: String,
        director: String = "",
        genres: [String] = [],
        status: String,
        score: String,
        type: String,
        overview: String,
        tmdb_id: String = ""
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.poster = poster
        self.director = director
        self.genres = genres
        self.status = status
        self.score = score
        self.type = type
        self.overview = overview
        self.tmdb_id = tmdb_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonMovie.decodeString(container, forKey: .id)
        self.title = DragonMovie.decodeString(container, forKey: .title)
        self.year = DragonMovie.decodeString(container, forKey: .year)
        self.poster = DragonMovie.decodeString(container, forKey: .poster)
        self.director = DragonMovie.decodeString(container, forKey: .director)
        self.genres = DragonMovie.decodeStringArray(container, forKey: .genres)
        self.status = DragonMovie.decodeString(container, forKey: .status)
        self.score = DragonMovie.decodeString(container, forKey: .score)
        self.type = DragonMovie.decodeString(container, forKey: .type)
        self.overview = DragonMovie.decodeString(container, forKey: .overview)
        self.tmdb_id = DragonMovie.decodeString(container, forKey: .tmdb_id)
    }

    var posterURL: URL? {
        Self.sanitizedPosterURL(from: poster)
    }

    var genresText: String {
        genres.joined(separator: ", ")
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? container.decode(Double.self, forKey: key) {
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        }

        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return ""
    }

    private static func decodeStringArray(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String] {
        if let values = try? container.decode([String].self, forKey: key) {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        let fallbackString = decodeString(container, forKey: key)
        guard !fallbackString.isEmpty else {
            return []
        }

        return fallbackString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sanitizedPosterURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            return nil
        }

        let host = components.host?.lowercased() ?? ""
        if (host == "www.themoviedb.org" || host == "themoviedb.org"),
           components.path.hasPrefix("/t/p/") {
            components.scheme = "https"
            components.host = "image.tmdb.org"
            components.query = nil
            components.fragment = nil
        }

        return components.url
    }
}

struct DragonYouTubeVideosResponse: Codable {
    let api_version: String
    let ok: Bool
    let section: String
    let items: [DragonYouTubeVideo]
    let count: Int
    let total: Int
    let limit: Int
    let offset: Int
    let has_more: Bool
    let next_offset: Int?

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case section
        case items
        case count
        case total
        case limit
        case offset
        case has_more
        case next_offset
    }

    init(
        api_version: String,
        ok: Bool,
        section: String,
        items: [DragonYouTubeVideo],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int = 0,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.section = section
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit ?? count
        self.offset = offset
        let resolvedHasMore = has_more ?? ((offset + count) < (total ?? count))
        self.has_more = resolvedHasMore
        self.next_offset = next_offset ?? (resolvedHasMore ? offset + count : nil)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.section = DragonYouTubeVideosResponse.decodeString(container, keys: [.section])
        self.items = try container.decodeIfPresent([DragonYouTubeVideo].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? count
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        let decodedHasMore = try container.decodeIfPresent(Bool.self, forKey: .has_more)
            ?? ((offset + count) < total)
        self.has_more = decodedHasMore
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
            ?? (decodedHasMore ? offset + count : nil)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }
}

typealias DragonYouTubeResponse = DragonYouTubeVideosResponse

struct DragonYouTubeSectionsResponse: Codable {
    let api_version: String
    let ok: Bool
    let sections: [DragonYouTubeSection]

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case sections
    }

    init(api_version: String, ok: Bool, sections: [DragonYouTubeSection]) {
        self.api_version = api_version
        self.ok = ok
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.sections = try container.decodeIfPresent([DragonYouTubeSection].self, forKey: .sections) ?? []
    }
}

struct DragonYouTubeSection: Codable, Identifiable {
    let key: String
    let label: String
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case count
    }

    init(key: String, label: String, count: Int) {
        self.key = key
        self.label = label
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = DragonYouTubeSection.decodeString(container, keys: [.key], default: "unknown")
        self.label = DragonYouTubeSection.decodeString(container, keys: [.label], default: key.isEmpty ? "Unknown section" : key)
        self.count = DragonYouTubeSection.decodeInt(container, keys: [.count])
    }

    var id: String {
        key.isEmpty ? label : key
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }
        }

        return defaultValue
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int(trimmed) {
                    return parsed
                }
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                return Int(value.rounded())
            }
        }

        return 0
    }
}

struct DragonYouTubeVideo: Codable, Identifiable {
    let id: String
    let video_id: String
    let title: String
    let channel: String
    let thumbnail: String
    let url: String
    let published_at: String
    let saved_at: String
    let duration: String
    let section: String
    let group: String
    let playlist: String
    let source: String

    private enum CodingKeys: String, CodingKey {
        case id
        case video_id
        case videoId
        case title
        case channel
        case channel_title
        case thumbnail
        case thumbnail_url
        case url
        case published_at
        case publishedAt
        case saved_at
        case savedAt
        case duration
        case section
        case group
        case playlist
        case playlist_title
        case source
    }

    init(id: String, video_id: String, title: String, channel: String, thumbnail: String, url: String, published_at: String, saved_at: String, duration: String, section: String, group: String, playlist: String, source: String) {
        self.id = id
        self.video_id = video_id
        self.title = title
        self.channel = channel
        self.thumbnail = thumbnail
        self.url = url
        self.published_at = published_at
        self.saved_at = saved_at
        self.duration = duration
        self.section = section
        self.group = group
        self.playlist = playlist
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonYouTubeVideo.decodeString(container, keys: [.id, .video_id, .videoId])
        self.video_id = DragonYouTubeVideo.decodeString(container, keys: [.video_id, .videoId, .id])
        self.title = DragonYouTubeVideo.decodeString(container, keys: [.title], default: "Untitled video")
        self.channel = DragonYouTubeVideo.decodeString(container, keys: [.channel, .channel_title])
        self.thumbnail = DragonYouTubeVideo.decodeString(container, keys: [.thumbnail, .thumbnail_url])
        self.url = DragonYouTubeVideo.decodeString(container, keys: [.url])
        self.published_at = DragonYouTubeVideo.decodeString(container, keys: [.published_at, .publishedAt])
        self.saved_at = DragonYouTubeVideo.decodeString(container, keys: [.saved_at, .savedAt])
        self.duration = DragonYouTubeVideo.decodeString(container, keys: [.duration])
        self.section = DragonYouTubeVideo.decodeString(container, keys: [.section])
        self.group = DragonYouTubeVideo.decodeString(container, keys: [.group])
        self.playlist = DragonYouTubeVideo.decodeString(container, keys: [.playlist, .playlist_title])
        self.source = DragonYouTubeVideo.decodeString(container, keys: [.source], default: "unknown")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(video_id, forKey: .video_id)
        try container.encode(title, forKey: .title)
        try container.encode(channel, forKey: .channel)
        try container.encode(thumbnail, forKey: .thumbnail)
        try container.encode(url, forKey: .url)
        try container.encode(published_at, forKey: .published_at)
        try container.encode(saved_at, forKey: .saved_at)
        try container.encode(duration, forKey: .duration)
        try container.encode(section, forKey: .section)
        try container.encode(group, forKey: .group)
        try container.encode(playlist, forKey: .playlist)
        try container.encode(source, forKey: .source)
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys], default defaultValue: String = "") -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }
        }

        return defaultValue
    }
}
