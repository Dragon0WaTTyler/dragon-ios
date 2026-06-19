import Foundation

enum DragonArticlesRefreshPhase: Equatable {
    case idle
    case cached
    case refreshing
    case refreshed
    case failedUsingCache
    case empty
}

enum DragonArticlesRefreshSource: String, Codable, Sendable {
    case directRSS
    case remoteFallback

    var refreshedStatusText: String {
        switch self {
        case .directRSS:
            return "Refreshed from direct RSS feeds."
        case .remoteFallback:
            return "Refreshed using the backend fallback."
        }
    }
}

struct DragonCachedArticlesResult: Sendable {
    let response: DragonArticlesResponse
    let cachedAt: Date
    let source: DragonArticlesRefreshSource
}

struct DragonArticlesRefreshResult: Sendable {
    let response: DragonArticlesResponse
    let refreshedAt: Date
    let source: DragonArticlesRefreshSource
}

protocol DragonArticlesDataSource {
    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult?
    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult
}

enum DragonArticlesDataSourceError: LocalizedError {
    case refreshFailed(primaryError: Error, fallbackError: Error)

    var errorDescription: String? {
        switch self {
        case .refreshFailed(let primaryError, let fallbackError):
            return "Direct RSS refresh failed (\(primaryError.localizedDescription)). Backend fallback also failed (\(fallbackError.localizedDescription))."
        }
    }
}

final class DragonDefaultArticlesDataSource: DragonArticlesDataSource {
    private let rssSource: DragonRSSArticleSource
    private let remoteFallback: DragonArticlesFetching?
    private let responseCache: DragonResponseCache
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rssSource: DragonRSSArticleSource = DragonRSSArticleSource(),
        remoteFallback: DragonArticlesFetching? = DragonAPIClient.shared,
        responseCache: DragonResponseCache = .shared
    ) {
        self.rssSource = rssSource
        self.remoteFallback = remoteFallback
        self.responseCache = responseCache

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult? {
        let cacheURL = cacheURL(for: limit)

        guard let cachedResponse = await responseCache.load(for: cacheURL),
              let payload = try? decoder.decode(DragonCachedArticlesPayload.self, from: cachedResponse.data) else {
            return nil
        }

        return DragonCachedArticlesResult(
            response: payload.response,
            cachedAt: cachedResponse.metadata.cachedAt,
            source: payload.source
        )
    }

    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult {
        do {
            let response = try await rssSource.fetchArticles(limit: limit)
            let refreshedAt = Date()
            await save(response: response, limit: limit, source: .directRSS)
            return DragonArticlesRefreshResult(response: response, refreshedAt: refreshedAt, source: .directRSS)
        } catch let primaryError {
            guard let remoteFallback else {
                throw primaryError
            }

            do {
                let response = try await remoteFallback.fetchArticles(limit: limit)
                let refreshedAt = Date()
                await save(response: response, limit: limit, source: .remoteFallback)
                return DragonArticlesRefreshResult(response: response, refreshedAt: refreshedAt, source: .remoteFallback)
            } catch let fallbackError {
                throw DragonArticlesDataSourceError.refreshFailed(
                    primaryError: primaryError,
                    fallbackError: fallbackError
                )
            }
        }
    }

    private func save(response: DragonArticlesResponse, limit: Int, source: DragonArticlesRefreshSource) async {
        let payload = DragonCachedArticlesPayload(response: response, source: source)
        guard let data = try? encoder.encode(payload) else {
            return
        }

        await responseCache.save(data: data, for: cacheURL(for: limit))
    }

    private func cacheURL(for limit: Int) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "articles"
        components.path = "/rss-v1"
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        return components.url ?? URL(string: "dragon-cache://articles/rss-v1?limit=\(limit)")!
    }
}

private struct DragonCachedArticlesPayload: Codable {
    let response: DragonArticlesResponse
    let source: DragonArticlesRefreshSource
}
