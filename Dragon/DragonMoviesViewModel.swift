import Foundation
import Combine
import OSLog

@MainActor
final class DragonMoviesViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loadingMore
        case loaded
        case empty
        case failed(String)
        case partialLoaded(String)
    }

    struct Rail: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let movies: [DragonMovie]
    }

    @Published private(set) var state: State
    @Published private(set) var movies: [DragonMovie]
    @Published private(set) var featuredMovie: DragonMovie?
    @Published private(set) var rails: [Rail]
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
    private let logger = Logger(subsystem: "com.hh.Dragon", category: "Movies")
    private var loadGeneration = 0

    init(
        dataSource: DragonMoviesDataSource = DragonDefaultMoviesDataSource(),
        pageLimit: Int = 100,
        maxCatalogCount: Int = 800,
        initialState: State = .idle,
        initialMovies: [DragonMovie] = [],
        initialFeaturedMovie: DragonMovie? = nil,
        initialRails: [Rail] = [],
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
        self.featuredMovie = initialFeaturedMovie
        self.rails = initialRails
        self.lastUpdatedAt = initialLastUpdatedAt
        self.errorText = initialErrorText
        self.statusText = initialStatusText
        self.backendTotal = initialBackendTotal
        self.fetchedPageCount = initialFetchedPageCount
        self.loadSource = initialLoadSource
        self.backendURLText = initialBackendURLText
    }

    var isLoading: Bool {
        switch state {
        case .loading, .loadingMore:
            return true
        case .idle, .loaded, .empty, .failed, .partialLoaded:
            return false
        }
    }

    var isLoadingMore: Bool {
        if case .loadingMore = state {
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

    var progressLabel: String {
        if let backendTotal, backendTotal > 0 {
            return "\(loadedCount) of \(backendTotal) loaded"
        }

        return "\(loadedCount) loaded"
    }

    var catalogCountLabel: String {
        if let backendTotal, backendTotal > 0 {
            return "\(loadedCount) / \(backendTotal) titles"
        }

        return "\(loadedCount) titles"
    }

    var isCatalogComplete: Bool {
        if let backendTotal, backendTotal > 0 {
            return loadedCount >= backendTotal
        }

        return !isLoadingMore && hasVisibleContent
    }

    func loadMovies() async {
        loadGeneration += 1
        let generation = loadGeneration
        errorText = ""

        if let cachedResult = await dataSource.loadCachedMovies(pageLimit: pageLimit, maxCatalogCount: maxCatalogCount) {
            applyLoadedCatalog(
                response: cachedResult.response,
                pageCount: cachedResult.pageCount,
                refreshedAt: cachedResult.cachedAt,
                source: .cache,
                backendURL: cachedResult.backendURL
            )
            state = cachedResult.response.items.isEmpty ? .loading : .loadingMore
            statusText = sourceStatusLine(
                source: .cache,
                movieCount: cachedResult.response.items.count,
                backendURL: cachedResult.backendURL,
                detail: "Refreshing live data"
            )
        } else {
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

            applyLoadedCatalog(
                response: result.response,
                pageCount: result.pageCount,
                refreshedAt: result.refreshedAt,
                source: result.source,
                backendURL: result.backendURL
            )

            if result.response.items.isEmpty {
                statusText = sourceStatusLine(
                    source: .empty,
                    movieCount: 0,
                    backendURL: result.backendURL
                )
                state = .empty
                logSummary(context: "empty")
            } else {
                statusText = sourceStatusLine(
                    source: result.source,
                    movieCount: result.response.items.count,
                    backendURL: result.backendURL,
                    detail: "\(result.pageCount) page\(result.pageCount == 1 ? "" : "s")"
                )
                state = .loaded
                logSummary(context: "loaded")
            }
        } catch {
            guard generation == loadGeneration else {
                return
            }

            let message = "Could not load /api/v1/movies: \(error.localizedDescription)"
            errorText = message

            if hasVisibleContent {
                statusText = sourceStatusLine(
                    source: .cache,
                    movieCount: movies.count,
                    backendURL: backendURLText,
                    detail: "Showing cached data"
                )
                state = .partialLoaded(message)
                logSummary(context: "refresh-failed")
            } else {
                loadSource = .empty
                statusText = sourceStatusLine(
                    source: .empty,
                    movieCount: 0,
                    backendURL: backendURLText
                )
                state = .failed(message)
                logSummary(context: "failed")
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
        featuredMovie = chooseFeaturedMovie(from: response.items)
        rails = buildRails(from: response.items, featuredMovie: featuredMovie)
        backendTotal = response.total > 0 ? response.total : response.count
        fetchedPageCount = pageCount
        lastUpdatedAt = refreshedAt
        loadSource = source
        backendURLText = backendURL
        persistDebugSnapshot()
    }

    private func chooseFeaturedMovie(from movies: [DragonMovie]) -> DragonMovie? {
        movies.enumerated().max { left, right in
            featuredRank(for: left.element, index: left.offset) < featuredRank(for: right.element, index: right.offset)
        }?.element
    }

    private func buildRails(from movies: [DragonMovie], featuredMovie: DragonMovie?) -> [Rail] {
        let featuredID = featuredMovie?.id
        let withoutFeatured = movies.filter { $0.id != featuredID }

        let continueWatching = sortedByProgress(withoutFeatured.filter(\.isInProgress))
        let finished = sortedByScore(withoutFeatured.filter(\.isFinished))
        let topRated = sortedByScore(withoutFeatured)
        let unwatched = sortedByScore(withoutFeatured.filter { !$0.isFinished })
        let watchNextSeed = continueWatching + unwatched + topRated
        let watchNext = uniquePreservingOrder(watchNextSeed)
        let browse = withoutFeatured.isEmpty ? movies : withoutFeatured

        let rails = [
            Rail(
                id: "watch-next",
                title: "Watch Next",
                subtitle: continueWatching.isEmpty ? "A fresh queue from your Dragon library" : "Resume momentum with the strongest next picks",
                movies: Array(watchNext.prefix(24))
            ),
            Rail(
                id: "continue-watching",
                title: "Continue Watching",
                subtitle: "Progress-aware when Dragon exposes watching state",
                movies: Array(continueWatching.prefix(24))
            ),
            Rail(
                id: "finished",
                title: "Finished / Watched",
                subtitle: "Completed titles ready to revisit",
                movies: Array(finished.prefix(24))
            ),
            Rail(
                id: "top-rated",
                title: "Top Rated",
                subtitle: "Locally ranked from Dragon score metadata",
                movies: Array(topRated.prefix(30))
            ),
            Rail(
                id: "browse",
                title: "All Movies / Browse",
                subtitle: progressLabelText(loadedCount: browse.count, total: backendTotal),
                movies: browse
            )
        ]

        return rails.filter { !$0.movies.isEmpty }
    }

    private func sortedByProgress(_ movies: [DragonMovie]) -> [DragonMovie] {
        movies.sorted { left, right in
            let leftProgress = left.progressFraction ?? 0
            let rightProgress = right.progressFraction ?? 0

            if leftProgress != rightProgress {
                return leftProgress > rightProgress
            }

            if left.sortScore != right.sortScore {
                return left.sortScore > right.sortScore
            }

            return left.displayTitle.localizedCaseInsensitiveCompare(right.displayTitle) == .orderedAscending
        }
    }

    private func sortedByScore(_ movies: [DragonMovie]) -> [DragonMovie] {
        movies.sorted { left, right in
            if left.sortScore != right.sortScore {
                return left.sortScore > right.sortScore
            }

            let leftHasArtwork = left.primaryArtworkURL != nil
            let rightHasArtwork = right.primaryArtworkURL != nil
            if leftHasArtwork != rightHasArtwork {
                return leftHasArtwork && !rightHasArtwork
            }

            return left.displayTitle.localizedCaseInsensitiveCompare(right.displayTitle) == .orderedAscending
        }
    }

    private func uniquePreservingOrder(_ movies: [DragonMovie]) -> [DragonMovie] {
        var seen = Set<String>()
        var result: [DragonMovie] = []

        for movie in movies {
            guard !seen.contains(movie.id) else {
                continue
            }

            seen.insert(movie.id)
            result.append(movie)
        }

        return result
    }

    private func featuredRank(for movie: DragonMovie, index: Int) -> Double {
        var score = movie.sortScore

        if movie.isInProgress {
            score += 5
        } else if !movie.isFinished {
            score += 2.5
        }

        if movie.backdropURL != nil {
            score += 2
        } else if movie.posterURL != nil {
            score += 1
        }

        if !movie.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }

        score += Double(max(0, 32 - index)) * 0.02
        return score
    }

    private func progressLabelText(loadedCount: Int, total: Int?) -> String {
        if let total, total > 0 {
            return "\(loadedCount) of \(total)"
        }

        return "\(loadedCount)"
    }

    func sourceStatusLine(
        source: DragonMoviesLoadSource,
        movieCount: Int,
        backendURL: String,
        detail: String? = nil
    ) -> String {
        let countLabel = movieCount == 1 ? "movie" : "movies"
        let backendHost = URL(string: backendURL)?.host ?? backendURL
        var parts = [
            "Source: \(source.displayLabel)",
            "\(movieCount) \(countLabel)"
        ]

        if !backendHost.isEmpty {
            parts.append("Backend: \(backendHost)")
        }

        if let detail, !detail.isEmpty {
            parts.append(detail)
        }

        return parts.joined(separator: " • ")
    }

    private func logSummary(context: String) {
        let summary = "[DragonMovies] context=\(context) state=\(state) backendTotal=\(backendTotal ?? -1) pagesFetched=\(fetchedPageCount) uniqueMoviesLoaded=\(loadedCount) browseCount=\(browseRailCount)"
        print(summary)
        logger.notice("\(summary, privacy: .public)")
        persistDebugSnapshot()
    }

    private var browseRailCount: Int {
        rails.first(where: { $0.id == "browse" })?.movies.count ?? 0
    }

    private func logPageFetch(pageNumber: Int, response: DragonMoviesResponse, resolvedTotal: Int?) {
        let message = "[DragonMovies] page=\(pageNumber) offset=\(response.offset ?? -1) limit=\(response.limit ?? pageLimit) count=\(response.count) total=\(resolvedTotal ?? -1) hasMore=\(response.has_more) nextOffset=\(response.next_offset ?? -1)"
        print(message)
        logger.notice("\(message, privacy: .public)")
    }

    private func persistDebugSnapshot() {
        let defaults = UserDefaults.standard
        defaults.set(loadedCount, forKey: "dragon.movies.debug.loadedCount")
        defaults.set(backendTotal ?? -1, forKey: "dragon.movies.debug.backendTotal")
        defaults.set(fetchedPageCount, forKey: "dragon.movies.debug.pagesFetched")
        defaults.set(browseRailCount, forKey: "dragon.movies.debug.browseCount")
        defaults.set(statusText, forKey: "dragon.movies.debug.statusText")
        defaults.set(loadSource.rawValue, forKey: "dragon.movies.debug.source")
        defaults.set(backendURLText, forKey: "dragon.movies.debug.backendURL")
    }
}
