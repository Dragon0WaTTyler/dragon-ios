import Foundation
import Combine

@MainActor
final class DragonMoviesViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
        case partialLoaded(String)
    }

    @Published private(set) var state: State
    @Published private(set) var movies: [DragonMovie]
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorText: String
    @Published private(set) var statusText: String
    @Published private(set) var backendTotal: Int?
    @Published private(set) var fetchedPageCount: Int
    @Published private(set) var loadSource: DragonMoviesLoadSource
    @Published private(set) var backendURLText: String

    private let dataSource: DragonMoviesDataSource
    private let pageLimit: Int
    private let maxCatalogCount: Int
    private var loadGeneration = 0

    init(
        dataSource: DragonMoviesDataSource,
        pageLimit: Int = 100,
        maxCatalogCount: Int = 800,
        initialState: State = .idle,
        initialMovies: [DragonMovie] = [],
        initialLastUpdatedAt: Date? = nil,
        initialErrorText: String = "",
        initialStatusText: String = "",
        initialBackendTotal: Int? = nil,
        initialFetchedPageCount: Int = 0,
        initialLoadSource: DragonMoviesLoadSource = .empty,
        initialBackendURLText: String = ""
    ) {
        self.dataSource = dataSource
        self.pageLimit = pageLimit
        self.maxCatalogCount = maxCatalogCount
        self.state = initialState
        self.movies = initialMovies
        self.lastUpdatedAt = initialLastUpdatedAt
        self.errorText = initialErrorText
        self.statusText = initialStatusText
        self.backendTotal = initialBackendTotal
        self.fetchedPageCount = initialFetchedPageCount
        self.loadSource = initialLoadSource
        self.backendURLText = initialBackendURLText
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    var hasVisibleContent: Bool {
        !movies.isEmpty
    }

    var loadedCount: Int {
        movies.count
    }

    func loadMovies() async {
        loadGeneration += 1
        let generation = loadGeneration
        var cachedCatalogWasLoaded = false

        errorText = ""

        if let cachedResult = await dataSource.loadCachedMovies(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount) {
            cachedCatalogWasLoaded = true
            applyLoadedCatalog(
                response: cachedResult.response,
                pageCount: cachedResult.pageCount,
                refreshedAt: cachedResult.cachedAt,
                source: .cache,
                backendURL: cachedResult.backendURL
            )
            state = cachedResult.response.items.isEmpty ? .loading : .loaded
            statusText = sourceStatusLine(
                source: .cache,
                movieCount: cachedResult.response.items.count,
                backendURL: cachedResult.backendURL,
                detail: "Refreshing live data"
            )
        } else {
            movies = []
            lastUpdatedAt = nil
            state = .loading
            loadSource = .empty
            backendURLText = normalizeDragonBackendBaseURL(currentDragonBackendBaseURL()) ?? dragonDefaultBackendBaseURL
            statusText = sourceStatusLine(
                source: .empty,
                movieCount: 0,
                backendURL: backendURLText,
                detail: "Loading live data"
            )
            backendTotal = nil
            fetchedPageCount = 0
        }

        do {
            let result = try await dataSource.refreshMovies(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount)
            guard generation == loadGeneration else {
                return
            }

            if result.response.items.isEmpty {
                if hasVisibleContent {
                    loadSource = .failedUsingCache
                    statusText = sourceStatusLine(
                        source: .failedUsingCache,
                        movieCount: movies.count,
                        backendURL: backendURLText,
                        detail: "Live refresh returned no movies"
                    )
                    errorText = "Live refresh returned no movies. Showing cached catalog."
                    state = .partialLoaded(errorText)
                } else {
                    applyLoadedCatalog(
                        response: result.response,
                        pageCount: result.pageCount,
                        refreshedAt: result.refreshedAt,
                        source: .empty,
                        backendURL: result.backendURL
                    )
                    statusText = sourceStatusLine(
                        source: .empty,
                        movieCount: 0,
                        backendURL: result.backendURL
                    )
                    state = .empty
                }
                return
            }

            applyLoadedCatalog(
                response: result.response,
                pageCount: result.pageCount,
                refreshedAt: result.refreshedAt,
                source: result.source,
                backendURL: result.backendURL
            )

            statusText = sourceStatusLine(
                source: result.source,
                movieCount: result.response.items.count,
                backendURL: result.backendURL,
                detail: result.pageCount > 0 ? "\(result.pageCount) page\(result.pageCount == 1 ? "" : "s")" : nil
            )
            errorText = ""
            state = .loaded
        } catch {
            guard generation == loadGeneration else {
                return
            }

            let message = dragonUserFacingMessage(for: error)

            if cachedCatalogWasLoaded && hasVisibleContent {
                loadSource = .failedUsingCache
                statusText = sourceStatusLine(
                    source: .failedUsingCache,
                    movieCount: movies.count,
                    backendURL: backendURLText,
                    detail: "Showing cached data"
                )
                errorText = message
                state = .partialLoaded(message)
                return
            }

            if let fallbackResult = try? await dataSource.loadBundledFallback(maxCatalogCount: maxCatalogCount),
               generation == loadGeneration,
               !fallbackResult.response.items.isEmpty {
                applyLoadedCatalog(
                    response: fallbackResult.response,
                    pageCount: fallbackResult.pageCount,
                    refreshedAt: fallbackResult.refreshedAt,
                    source: .bundledSnapshot,
                    backendURL: fallbackResult.backendURL
                )
                statusText = sourceStatusLine(
                    source: .bundledSnapshot,
                    movieCount: fallbackResult.response.items.count,
                    backendURL: fallbackResult.backendURL,
                    detail: "Live backend unavailable"
                )
                errorText = message
                state = .partialLoaded(message)
            } else {
                loadSource = .empty
                backendURLText = normalizeDragonBackendBaseURL(currentDragonBackendBaseURL()) ?? dragonDefaultBackendBaseURL
                statusText = sourceStatusLine(
                    source: .empty,
                    movieCount: 0,
                    backendURL: backendURLText
                )
                errorText = message
                state = .failed(message)
            }
        }
    }

    private func applyLoadedCatalog(
        response: DragonMoviesResponse,
        pageCount: Int,
        refreshedAt: Date,
        source: DragonMoviesLoadSource,
        backendURL: String
    ) {
        movies = response.items
        backendTotal = response.total > 0 ? response.total : response.count
        fetchedPageCount = pageCount
        lastUpdatedAt = refreshedAt
        loadSource = source
        backendURLText = backendURL
    }

    private func sourceStatusLine(
        source: DragonMoviesLoadSource,
        movieCount: Int,
        backendURL: String,
        detail: String? = nil
    ) -> String {
        let movieLabel = movieCount == 1 ? "movie" : "movies"
        var parts = [
            "Source: \(source.displayLabel)",
            "\(movieCount) \(movieLabel)"
        ]

        if !backendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Backend: \(backendURL)")
        }

        if let detail, !detail.isEmpty {
            parts.append(detail)
        }

        return parts.joined(separator: " • ")
    }
}
