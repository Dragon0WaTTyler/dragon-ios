import Foundation

enum DragonMoviesLoadSource: String, Codable {
    case api
    case notion
    case cache
    case bundledSnapshot
    case failedUsingCache
    case empty

    var displayLabel: String {
        switch self {
        case .api:
            return "Legacy API"
        case .notion:
            return "Notion"
        case .cache:
            return "Cache"
        case .bundledSnapshot:
            return "Bundled snapshot"
        case .failedUsingCache:
            return "Failed using cache"
        case .empty:
            return "Empty"
        }
    }
}

struct DragonCachedMoviesResult {
    let response: DragonMoviesResponse
    let cachedAt: Date
    let source: DragonMoviesLoadSource
    let backendURL: String
    let pageCount: Int
}

struct DragonMoviesRefreshResult {
    let response: DragonMoviesResponse
    let refreshedAt: Date
    let source: DragonMoviesLoadSource
    let backendURL: String
    let pageCount: Int
}

protocol DragonMoviesDataSource {
    var sourceLabel: String { get }
    var isConfigured: Bool { get }

    func loadCachedMovies(pageLimit: Int, maxCatalogCount: Int) async -> DragonCachedMoviesResult?
    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult
    func loadBundledFallback(maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult?
}

protocol DragonMoviesPagingClient {
    func fetchMovies(limit: Int, offset: Int, allowsCaching: Bool) async throws -> DragonAPIFetchResult<DragonMoviesResponse>
}

protocol DragonMoviesRemoteCatalogLoader {
    var isConfigured: Bool { get }
    var cacheIdentity: String { get }
    var fallbackSourceLabel: String { get }

    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult
}

extension DragonAPIClient: DragonMoviesPagingClient {}

enum DragonMoviesDataSourceError: LocalizedError {
    case backendReturnedNotOK
    case notionNotConfigured

    var errorDescription: String? {
        switch self {
        case .backendReturnedNotOK:
            return "Backend returned an invalid movie catalog."
        case .notionNotConfigured:
            return "Notion Movies is not configured."
        }
    }
}

final class DragonDefaultMoviesDataSource: DragonMoviesDataSource {
    private let notionLoader: DragonMoviesRemoteCatalogLoader
    private let responseCache: DragonResponseCache
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        notionLoader: DragonMoviesRemoteCatalogLoader = DragonNotionMoviesDataSource(),
        responseCache: DragonResponseCache = .shared
    ) {
        self.notionLoader = notionLoader
        self.responseCache = responseCache

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedMovies(pageLimit: Int, maxCatalogCount: Int) async -> DragonCachedMoviesResult? {
        let cacheURL = dragonMoviesCacheURL(
            pageLimit: pageLimit,
            maxCatalogCount: maxCatalogCount,
            cacheIdentity: notionLoader.cacheIdentity
        )

        guard let cachedResponse = await responseCache.load(for: cacheURL),
              let payload = try? decoder.decode(DragonCachedMoviesPayload.self, from: cachedResponse.data) else {
            return nil
        }

        return DragonCachedMoviesResult(
            response: payload.response,
            cachedAt: cachedResponse.metadata.cachedAt,
            source: .cache,
            backendURL: payload.backendURL,
            pageCount: payload.pageCount
        )
    }

    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult {
        guard notionLoader.isConfigured else {
            throw DragonMoviesDataSourceError.notionNotConfigured
        }

        let result = try await notionLoader.refreshMovies(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount)

        if !result.response.items.isEmpty {
            await save(
                response: result.response,
                pageLimit: pageLimit,
                maxCatalogCount: maxCatalogCount,
                cacheIdentity: notionLoader.cacheIdentity,
                backendURL: result.backendURL,
                pageCount: result.pageCount
            )
        }

        return result
    }

    func loadBundledFallback(maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult? {
        nil
    }

    var sourceLabel: String {
        notionLoader.isConfigured ? notionLoader.fallbackSourceLabel : ""
    }

    var isConfigured: Bool {
        notionLoader.isConfigured
    }

    private func save(
        response: DragonMoviesResponse,
        pageLimit: Int,
        maxCatalogCount: Int,
        cacheIdentity: String,
        backendURL: String,
        pageCount: Int
    ) async {
        guard !response.items.isEmpty else {
            return
        }

        let payload = DragonCachedMoviesPayload(
            response: response,
            backendURL: backendURL,
            pageCount: pageCount
        )

        guard let data = try? encoder.encode(payload) else {
            return
        }

        await responseCache.save(
            data: data,
            for: dragonMoviesCacheURL(
                pageLimit: pageLimit,
                maxCatalogCount: maxCatalogCount,
                cacheIdentity: cacheIdentity
            )
        )
    }
}

final class DragonLegacyAPIMoviesDataSource: DragonMoviesRemoteCatalogLoader {
    private let client: DragonMoviesPagingClient
    private let backendBaseURLProvider: () -> String

    init(
        client: DragonMoviesPagingClient = DragonAPIClient.shared,
        backendBaseURLProvider: @escaping () -> String = currentDragonBackendBaseURL
    ) {
        self.client = client
        self.backendBaseURLProvider = backendBaseURLProvider
    }

    var isConfigured: Bool {
        true
    }

    var cacheIdentity: String {
        "legacy-api|\(resolvedBackendBaseURL())"
    }

    var fallbackSourceLabel: String {
        resolvedBackendBaseURL()
    }

    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult {
        let backendURL = resolvedBackendBaseURL()
        var mergedMovies: [DragonMovie] = []
        var seenMovieIDs = Set<String>()
        var nextOffset = 0
        var pagesLoaded = 0
        var resolvedTotal: Int?
        var apiVersion = "v1"
        let maximumPageRequests = max(1, Int(ceil(Double(maxCatalogCount) / Double(max(pageLimit, 1)))) + 2)

        while mergedMovies.count < maxCatalogCount && pagesLoaded < maximumPageRequests {
            let result = try await client.fetchMovies(limit: pageLimit, offset: nextOffset, allowsCaching: false)
            let response = result.value

            guard response.ok else {
                throw DragonMoviesDataSourceError.backendReturnedNotOK
            }

            apiVersion = response.api_version
            pagesLoaded += 1

            if response.total > 0 {
                resolvedTotal = max(resolvedTotal ?? 0, response.total)
            } else if response.count > 0 {
                resolvedTotal = max(resolvedTotal ?? 0, mergedMovies.count + response.count)
            }

            let countBeforeMerge = mergedMovies.count
            dragonMergeMovies(response.items, into: &mergedMovies, seenIDs: &seenMovieIDs)
            if !response.items.isEmpty && mergedMovies.count == countBeforeMerge {
                break
            }

            if !dragonShouldContinuePaging(
                response: response,
                requestLimit: pageLimit,
                currentOffset: nextOffset,
                loadedCount: mergedMovies.count,
                maxCatalogCount: maxCatalogCount,
                total: resolvedTotal
            ) {
                break
            }

            guard let candidateNextOffset = dragonResolveNextOffset(
                response: response,
                requestLimit: pageLimit,
                currentOffset: nextOffset
            ) else {
                break
            }

            if candidateNextOffset <= nextOffset {
                break
            }

            nextOffset = candidateNextOffset
        }

        let response = DragonMoviesResponse(
            api_version: apiVersion,
            ok: true,
            items: mergedMovies,
            count: mergedMovies.count,
            total: resolvedTotal ?? mergedMovies.count,
            limit: pageLimit,
            offset: 0,
            has_more: false,
            next_offset: nil
        )

        return DragonMoviesRefreshResult(
            response: response,
            refreshedAt: Date(),
            source: response.items.isEmpty ? .empty : .api,
            backendURL: backendURL,
            pageCount: max(pagesLoaded, 1)
        )
    }

    private func resolvedBackendBaseURL() -> String {
        normalizeDragonBackendBaseURL(backendBaseURLProvider()) ?? dragonDefaultBackendBaseURL
    }
}

func dragonMoviesCacheURL(pageLimit: Int, maxCatalogCount: Int, cacheIdentity: String) -> URL {
    var components = URLComponents()
    components.scheme = "dragon-cache"
    components.host = DragonResponseCacheDomain.movies.rawValue
    components.path = "/catalog-v2"
    components.queryItems = [
        URLQueryItem(name: "source", value: cacheIdentity),
        URLQueryItem(name: "page_limit", value: String(pageLimit)),
        URLQueryItem(name: "max_catalog_count", value: String(maxCatalogCount))
    ]

    return components.url
        ?? URL(string: "dragon-cache://movies/catalog-v2?page_limit=\(pageLimit)&max_catalog_count=\(maxCatalogCount)")!
}

func dragonMergeMovies(_ incomingMovies: [DragonMovie], into mergedMovies: inout [DragonMovie], seenIDs: inout Set<String>) {
    for movie in incomingMovies {
        let normalizedID = dragonStableMovieDedupeKey(for: movie)
        guard !normalizedID.isEmpty, !seenIDs.contains(normalizedID) else {
            continue
        }

        seenIDs.insert(normalizedID)
        mergedMovies.append(movie)
    }
}

func dragonStableMovieDedupeKey(for movie: DragonMovie) -> String {
    let normalizedID = movie.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !normalizedID.isEmpty {
        return normalizedID
    }

    let fallbackParts = [
        movie.title,
        movie.year,
        movie.poster
    ]
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    .filter { !$0.isEmpty }

    return fallbackParts.joined(separator: "|")
}

func dragonShouldContinuePaging(
    response: DragonMoviesResponse,
    requestLimit: Int,
    currentOffset: Int,
    loadedCount: Int,
    maxCatalogCount: Int,
    total: Int?
) -> Bool {
    if loadedCount >= maxCatalogCount {
        return false
    }

    if response.items.isEmpty {
        return false
    }

    if let total, total > 0, loadedCount >= total {
        return false
    }

    if response.has_more {
        return true
    }

    if let nextOffset = response.next_offset, nextOffset > currentOffset {
        return true
    }

    return response.items.count >= requestLimit
}

func dragonResolveNextOffset(
    response: DragonMoviesResponse,
    requestLimit: Int,
    currentOffset: Int
) -> Int? {
    if let nextOffset = response.next_offset, nextOffset > currentOffset {
        return nextOffset
    }

    let step = max(response.items.count, response.limit ?? requestLimit, 1)
    guard response.has_more || response.items.count >= requestLimit else {
        return nil
    }

    return currentOffset + step
}

func dragonIsSnapshotFallback(_ source: DragonResponseSource) -> Bool {
    switch source {
    case .snapshot, .remoteSnapshot, .cachedSnapshot, .bundledSnapshot:
        return true
    case .network, .cache:
        return false
    }
}

private struct DragonCachedMoviesPayload: Codable {
    let response: DragonMoviesResponse
    let backendURL: String
    let pageCount: Int
}
