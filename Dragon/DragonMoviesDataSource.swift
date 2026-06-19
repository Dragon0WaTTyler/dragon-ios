import Foundation

enum DragonMoviesLoadSource: String, Codable, Sendable {
    case api
    case cache
    case bundledSnapshot
    case empty

    var displayLabel: String {
        switch self {
        case .api:
            return "API"
        case .cache:
            return "Cache"
        case .bundledSnapshot:
            return "Bundled Snapshot"
        case .empty:
            return "Empty"
        }
    }
}

struct DragonCachedMoviesResult: Sendable {
    let response: DragonMoviesResponse
    let cachedAt: Date
    let source: DragonMoviesLoadSource
    let backendURL: String
    let pageCount: Int
}

struct DragonMoviesRefreshResult: Sendable {
    let response: DragonMoviesResponse
    let refreshedAt: Date
    let source: DragonMoviesLoadSource
    let backendURL: String
    let pageCount: Int
}

protocol DragonMoviesDataSource {
    func loadCachedMovies(pageLimit: Int, maxCatalogCount: Int) async -> DragonCachedMoviesResult?
    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult
}

final class DragonDefaultMoviesDataSource: DragonMoviesDataSource {
    private let client: DragonMoviesFetching
    private let responseCache: DragonResponseCache
    private let backendBaseURLProvider: () -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        client: DragonMoviesFetching = DragonAPIClient.shared,
        responseCache: DragonResponseCache = .shared,
        backendBaseURLProvider: @escaping () -> String = currentDragonBackendBaseURL
    ) {
        self.client = client
        self.responseCache = responseCache
        self.backendBaseURLProvider = backendBaseURLProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedMovies(pageLimit: Int, maxCatalogCount: Int) async -> DragonCachedMoviesResult? {
        let backendURL = resolvedBackendBaseURL()
        let cacheURL = cacheURL(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount, backendURL: backendURL)

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
        let backendURL = resolvedBackendBaseURL()

        var mergedMovies: [DragonMovie] = []
        var seenMovieIDs = Set<String>()
        var nextOffset = 0
        var pagesLoaded = 0
        var resolvedTotal: Int?
        var apiVersion = "v1"

        while mergedMovies.count < maxCatalogCount {
            let response = try await client.fetchMovies(limit: pageLimit, offset: nextOffset)
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

            merge(response.items, into: &mergedMovies, seenIDs: &seenMovieIDs)

            if !shouldContinuePaging(
                response: response,
                requestLimit: pageLimit,
                currentOffset: nextOffset,
                loadedCount: mergedMovies.count,
                maxCatalogCount: maxCatalogCount,
                total: resolvedTotal
            ) {
                break
            }

            guard let candidateNextOffset = resolveNextOffset(
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

        let refreshedAt = Date()
        await save(
            response: response,
            pageLimit: pageLimit,
            maxCatalogCount: maxCatalogCount,
            backendURL: backendURL,
            pageCount: pagesLoaded
        )

        return DragonMoviesRefreshResult(
            response: response,
            refreshedAt: refreshedAt,
            source: response.items.isEmpty ? .empty : .api,
            backendURL: backendURL,
            pageCount: pagesLoaded
        )
    }

    private func save(
        response: DragonMoviesResponse,
        pageLimit: Int,
        maxCatalogCount: Int,
        backendURL: String,
        pageCount: Int
    ) async {
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
            for: cacheURL(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount, backendURL: backendURL)
        )
    }

    private func cacheURL(pageLimit: Int, maxCatalogCount: Int, backendURL: String) -> URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "movies"
        components.path = "/catalog-v1"
        components.queryItems = [
            URLQueryItem(name: "backend", value: backendURL),
            URLQueryItem(name: "page_limit", value: String(pageLimit)),
            URLQueryItem(name: "max_catalog_count", value: String(maxCatalogCount))
        ]

        return components.url
            ?? URL(string: "dragon-cache://movies/catalog-v1?page_limit=\(pageLimit)&max_catalog_count=\(maxCatalogCount)")!
    }

    private func resolvedBackendBaseURL() -> String {
        normalizeDragonBackendBaseURL(backendBaseURLProvider()) ?? dragonDefaultBackendBaseURL
    }

    private func merge(_ incomingMovies: [DragonMovie], into mergedMovies: inout [DragonMovie], seenIDs: inout Set<String>) {
        for movie in incomingMovies {
            let normalizedID = movie.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedID.isEmpty, !seenIDs.contains(normalizedID) else {
                continue
            }

            seenIDs.insert(normalizedID)
            mergedMovies.append(movie)
        }
    }

    private func shouldContinuePaging(
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

    private func resolveNextOffset(
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
}

private struct DragonCachedMoviesPayload: Codable {
    let response: DragonMoviesResponse
    let backendURL: String
    let pageCount: Int
}

private enum DragonMoviesDataSourceError: LocalizedError {
    case backendReturnedNotOK

    var errorDescription: String? {
        switch self {
        case .backendReturnedNotOK:
            return "Dragon API responded with ok=false."
        }
    }
}
