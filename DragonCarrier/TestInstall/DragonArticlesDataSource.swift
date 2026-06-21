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
    case legacyRemote

    var displayLabel: String {
        switch self {
        case .nativeRSS:
            return "Native RSS"
        case .cachedArticles:
            return "Articles cache"
        case .legacyRemote:
            return "Legacy remote"
        }
    }

    var refreshWarning: String? {
        switch self {
        case .nativeRSS:
            return nil
        case .cachedArticles:
            return "Failed to refresh RSS. Showing saved articles."
        case .legacyRemote:
            return "Native RSS refresh failed. Showing legacy remote articles."
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

final class LegacyArticlesRemoteDataSource: DragonArticlesFetching {
    private let remote: DragonArticlesFetching

    init(remote: DragonArticlesFetching = DragonRemoteDataSource.shared) {
        self.remote = remote
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await remote.fetchArticles(limit: limit)
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        try await remote.fetchArticleDetail(id: id)
    }
}

final class NativeRSSArticlesDataSource {
    private let rssSource: DragonRSSArticleSource

    init(rssSource: DragonRSSArticleSource = DragonRSSArticleSource()) {
        self.rssSource = rssSource
    }

    func fetchArticles() async throws -> DragonNativeArticlesFetchResult {
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
    private let legacyFallback: DragonArticlesFetching?
    private let nowProvider: () -> Date

    init(
        native: NativeRSSArticlesDataSource = NativeRSSArticlesDataSource(),
        snapshotStore: DragonSnapshotStore = .shared,
        legacyFallback: DragonArticlesFetching? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.native = native
        self.snapshotStore = snapshotStore
        self.legacyFallback = legacyFallback
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
        do {
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
        } catch {
            guard let legacyFallback else {
                throw error
            }

            let fallbackResult = try await legacyFallback.fetchArticles(limit: limit)
            let filteredResponse = fallbackResult.value.filteredToRecentArticles(referenceDate: nowProvider())
            let diagnostics = DragonNativeArticlesDiagnostics(
                totalFeedsFetched: 0,
                totalItemsParsed: fallbackResult.value.items.count,
                totalValidDatedItems: fallbackResult.value.items.filter { $0.publishedDate != nil }.count,
                totalItemsInside24Hours: filteredResponse.items.count,
                oldestDisplayedArticleAgeHours: filteredResponse.items.last?.publishedDate.map {
                    nowProvider().timeIntervalSince($0) / 3_600
                }
            )
            let envelope = DragonCachedArticlesEnvelope(
                response: fallbackResult.value,
                sourceStatuses: [],
                diagnostics: diagnostics
            )
            await snapshotStore.save(envelope, for: .nativeArticlesFeed)

            return DragonArticlesRefreshResult(
                response: filteredResponse,
                refreshedAt: Date(),
                source: .legacyRemote,
                warningMessage: DragonArticlesRefreshSource.legacyRemote.refreshWarning
            )
        }
    }
}

final class DragonDefaultArticlesDataSource: DragonArticlesDataSource {
    private let cachedDataSource: CachedArticlesDataSource

    init(
        native: NativeRSSArticlesDataSource = NativeRSSArticlesDataSource(),
        snapshotStore: DragonSnapshotStore = .shared,
        legacyFallback: DragonArticlesFetching? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.cachedDataSource = CachedArticlesDataSource(
            native: native,
            snapshotStore: snapshotStore,
            legacyFallback: legacyFallback,
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
