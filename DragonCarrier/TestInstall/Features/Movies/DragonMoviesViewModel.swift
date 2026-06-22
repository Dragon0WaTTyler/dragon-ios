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
    @Published private(set) var needsConfiguration: Bool

    private let dataSource: DragonMoviesDataSource
    private let pageLimit: Int
    private let maxCatalogCount: Int
    private var loadGeneration = 0
    private let notionNotConfiguredMessage = "Notion Movies is not configured."
    private let noCachedMoviesMessage = "No cached movies available."
    private let configureMoviesMessage = "Configure Movies in Settings."

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
        initialBackendURLText: String = "",
        initialNeedsConfiguration: Bool = false
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
        self.needsConfiguration = initialNeedsConfiguration
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

    var emptyStateTitle: String {
        if needsConfiguration {
            return notionNotConfiguredMessage
        }

        if case .failed = state {
            return "Could not load movies"
        }

        return "No movies found."
    }

    var emptyStateMessage: String {
        if needsConfiguration {
            return "\(noCachedMoviesMessage) \(configureMoviesMessage)"
        }

        if case .failed(let message) = state {
            return message
        }

        return "Pull to refresh to check again."
    }

    var emptyStateButtonTitle: String {
        if case .failed = state {
            return "Try Again"
        }

        return "Reload"
    }

    func loadMovies() async {
        loadGeneration += 1
        let generation = loadGeneration
        var cachedCatalogWasLoaded = false

        errorText = ""
        needsConfiguration = false

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
                detail: dataSource.isConfigured ? "Refreshing live data" : configureMoviesMessage
            )
        } else {
            movies = []
            lastUpdatedAt = nil
            state = .loading
            loadSource = .empty
            backendURLText = ""
            statusText = sourceStatusLine(
                source: .empty,
                movieCount: 0,
                backendURL: backendURLText,
                detail: dataSource.isConfigured ? "Loading live data" : configureMoviesMessage
            )
            backendTotal = nil
            fetchedPageCount = 0
        }

        if !dataSource.isConfigured {
            applyConfigurationState(usingCachedMovies: cachedCatalogWasLoaded && hasVisibleContent)
            return
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

            loadSource = .empty
            backendURLText = ""
            statusText = sourceStatusLine(
                source: .empty,
                movieCount: 0,
                backendURL: backendURLText
            )
            errorText = message
            state = .failed(message)
        }
    }

    private func applyConfigurationState(usingCachedMovies: Bool) {
        needsConfiguration = true

        if usingCachedMovies {
            loadSource = .cache
            statusText = sourceStatusLine(
                source: .cache,
                movieCount: movies.count,
                backendURL: backendURLText,
                detail: configureMoviesMessage
            )
            errorText = notionNotConfiguredMessage
            state = .partialLoaded(notionNotConfiguredMessage)
            return
        }

        loadSource = .empty
        backendURLText = ""
        statusText = sourceStatusLine(
            source: .empty,
            movieCount: 0,
            backendURL: "",
            detail: configureMoviesMessage
        )
        errorText = notionNotConfiguredMessage
        state = .failed(notionNotConfiguredMessage)
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
            parts.append("Location: \(backendURL)")
        }

        if let detail, !detail.isEmpty {
            parts.append(detail)
        }

        return parts.joined(separator: " • ")
    }
}
