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

    private let dataSource: DragonDataSource
    private var hasLoaded = false

    init(
        article: DragonArticle,
        dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource,
        initialState: State = .loading
    ) {
        self.article = article
        self.dataSource = dataSource
        self.state = initialState
    }

    var title: String {
        article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled article" : article.title
    }

    var source: String {
        article.source
    }

    var publishedAt: String {
        article.published_at
    }

    var savedAt: String {
        article.saved_at
    }

    var excerpt: String {
        article.excerpt
    }

    var contentText: String {
        article.content_text
    }

    var contentHTML: String {
        article.content_html
    }

    var fulltextStatusLabel: String {
        article.fulltext_status.display_label
    }

    var fulltextStatusMessage: String {
        let message = article.fulltext_status.display_message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            return message
        }

        let safeError = article.fulltext_status.safe_error.trimmingCharacters(in: .whitespacesAndNewlines)
        return safeError
    }

    var originalURL: String {
        article.url
    }

    var imageURL: URL? {
        ArticleDetailViewModel.sanitizedURL(article.thumbnail)
            ?? ArticleDetailViewModel.sanitizedURL(article.image)
    }

    var displayBodyText: String {
        let primaryText = article.content_text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primaryText.isEmpty {
            return primaryText
        }

        let htmlFallback = ArticleDetailViewModel.plainText(fromHTML: article.content_html)
        if !htmlFallback.isEmpty {
            return htmlFallback
        }

        return article.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCachedBody: Bool {
        !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayParagraphs: [String] {
        let content = displayBodyText
        guard !content.isEmpty else {
            return ["No article text available."]
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

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = state {
            return message
        }
        return nil
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        await loadDetail()
    }

    private func loadDetail() async {
        state = .loading

        do {
            let result = try await dataSource.fetchArticleDetail(id: article.id)
            article = article.merged(with: result.value)
            state = .loaded
        } catch {
            state = .failed(dragonUserFacingMessage(for: error))
        }
    }

    private static func sanitizedURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private static func plainText(fromHTML html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var value = trimmed
        let blockMarkers = ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>", "</blockquote>", "</h1>", "</h2>", "</h3>"]
        for marker in blockMarkers {
            value = value.replacingOccurrences(of: marker, with: "\n\n", options: [.caseInsensitive])
        }

        value = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "&nbsp;", with: " ")
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        value = value.replacingOccurrences(of: "&quot;", with: "\"")
        value = value.replacingOccurrences(of: "&#39;", with: "'")
        value = value.replacingOccurrences(of: "\\s+\\n", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension DragonArticle {
    func merged(with detail: DragonArticle) -> DragonArticle {
        DragonArticle(
            id: detail.id.isEmpty ? id : detail.id,
            title: detail.title.isEmpty ? title : detail.title,
            source: detail.source.isEmpty ? source : detail.source,
            url: detail.url.isEmpty ? url : detail.url,
            published_at: detail.published_at.isEmpty ? published_at : detail.published_at,
            saved_at: detail.saved_at.isEmpty ? saved_at : detail.saved_at,
            excerpt: detail.excerpt.isEmpty ? excerpt : detail.excerpt,
            image: detail.image.isEmpty ? image : detail.image,
            thumbnail: detail.thumbnail.isEmpty ? thumbnail : detail.thumbnail,
            status: detail.status.isEmpty ? status : detail.status,
            read_state: detail.read_state.isEmpty ? read_state : detail.read_state,
            fulltext_status: detail.fulltext_status,
            content_text: detail.content_text,
            content_html: detail.content_html
        )
    }
}
