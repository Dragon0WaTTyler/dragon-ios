import Foundation

struct DragonRSSFeedDescriptor: Sendable {
    let title: String
    let url: URL
}

enum DragonArticlesFeedRegistry {
    static let v1Feeds: [DragonRSSFeedDescriptor] = [
        DragonRSSFeedDescriptor(
            title: "Apple Developer News",
            url: URL(string: "https://developer.apple.com/news/rss/news.rss")!
        ),
        DragonRSSFeedDescriptor(
            title: "BBC World",
            url: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!
        ),
        DragonRSSFeedDescriptor(
            title: "Martin Fowler",
            url: URL(string: "https://martinfowler.com/feed.atom")!
        )
    ]
}

enum DragonRSSArticleSourceError: LocalizedError {
    case emptyRegistry
    case noArticlesAvailable([String])
    case invalidResponse(URL)
    case httpStatus(URL, Int)

    var errorDescription: String? {
        switch self {
        case .emptyRegistry:
            return "No RSS feeds are configured."
        case .noArticlesAvailable(let failures):
            if failures.isEmpty {
                return "No articles were available from the configured feeds."
            }
            return failures.joined(separator: " ")
        case .invalidResponse(let url):
            return "Invalid feed response from \(url.host() ?? url.absoluteString)."
        case .httpStatus(let url, let statusCode):
            return "Feed \(url.host() ?? url.absoluteString) returned HTTP \(statusCode)."
        }
    }
}

final class DragonRSSArticleSource {
    private let session: URLSession
    private let feeds: [DragonRSSFeedDescriptor]
    private let parser: DragonRSSParser

    init(
        session: URLSession = .shared,
        feeds: [DragonRSSFeedDescriptor] = DragonArticlesFeedRegistry.v1Feeds,
        parser: DragonRSSParser = DragonRSSParser()
    ) {
        self.session = session
        self.feeds = feeds
        self.parser = parser
    }

    func fetchArticles(limit: Int) async throws -> DragonArticlesResponse {
        guard !feeds.isEmpty else {
            throw DragonRSSArticleSourceError.emptyRegistry
        }

        let outcomes = await withTaskGroup(of: FeedOutcome.self, returning: [FeedOutcome].self) { group in
            for feed in feeds {
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

        let uniqueArticles = deduplicatedArticles(parsedArticles)
        let limitedArticles = Array(uniqueArticles.prefix(max(limit, 0)))

        guard !limitedArticles.isEmpty else {
            let failures = outcomes.compactMap(\.failureMessage)
            throw DragonRSSArticleSourceError.noArticlesAvailable(failures)
        }

        return DragonArticlesResponse(
            api_version: "rss-v1",
            ok: true,
            items: limitedArticles.map(Self.makeArticle(from:)),
            count: limitedArticles.count
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
        _ feed: DragonRSSFeedDescriptor,
        session: URLSession,
        parser: DragonRSSParser
    ) async -> FeedOutcome {
        do {
            var request = URLRequest(
                url: feed.url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 20
            )
            request.setValue(
                "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5",
                forHTTPHeaderField: "Accept"
            )

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DragonRSSArticleSourceError.invalidResponse(feed.url)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw DragonRSSArticleSourceError.httpStatus(feed.url, httpResponse.statusCode)
            }

            let parsedFeed = try parser.parse(data: data, fallbackFeedTitle: feed.title)
            return FeedOutcome(articles: parsedFeed.articles, failureMessage: nil)
        } catch {
            return FeedOutcome(
                articles: [],
                failureMessage: error.localizedDescription
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
            published_at: article.publishedAt.map { publishedISO8601Formatter.string(from: $0) } ?? "",
            saved_at: "",
            excerpt: article.summary,
            status: "",
            read_state: ""
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
}
