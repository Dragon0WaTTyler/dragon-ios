import Foundation

enum DragonRemoteSnapshotDataSourceError: LocalizedError {
    case noSnapshotAvailable

    var errorDescription: String? {
        switch self {
        case .noSnapshotAvailable:
            return "No Dragon snapshot is available. Check network access or bundle a local snapshot."
        }
    }
}

final class DragonRemoteSnapshotDataSource: DragonDataSource {
    static let shared = DragonRemoteSnapshotDataSource()

    private struct ResolvedSnapshot {
        let snapshot: DragonCoreSnapshot
        let url: URL
        let source: DragonResponseSource
        let serviceName: String
    }

    private let snapshotStore: DragonCoreSnapshotStore
    private let remoteClient: DragonRemoteSnapshotClient
    private let bundle: Bundle
    private let fileManager: FileManager
    private let snapshotFileName: String
    private let lock = NSLock()

    private var currentSnapshot: ResolvedSnapshot?
    private var refreshTask: Task<Void, Never>?
    private var hasScheduledRefresh = false

    init(
        snapshotStore: DragonCoreSnapshotStore = .shared,
        remoteClient: DragonRemoteSnapshotClient = .init(),
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        snapshotFileName: String = "dragon_core_snapshot.json"
    ) {
        self.snapshotStore = snapshotStore
        self.remoteClient = remoteClient
        self.bundle = bundle
        self.fileManager = fileManager
        self.snapshotFileName = snapshotFileName
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchHome()
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchArticles(limit: limit)
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchArticleDetail(id: id)
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchBooks(limit: limit, offset: offset, query: query)
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchMovies(limit: limit)
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchYouTubeVideos(
            source: source,
            section: section,
            limit: limit,
            offset: offset,
            query: query
        )
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchYouTubeVideos(section: section, limit: limit, offset: offset)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        let dataSource = try await snapshotBackedDataSource()
        return try await dataSource.fetchYouTubeSections()
    }

    private func snapshotBackedDataSource() async throws -> DragonBundledSnapshotDataSource {
        let resolvedSnapshot = try await resolveSnapshot()
        return DragonBundledSnapshotDataSource(
            preloadedSnapshot: resolvedSnapshot.snapshot,
            resolvedURL: resolvedSnapshot.url,
            responseSource: resolvedSnapshot.source,
            serviceName: resolvedSnapshot.serviceName
        )
    }

    private func resolveSnapshot() async throws -> ResolvedSnapshot {
        if let currentSnapshot = lockedCurrentSnapshot() {
            scheduleRefreshIfNeeded()
            return currentSnapshot
        }

        if let cachedSnapshot = snapshotStore.loadSnapshot() {
            let resolved = ResolvedSnapshot(
                snapshot: cachedSnapshot.snapshot,
                url: cachedSnapshot.metadata.fileURL,
                source: .cachedSnapshot(cachedSnapshot.metadata.cachedResponseMetadata),
                serviceName: "dragon-cached-snapshot"
            )
            setCurrentSnapshot(resolved)
            scheduleRefreshIfNeeded()
            return resolved
        }

        if let bundledSnapshot = try? DragonBundledSnapshotDataSource.loadBundledSnapshot(
            bundle: bundle,
            fileManager: fileManager,
            snapshotFileName: snapshotFileName
        ) {
            let resolved = ResolvedSnapshot(
                snapshot: bundledSnapshot.snapshot,
                url: bundledSnapshot.url,
                source: .bundledSnapshot,
                serviceName: "dragon-bundled-snapshot"
            )
            setCurrentSnapshot(resolved)
            scheduleRefreshIfNeeded()
            return resolved
        }

        let remoteSnapshot = try await fetchAndPersistRemoteSnapshot()
        setCurrentSnapshot(remoteSnapshot)
        return remoteSnapshot
    }

    private func scheduleRefreshIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard !hasScheduledRefresh, refreshTask == nil else {
            return
        }

        hasScheduledRefresh = true
        refreshTask = Task {
            await self.refreshFromRemote()
        }
    }

    private func refreshFromRemote() async {
        defer { clearRefreshTask() }

        do {
            let refreshedSnapshot = try await fetchAndPersistRemoteSnapshot()
            setCurrentSnapshot(refreshedSnapshot)
        } catch {
#if DEBUG
            print("Dragon remote snapshot refresh skipped: \(error)")
#endif
        }
    }

    private func fetchAndPersistRemoteSnapshot() async throws -> ResolvedSnapshot {
        let fetchedSnapshot = try await remoteClient.fetchSnapshot()

        do {
            try snapshotStore.saveSnapshotData(fetchedSnapshot.data)
        } catch {
#if DEBUG
            print("Dragon core snapshot store save failed: \(error)")
#endif
        }

        return ResolvedSnapshot(
            snapshot: fetchedSnapshot.snapshot,
            url: fetchedSnapshot.url,
            source: .remoteSnapshot,
            serviceName: "dragon-remote-snapshot"
        )
    }

    private func lockedCurrentSnapshot() -> ResolvedSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshot
    }

    private func setCurrentSnapshot(_ snapshot: ResolvedSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        currentSnapshot = snapshot
    }

    private func clearRefreshTask() {
        lock.lock()
        defer { lock.unlock() }
        refreshTask = nil
    }
}
