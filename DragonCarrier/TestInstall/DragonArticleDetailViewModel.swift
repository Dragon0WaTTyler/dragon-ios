import Foundation

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    enum State {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var article: DragonArticle
    @Published private(set) var isFetchingFullArticle = false

    private let contentLoader: NativeArticleContentLoader
    private var hasLoaded = false

    init(
        article: DragonArticle,
        initialState: State = .loading
    ) {
        self.article = article
        self.contentLoader = NativeArticleContentLoader()
        self.state = initialState
    }

    var title: String {
        let cleanedTitle = DragonArticleTextCleaner.displayText(article.title)
        return cleanedTitle.isEmpty ? "Untitled article" : cleanedTitle
    }

    var source: String {
        DragonArticleTextCleaner.displayText(article.source)
    }

    var savedAt: String {
        article.saved_at
    }

    var articleURL: URL? {
        article.resolvedOriginalURL
    }

    var imageURL: URL? {
        article.resolvedImageURL
    }

    var hasFullArticleContent: Bool {
        article.fulltext_status.status == "native_loaded"
    }

    var hasDisplayBody: Bool {
        !displayBodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayBodyText: String {
        let primaryText = DragonArticleTextCleaner.bodyText(article.content_text)
        if !primaryText.isEmpty {
            return primaryText
        }

        let htmlFallback = DragonArticleTextCleaner.plainText(fromHTML: article.content_html)
        if !htmlFallback.isEmpty {
            return htmlFallback
        }

        return DragonArticleTextCleaner.bodyText(article.excerpt)
    }

    var readerNotice: String? {
        hasFullArticleContent ? nil : "Full content unavailable. Showing saved preview."
    }

    var stateLabels: [String] {
        [article.readIndicatorLabel, article.savedIndicatorLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var bodyParagraphs: [String] {
        paragraphs(from: displayBodyText)
    }

    var detectedVideo: ArticleEmbeddedVideo? {
        ArticleEmbeddedVideo.detect(in: article)
    }

    var canLoadFullArticle: Bool {
        articleURL != nil
    }

    var loadFullArticleButtonTitle: String {
        hasFullArticleContent ? "Reload Full Article" : "Load Full Article"
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }

        return isFetchingFullArticle
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        state = .loading

        if let articleURL,
           let cachedContent = await contentLoader.loadCachedContent(for: articleURL) {
            article = article.merged(with: cachedContent)
        }

        state = .loaded
    }

    func loadFullArticle() async {
        guard let articleURL, !isFetchingFullArticle else {
            return
        }

        isFetchingFullArticle = true
        do {
            let cachedContent = try await contentLoader.fetchContent(for: articleURL)
            article = article.merged(with: cachedContent)
            state = .loaded
        } catch {
#if DEBUG
            print("[Articles Full Load] Failed for \(articleURL.absoluteString): \(error)")
#endif
            state = .failed("Full content unavailable. Showing saved preview.")
        }
        isFetchingFullArticle = false
    }

    private func paragraphs(from value: String) -> [String] {
        let content = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return []
        }

        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !paragraphs.isEmpty {
            return paragraphs
        }

        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ArticleEmbeddedVideo: Equatable {
    let videoID: String
    let sourceURL: URL

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    var embedURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/embed/\(videoID)"
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube.com"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1")
        ]
        return components.url!
    }

    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }

    static func detect(in article: DragonArticle) -> ArticleEmbeddedVideo? {
        let fields = [
            article.video_embed_url,
            article.video_url,
            article.media_url,
            article.original_url,
            article.canonical_url,
            article.url,
            article.excerpt,
            article.content_text,
            article.content_html
        ]

        for field in fields {
            for candidate in extractURLStrings(from: field) {
                guard let url = normalizedURL(from: candidate),
                      let videoID = extractYouTubeVideoID(from: url) else {
                    continue
                }

                return ArticleEmbeddedVideo(videoID: videoID, sourceURL: url)
            }
        }

        return nil
    }

    private static func extractURLStrings(from value: String) -> [String] {
        let normalized = DragonArticleTextCleaner.decodedEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return []
        }

        let pattern = #"(?:(?:https?:)?//)[^\s"'<>)]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [normalized]
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = expression.matches(in: normalized, options: [], range: range)
        let values = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: normalized) else {
                return nil
            }

            return String(normalized[range])
        }

        if values.isEmpty,
           normalized.hasPrefix("http://") || normalized.hasPrefix("https://") || normalized.hasPrefix("//") {
            return [normalized]
        }

        return values
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = DragonArticleTextCleaner.decodedEntities(rawValue)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>(),."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        let sanitized = candidate.replacingOccurrences(of: " ", with: "%20")
        return URL(string: sanitized)
    }

    private static func extractYouTubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else {
            return nil
        }

        if host.contains("youtu.be") {
            let candidate = url.pathComponents.dropFirst().first ?? ""
            return isValidYouTubeVideoID(candidate) ? candidate : nil
        }

        guard host.contains("youtube.com") else {
            return nil
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let candidate = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidYouTubeVideoID(candidate) {
            return candidate
        }

        let pathComponents = url.pathComponents
        for marker in ["embed", "shorts", "live"] {
            if let markerIndex = pathComponents.firstIndex(of: marker),
               pathComponents.indices.contains(markerIndex + 1) {
                let candidate = pathComponents[markerIndex + 1]
                if isValidYouTubeVideoID(candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func isValidYouTubeVideoID(_ value: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.count == 11 && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

}

private enum NativeArticleContentLoaderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case unreadableHTML
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid article URL."
        case .invalidResponse:
            return "Invalid article response."
        case .httpStatus(let statusCode):
            return "Article returned HTTP \(statusCode)."
        case .unreadableHTML:
            return "Could not decode the article page."
        case .emptyContent:
            return "No readable article content was found."
        }
    }
}

fileprivate final class NativeArticleContentLoader {
    private let session: URLSession
    private let snapshotStore: DragonSnapshotStore

    init(
        session: URLSession = .shared,
        snapshotStore: DragonSnapshotStore = .shared
    ) {
        self.session = session
        self.snapshotStore = snapshotStore
    }

    fileprivate func loadCachedContent(for url: URL) async -> CachedArticleContent? {
        await snapshotStore.load(CachedArticleContent.self, for: .articleContent(url: url.absoluteString))?.value
    }

    fileprivate func fetchContent(for url: URL) async throws -> CachedArticleContent {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NativeArticleContentLoaderError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NativeArticleContentLoaderError.httpStatus(httpResponse.statusCode)
        }

        guard let html = Self.decodeHTML(data: data) else {
            throw NativeArticleContentLoaderError.unreadableHTML
        }

        let extracted = NativeArticleHTMLExtractor.extract(from: html, sourceURL: url)
        guard !extracted.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeArticleContentLoaderError.emptyContent
        }

        let cachedContent = CachedArticleContent(
            sourceURL: url.absoluteString,
            fetchedAt: Date(),
            contentText: extracted.contentText,
            contentHTML: extracted.contentHTML,
            imageURL: extracted.imageURL,
            videoURL: extracted.videoURL
        )
        await snapshotStore.save(cachedContent, for: .articleContent(url: url.absoluteString))
        return cachedContent
    }

    private static func decodeHTML(data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16), !utf16.isEmpty {
            return utf16
        }
        if let latin1 = String(data: data, encoding: .isoLatin1), !latin1.isEmpty {
            return latin1
        }

        let fallback = String(decoding: data, as: UTF8.self)
        return fallback.isEmpty ? nil : fallback
    }
}

private struct CachedArticleContent: Codable {
    let sourceURL: String
    let fetchedAt: Date
    let contentText: String
    let contentHTML: String
    let imageURL: String
    let videoURL: String
}

private struct ExtractedArticleContent {
    let contentText: String
    let contentHTML: String
    let imageURL: String
    let videoURL: String
}

private enum NativeArticleHTMLExtractor {
    static func extract(from html: String, sourceURL: URL) -> ExtractedArticleContent {
        let cleanedHTML = removeNoise(from: html)
        let candidateRegions = [cleanedHTML] + preferredRegions(in: cleanedHTML)
        let selectedRegion = candidateRegions.max { left, right in
            extractParagraphs(from: left).count < extractParagraphs(from: right).count
        } ?? cleanedHTML

        let paragraphs = extractParagraphs(from: selectedRegion)
        let contentText = paragraphs.joined(separator: "\n\n")
        let imageURL = bestImageURL(
            from: [
                extractMetaContent(from: cleanedHTML, propertyNames: ["og:image", "twitter:image"]),
                extractFirstMeaningfulImage(from: selectedRegion),
                extractFirstMeaningfulImage(from: cleanedHTML)
            ]
        ) ?? ""
        let videoURL = bestVideoURL(
            from: [
                extractYouTubeURL(from: selectedRegion),
                extractYouTubeURL(from: cleanedHTML),
                sourceURL.absoluteString
            ]
        ) ?? ""

        return ExtractedArticleContent(
            contentText: contentText,
            contentHTML: selectedRegion,
            imageURL: imageURL,
            videoURL: videoURL
        )
    }

    static func plainText(fromHTML html: String) -> String {
        DragonArticleTextCleaner.plainText(fromHTML: html)
    }

    private static func preferredRegions(in html: String) -> [String] {
        [
            firstTagBlock(named: "article", in: html),
            firstTagBlock(named: "main", in: html),
            firstTagBlock(named: "body", in: html)
        ]
        .compactMap { $0 }
    }

    private static func firstTagBlock(named tagName: String, in html: String) -> String? {
        let pattern = #"<\#(tagName)\b[^>]*>([\s\S]*?)</\#(tagName)>"#
        return firstMatch(for: pattern, in: html, captureGroup: 1)
    }

    private static func removeNoise(from html: String) -> String {
        var value = html
        let patterns = [
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

        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        return value
    }

    private static func extractParagraphs(from html: String) -> [String] {
        let paragraphPatterns = [
            #"<p\b[^>]*>([\s\S]*?)</p>"#,
            #"<blockquote\b[^>]*>([\s\S]*?)</blockquote>"#,
            #"<li\b[^>]*>([\s\S]*?)</li>"#
        ]

        var values: [String] = []
        for pattern in paragraphPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in expression.matches(in: html, options: [], range: range) {
                guard let captureRange = Range(match.range(at: 1), in: html) else {
                    continue
                }

                let text = plainText(fromHTML: String(html[captureRange]))
                guard isMeaningfulParagraph(text) else {
                    continue
                }

                values.append(text)
            }
        }

        let unique = values.reduce(into: [String]()) { result, paragraph in
            if !result.contains(paragraph) {
                result.append(paragraph)
            }
        }

        if !unique.isEmpty {
            return Array(unique.prefix(40))
        }

        let fallback = plainText(fromHTML: html)
        if isMeaningfulParagraph(fallback) {
            return [fallback]
        }

        return []
    }

    private static func isMeaningfulParagraph(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else {
            return false
        }

        let lowercased = trimmed.lowercased()
        let noiseMarkers = [
            "cookie",
            "newsletter",
            "sign up",
            "subscribe",
            "advertisement",
            "all rights reserved",
            "follow us",
            "read more"
        ]

        return !noiseMarkers.contains { lowercased.contains($0) }
    }

    private static func extractMetaContent(from html: String, propertyNames: [String]) -> String? {
        for propertyName in propertyNames {
            let pattern = #"<meta[^>]+(?:property|name)\s*=\s*["']\#(propertyName)["'][^>]+content\s*=\s*["']([^"']+)["'][^>]*>"#
            if let match = firstMatch(for: pattern, in: html, captureGroup: 1) {
                return DragonArticleTextCleaner.displayText(match)
            }
        }

        return nil
    }

    private static func extractFirstMeaningfulImage(from html: String) -> String? {
        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, options: [], range: range) {
            guard let captureRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let candidate = String(html[captureRange])
            guard let normalized = normalizedMediaURL(candidate),
                  isMeaningfulImageURL(normalized) else {
                continue
            }

            return normalized
        }

        return nil
    }

    private static func extractYouTubeURL(from value: String) -> String? {
        let patterns = [
            #"https?://(?:www\.)?youtube\.com/watch\?[^"'\s<]*v=[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://(?:www\.)?youtube\.com/embed/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://(?:www\.)?youtube\.com/shorts/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"https?://youtu\.be/[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"//(?:www\.)?youtube\.com/watch\?[^"'\s<]*v=[A-Za-z0-9_-]{11}[^"'\s<]*"#,
            #"//youtu\.be/[A-Za-z0-9_-]{11}[^"'\s<]*"#
        ]

        let normalized = DragonArticleTextCleaner.decodedEntities(value)
        for pattern in patterns {
            if let match = firstMatch(for: pattern, in: normalized, captureGroup: 0),
               let resolved = normalizedMediaURL(match) {
                return resolved
            }
        }

        return nil
    }

    private static func bestImageURL(from candidates: [String?]) -> String? {
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

    private static func bestVideoURL(from candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let candidate,
                  let resolved = extractYouTubeURL(from: candidate) else {
                continue
            }

            return resolved
        }

        return nil
    }

    private static func normalizedMediaURL(_ rawValue: String) -> String? {
        let trimmed = rawValue
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

    private static func isMeaningfulImageURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let lowercasedPath = url.path.lowercased()
        let lowercasedURL = url.absoluteString.lowercased()
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

        return !noiseMarkers.contains { lowercasedPath.contains($0) || lowercasedURL.contains($0) }
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
}

private extension DragonArticle {
    func merged(with cachedContent: CachedArticleContent) -> DragonArticle {
        DragonArticle(
            id: id,
            title: title,
            source: source,
            url: url,
            original_url: original_url,
            canonical_url: canonical_url,
            published_at: published_at,
            saved_at: saved_at,
            excerpt: excerpt,
            image: cachedContent.imageURL.isEmpty ? image : cachedContent.imageURL,
            thumbnail: cachedContent.imageURL.isEmpty ? thumbnail : cachedContent.imageURL,
            media_url: cachedContent.videoURL.isEmpty ? media_url : cachedContent.videoURL,
            video_url: cachedContent.videoURL.isEmpty ? video_url : cachedContent.videoURL,
            video_embed_url: cachedContent.videoURL.isEmpty ? video_embed_url : cachedContent.videoURL,
            status: status,
            read_state: read_state,
            fulltext_status: DragonArticleFulltextStatus(
                status: "native_loaded",
                display_label: "",
                display_message: "",
                next_action: "open_original",
                safe_error: ""
            ),
            content_text: cachedContent.contentText.isEmpty ? content_text : cachedContent.contentText,
            content_html: cachedContent.contentHTML.isEmpty ? content_html : cachedContent.contentHTML
        )
    }
}
