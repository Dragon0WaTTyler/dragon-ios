import Foundation

struct DragonRSSSourceDescriptor: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let feedURL: String
    let language: String?
    let category: String?
    let active: Bool

    var normalizedName: String {
        name.dragonTrimmedOrNil ?? fallbackName
    }

    var normalizedFeedURL: String {
        feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var url: URL? {
        URL(string: normalizedFeedURL)
    }

    func updating(
        name: String? = nil,
        feedURL: String? = nil,
        active: Bool? = nil
    ) -> DragonRSSSourceDescriptor {
        DragonRSSSourceDescriptor(
            id: id,
            name: name ?? self.name,
            feedURL: feedURL ?? self.feedURL,
            language: language,
            category: category,
            active: active ?? self.active
        )
    }

    private var fallbackName: String {
        url?.host?.dragonTrimmedOrNil ?? "RSS Source"
    }
}

struct DragonRSSSourceFetchStatus: Codable, Sendable {
    let sourceID: String
    let sourceName: String
    let feedURL: String
    let status: String
    let itemCount: Int
    let fetchedAt: Date
    let errorMessage: String?
}

struct DragonNativeArticlesDiagnostics: Codable, Sendable {
    let totalFeedsFetched: Int
    let totalItemsParsed: Int
    let totalValidDatedItems: Int
    let totalItemsInside24Hours: Int
    let oldestDisplayedArticleAgeHours: Double?
}

struct DragonNativeArticlesFetchResult: Sendable {
    let response: DragonArticlesResponse
    let sourceStatuses: [DragonRSSSourceFetchStatus]
    let diagnostics: DragonNativeArticlesDiagnostics
}

enum DragonArticlesFeedRegistry {
    static let v1Feeds: [DragonRSSSourceDescriptor] = [
        DragonRSSSourceDescriptor(
            id: "hespress",
            name: "Hespress",
            feedURL: "https://www.hespress.com/feed",
            language: "ar",
            category: "general",
            active: true
        ),
        DragonRSSSourceDescriptor(
            id: "aljazeera-ar",
            name: "Al Jazeera Arabic",
            feedURL: "https://www.aljazeera.net/aljazeerarss/a7c186be-1baa-4bd4-9d80-a84db769f779/73d0e1b4-532f-45ef-b135-bfdff8b8cab9",
            language: "ar",
            category: "general",
            active: true
        ),
        DragonRSSSourceDescriptor(
            id: "aljazeera-en",
            name: "Al Jazeera English",
            feedURL: "https://www.aljazeera.com/xml/rss/all.xml",
            language: "en",
            category: "general",
            active: true
        )
    ]
}

enum DragonRSSArticleSourceError: LocalizedError {
    case emptyRegistry
    case noArticlesAvailable([String])
    case invalidFeedURL(String)
    case invalidResponse(URL)
    case httpStatus(URL, Int)

    var errorDescription: String? {
        switch self {
        case .emptyRegistry:
            return "No RSS sources configured. Add sources in Settings → Articles."
        case .noArticlesAvailable(let failures):
            if failures.isEmpty {
                return "No articles were available from the configured RSS feeds."
            }
            return failures.joined(separator: " ")
        case .invalidFeedURL(let value):
            return "Invalid RSS feed URL: \(value)"
        case .invalidResponse(let url):
            return "Invalid feed response from \(url.host() ?? url.absoluteString)."
        case .httpStatus(let url, let statusCode):
            return "Feed \(url.host() ?? url.absoluteString) returned HTTP \(statusCode)."
        }
    }
}

final class DragonRSSArticleSource {
    private let session: URLSession
    private let feeds: [DragonRSSSourceDescriptor]
    private let parser: DragonRSSParser
    private let nowProvider: () -> Date

    init(
        session: URLSession = .shared,
        feeds: [DragonRSSSourceDescriptor] = DragonArticlesFeedRegistry.v1Feeds,
        parser: DragonRSSParser = DragonRSSParser(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.feeds = feeds
        self.parser = parser
        self.nowProvider = nowProvider
    }

    func fetchArticles() async throws -> DragonNativeArticlesFetchResult {
        let activeFeeds = feeds.filter(\.active)
        guard !activeFeeds.isEmpty else {
            throw DragonRSSArticleSourceError.emptyRegistry
        }

        let outcomes = await withTaskGroup(of: FeedOutcome.self, returning: [FeedOutcome].self) { group in
            for feed in activeFeeds {
                group.addTask { [session, parser] in
                    await Self.fetchFeed(feed, session: session, parser: parser)
                }
            }

            var results: [FeedOutcome] = []
            for await outcome in group {
                results.append(outcome)
            }
            return results
        }

        let parsedArticles = outcomes
            .flatMap(\.articles)
            .sorted(by: Self.articleSort)
        let deduplicatedArticles = deduplicatedArticles(parsedArticles)
        let validDatedArticles = deduplicatedArticles.filter { $0.publishedAt != nil }
        let referenceDate = nowProvider()
        let recentArticles = validDatedArticles.filter {
            guard let publishedAt = $0.publishedAt else {
                return false
            }

            return publishedAt <= referenceDate
                && publishedAt >= referenceDate.addingTimeInterval(-86_400)
        }

        guard !recentArticles.isEmpty else {
            let failures = outcomes.compactMap(\.failureMessage)
            throw DragonRSSArticleSourceError.noArticlesAvailable(failures)
        }

        let response = DragonArticlesResponse(
            api_version: "native-rss-v1",
            ok: true,
            items: recentArticles.map(Self.makeArticle(from:)),
            count: recentArticles.count
        )

        let oldestDisplayedArticleAgeHours = recentArticles.last?.publishedAt.map {
            referenceDate.timeIntervalSince($0) / 3_600
        }

        return DragonNativeArticlesFetchResult(
            response: response,
            sourceStatuses: outcomes.map(\.status),
            diagnostics: DragonNativeArticlesDiagnostics(
                totalFeedsFetched: outcomes.count,
                totalItemsParsed: parsedArticles.count,
                totalValidDatedItems: validDatedArticles.count,
                totalItemsInside24Hours: recentArticles.count,
                oldestDisplayedArticleAgeHours: oldestDisplayedArticleAgeHours
            )
        )
    }

    private func deduplicatedArticles(_ articles: [DragonParsedArticle]) -> [DragonParsedArticle] {
        var seenKeys = Set<String>()
        var uniqueArticles: [DragonParsedArticle] = []

        for article in articles {
            let dedupeKey = normalizedDedupeKey(for: article)
            if seenKeys.insert(dedupeKey).inserted {
                uniqueArticles.append(article)
            }
        }

        return uniqueArticles
    }

    private func normalizedDedupeKey(for article: DragonParsedArticle) -> String {
        let link = article.link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !link.isEmpty {
            return "link:\(link)"
        }

        let id = article.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !id.isEmpty {
            return "id:\(id)"
        }

        let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "title:\(title)"
    }

    private static func fetchFeed(
        _ feed: DragonRSSSourceDescriptor,
        session: URLSession,
        parser: DragonRSSParser
    ) async -> FeedOutcome {
        let fetchedAt = Date()
        guard let url = feed.url else {
            return FeedOutcome(
                articles: [],
                failureMessage: DragonRSSArticleSourceError.invalidFeedURL(feed.feedURL).localizedDescription,
                status: DragonRSSSourceFetchStatus(
                    sourceID: feed.id,
                    sourceName: feed.name,
                    feedURL: feed.feedURL,
                    status: "invalid_url",
                    itemCount: 0,
                    fetchedAt: fetchedAt,
                    errorMessage: DragonRSSArticleSourceError.invalidFeedURL(feed.feedURL).localizedDescription
                )
            )
        }

        do {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 20
            )
            request.setValue(
                "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5",
                forHTTPHeaderField: "Accept"
            )
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DragonRSSArticleSourceError.invalidResponse(url)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw DragonRSSArticleSourceError.httpStatus(url, httpResponse.statusCode)
            }

            let parsedFeed = try parser.parse(data: data, fallbackFeedTitle: feed.name)
            let normalizedArticles = parsedFeed.articles.map { article in
                DragonParsedArticle(
                    id: article.id,
                    title: article.title,
                    link: article.link,
                    source: feed.name,
                    publishedAt: article.publishedAt,
                    summary: article.summary,
                    summaryHTML: article.summaryHTML,
                    contentHTML: article.contentHTML,
                    imageURL: article.imageURL,
                    videoURL: article.videoURL
                )
            }

            return FeedOutcome(
                articles: normalizedArticles,
                failureMessage: nil,
                status: DragonRSSSourceFetchStatus(
                    sourceID: feed.id,
                    sourceName: feed.name,
                    feedURL: feed.feedURL,
                    status: "success",
                    itemCount: normalizedArticles.count,
                    fetchedAt: fetchedAt,
                    errorMessage: nil
                )
            )
        } catch {
            return FeedOutcome(
                articles: [],
                failureMessage: error.localizedDescription,
                status: DragonRSSSourceFetchStatus(
                    sourceID: feed.id,
                    sourceName: feed.name,
                    feedURL: feed.feedURL,
                    status: "failed",
                    itemCount: 0,
                    fetchedAt: fetchedAt,
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private static func articleSort(lhs: DragonParsedArticle, rhs: DragonParsedArticle) -> Bool {
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (leftDate?, rightDate?):
            if leftDate != rightDate {
                return leftDate > rightDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func makeArticle(from article: DragonParsedArticle) -> DragonArticle {
        DragonArticle(
            id: article.id,
            title: article.title,
            source: article.source,
            url: article.link,
            original_url: article.link,
            canonical_url: article.link,
            published_at: article.publishedAt.map { publishedISO8601Formatter.string(from: $0) } ?? "",
            saved_at: "",
            excerpt: article.summary,
            image: article.imageURL,
            thumbnail: article.imageURL,
            media_url: article.videoURL,
            video_url: article.videoURL,
            video_embed_url: article.videoURL,
            status: "",
            read_state: "",
            fulltext_status: DragonArticleFulltextStatus(
                status: "native_rss_preview",
                display_label: "",
                display_message: "",
                next_action: "load_full_article",
                safe_error: ""
            ),
            content_text: "",
            content_html: article.contentHTML.isEmpty ? article.summaryHTML : article.contentHTML
        )
    }

    private static let publishedISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct FeedOutcome: Sendable {
    let articles: [DragonParsedArticle]
    let failureMessage: String?
    let status: DragonRSSSourceFetchStatus
}
