import Foundation

enum DragonArticlesRefreshPhase: Equatable {
    case idle
    case cached
    case refreshing
    case refreshed
    case failedUsingCache
    case empty
}

enum DragonArticlesRefreshSource: String, Codable {
    case directRSS
    case remoteFallback

    var liveDisplayLabel: String {
        switch self {
        case .directRSS:
            return "Direct RSS"
        case .remoteFallback:
            return "API fallback"
        }
    }

    var cacheDisplayLabel: String {
        switch self {
        case .directRSS:
            return "Direct RSS cache"
        case .remoteFallback:
            return "API fallback cache"
        }
    }
}

struct DragonCachedArticlesResult {
    let response: DragonArticlesResponse
    let cachedAt: Date
    let source: DragonArticlesRefreshSource
}

struct DragonArticlesRefreshResult {
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
            return "Direct RSS refresh failed (\(primaryError.localizedDescription)). API fallback also failed (\(fallbackError.localizedDescription))."
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
        remoteFallback: DragonArticlesFetching? = DragonRemoteDataSource.shared,
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
        let directCacheURL = directCacheURL(for: limit)
        let directCachedResult = await loadCachedArticles(cacheURL: directCacheURL)

        if let directCachedResult, !directCachedResult.response.items.isEmpty {
            return directCachedResult
        }

        let backendURL = resolvedBackendBaseURL()
        let fallbackCachedResult = await loadCachedArticles(
            cacheURL: fallbackCacheURL(for: limit, backendURL: backendURL)
        )

        return fallbackCachedResult ?? directCachedResult
    }

    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult {
        do {
            let response = try await rssSource.fetchArticles(limit: limit)
            let refreshedAt = Date()
            await save(response: response, cacheURL: directCacheURL(for: limit), source: .directRSS)
            return DragonArticlesRefreshResult(
                response: response,
                refreshedAt: refreshedAt,
                source: .directRSS
            )
        } catch let primaryError {
            guard !(await hasUsableDirectCache(limit: limit)) else {
                throw primaryError
            }

            guard let remoteFallback else {
                throw primaryError
            }

            let backendURL = resolvedBackendBaseURL()

            do {
                let fallbackResult = try await remoteFallback.fetchArticles(limit: limit)
                let response = fallbackResult.value
                let refreshedAt = Date()

                await save(
                    response: response,
                    cacheURL: fallbackCacheURL(for: limit, backendURL: backendURL),
                    source: .remoteFallback
                )

                return DragonArticlesRefreshResult(
                    response: response,
                    refreshedAt: refreshedAt,
                    source: .remoteFallback
                )
            } catch let fallbackError {
                throw DragonArticlesDataSourceError.refreshFailed(
                    primaryError: primaryError,
                    fallbackError: fallbackError
                )
            }
        }
    }

    private func hasUsableDirectCache(limit: Int) async -> Bool {
        guard let cachedResult = await loadCachedArticles(cacheURL: directCacheURL(for: limit)) else {
            return false
        }

        return !cachedResult.response.items.isEmpty
    }

    private func loadCachedArticles(cacheURL: URL) async -> DragonCachedArticlesResult? {
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

    private func save(
        response: DragonArticlesResponse,
        cacheURL: URL,
        source: DragonArticlesRefreshSource
    ) async {
        let payload = DragonCachedArticlesPayload(response: response, source: source)
        guard let data = try? encoder.encode(payload) else {
            return
        }

        await responseCache.save(data: data, for: cacheURL)
    }

    private func directCacheURL(for limit: Int) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = DragonResponseCacheDomain.articles.rawValue
        components.path = "/direct-rss-v1"
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        return components.url ?? URL(string: "dragon-cache://articles/direct-rss-v1?limit=\(limit)")!
    }

    private func fallbackCacheURL(for limit: Int, backendURL: String) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = DragonResponseCacheDomain.articles.rawValue
        components.path = "/api-fallback-v1"
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "backend", value: backendURL)
        ]

        return components.url
            ?? URL(string: "dragon-cache://articles/api-fallback-v1?limit=\(limit)")!
    }

    private func resolvedBackendBaseURL() -> String {
        normalizeDragonBackendBaseURL(backendBaseURLProvider()) ?? dragonDefaultBackendBaseURL
    }
}

private struct DragonCachedArticlesPayload: Codable {
    let response: DragonArticlesResponse
    let source: DragonArticlesRefreshSource
}
