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
    private let backendBaseURLProvider: () -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rssSource: DragonRSSArticleSource = DragonRSSArticleSource(),
        remoteFallback: DragonArticlesFetching? = DragonAPIClient.shared,
        responseCache: DragonResponseCache = .shared,
        backendBaseURLProvider: @escaping () -> String = currentDragonBackendBaseURL
    ) {
        self.rssSource = rssSource
        self.remoteFallback = remoteFallback
        self.responseCache = responseCache
        self.backendBaseURLProvider = backendBaseURLProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult? {
        if let directCachedResult = await loadCachedArticles(limit: limit, cacheURL: directCacheURL(for: limit)) {
            return directCachedResult
        }

        let backendURL = resolvedBackendBaseURL()
        return await loadCachedArticles(limit: limit, cacheURL: fallbackCacheURL(for: limit, backendURL: backendURL))
    }

    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult {
        do {
            let response = try await rssSource.fetchArticles(limit: limit)
            let refreshedAt = Date()
            await save(response: response, cacheURL: directCacheURL(for: limit), source: .directRSS)
            return DragonArticlesRefreshResult(response: response, refreshedAt: refreshedAt, source: .directRSS)
        } catch let primaryError {
            let backendURL = resolvedBackendBaseURL()

            if await loadCachedArticles(limit: limit, cacheURL: directCacheURL(for: limit)) != nil {
                throw primaryError
            }

            guard let remoteFallback else {
                throw primaryError
            }

            do {
                let response = try await remoteFallback.fetchArticles(limit: limit)
                let refreshedAt = Date()
                await save(
                    response: response,
                    cacheURL: fallbackCacheURL(for: limit, backendURL: backendURL),
                    source: .remoteFallback
                )
                return DragonArticlesRefreshResult(response: response, refreshedAt: refreshedAt, source: .remoteFallback)
            } catch let fallbackError {
                throw DragonArticlesDataSourceError.refreshFailed(
                    primaryError: primaryError,
                    fallbackError: fallbackError
                )
            }
        }
    }

    private func loadCachedArticles(limit: Int, cacheURL: URL) async -> DragonCachedArticlesResult? {
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

    private func save(response: DragonArticlesResponse, cacheURL: URL, source: DragonArticlesRefreshSource) async {
        let payload = DragonCachedArticlesPayload(response: response, source: source)
        guard let data = try? encoder.encode(payload) else {
            return
        }

        await responseCache.save(data: data, for: cacheURL)
    }

    private func directCacheURL(for limit: Int) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "articles"
        components.path = "/direct-rss-v2"
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        return components.url ?? URL(string: "dragon-cache://articles/direct-rss-v2?limit=\(limit)")!
    }

    private func fallbackCacheURL(for limit: Int, backendURL: String) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "articles"
        components.path = "/api-fallback-v2"
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "backend", value: backendURL)
        ]

        return components.url
            ?? URL(string: "dragon-cache://articles/api-fallback-v2?limit=\(limit)")!
    }

    private func resolvedBackendBaseURL() -> String {
        normalizeDragonBackendBaseURL(backendBaseURLProvider()) ?? dragonDefaultBackendBaseURL
    }
}

private struct DragonCachedArticlesPayload: Codable {
    let response: DragonArticlesResponse
    let source: DragonArticlesRefreshSource
}
