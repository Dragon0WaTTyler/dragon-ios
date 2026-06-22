import Foundation

enum DragonArticlesRefreshPhase: Equatable {
    case idle
    case cached
    case refreshing
    case refreshed
    case failedUsingCache
    case empty
}

enum DragonArticlesRefreshSource {
    case nativeRSS
    case cachedArticles

    var displayLabel: String {
        switch self {
        case .nativeRSS:
            return "Native RSS"
        case .cachedArticles:
            return "Articles cache"
        }
    }

    var refreshWarning: String? {
        switch self {
        case .nativeRSS:
            return nil
        case .cachedArticles:
            return "Failed to refresh RSS. Showing saved articles."
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
    let warningMessage: String?
}

protocol DragonArticlesDataSource {
    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult?
    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult
}

final class NativeRSSArticlesDataSource {
    private let session: URLSession
    private let parser: DragonRSSParser
    private let sourceStore: DragonArticlesSourceStore
    private let nowProvider: () -> Date

    init(
        session: URLSession = .shared,
        parser: DragonRSSParser = DragonRSSParser(),
        sourceStore: DragonArticlesSourceStore = DragonArticlesSourceStore(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.parser = parser
        self.sourceStore = sourceStore
        self.nowProvider = nowProvider
    }

    func fetchArticles() async throws -> DragonNativeArticlesFetchResult {
        let rssSource = DragonRSSArticleSource(
            session: session,
            feeds: sourceStore.loadSources(),
            parser: parser,
            nowProvider: nowProvider
        )
        let result = try await rssSource.fetchArticles()

#if DEBUG
        let oldestAgeText: String
        if let oldestDisplayedArticleAgeHours = result.diagnostics.oldestDisplayedArticleAgeHours {
            oldestAgeText = String(format: "%.1fh", oldestDisplayedArticleAgeHours)
        } else {
            oldestAgeText = "n/a"
        }
        print(
            """
            [Articles RSS] feeds=\(result.diagnostics.totalFeedsFetched) \
            parsed=\(result.diagnostics.totalItemsParsed) \
            dated=\(result.diagnostics.totalValidDatedItems) \
            last24h=\(result.diagnostics.totalItemsInside24Hours) \
            oldestDisplayed=\(oldestAgeText)
            """
        )
#endif

        return result
    }
}

final class CachedArticlesDataSource: DragonArticlesDataSource {
    private let native: NativeRSSArticlesDataSource
    private let snapshotStore: DragonSnapshotStore
    private let nowProvider: () -> Date

    init(
        native: NativeRSSArticlesDataSource = NativeRSSArticlesDataSource(),
        snapshotStore: DragonSnapshotStore = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.native = native
        self.snapshotStore = snapshotStore
        self.nowProvider = nowProvider
    }

    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult? {
        guard let cachedResult = await snapshotStore.load(
            DragonCachedArticlesEnvelope.self,
            for: .nativeArticlesFeed
        ) else {
            return nil
        }

        let filteredResponse = cachedResult.value.response.filteredToRecentArticles(referenceDate: nowProvider())

        return DragonCachedArticlesResult(
            response: filteredResponse,
            cachedAt: cachedResult.source.cachedMetadata?.cachedAt ?? nowProvider(),
            source: .cachedArticles
        )
    }

    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult {
        let result = try await native.fetchArticles()
        let envelope = DragonCachedArticlesEnvelope(
            response: result.response,
            sourceStatuses: result.sourceStatuses,
            diagnostics: result.diagnostics
        )
        await snapshotStore.save(envelope, for: .nativeArticlesFeed)

        return DragonArticlesRefreshResult(
            response: result.response.filteredToRecentArticles(referenceDate: nowProvider()),
            refreshedAt: Date(),
            source: .nativeRSS,
            warningMessage: nil
        )
    }
}

final class DragonDefaultArticlesDataSource: DragonArticlesDataSource {
    private let cachedDataSource: CachedArticlesDataSource

    init(
        native: NativeRSSArticlesDataSource = NativeRSSArticlesDataSource(),
        snapshotStore: DragonSnapshotStore = .shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.cachedDataSource = CachedArticlesDataSource(
            native: native,
            snapshotStore: snapshotStore,
            nowProvider: nowProvider
        )
    }

    func loadCachedArticles(limit: Int) async -> DragonCachedArticlesResult? {
        await cachedDataSource.loadCachedArticles(limit: limit)
    }

    func refreshArticles(limit: Int) async throws -> DragonArticlesRefreshResult {
        try await cachedDataSource.refreshArticles(limit: limit)
    }
}

private struct DragonCachedArticlesEnvelope: Codable {
    let response: DragonArticlesResponse
    let sourceStatuses: [DragonRSSSourceFetchStatus]
    let diagnostics: DragonNativeArticlesDiagnostics
}
