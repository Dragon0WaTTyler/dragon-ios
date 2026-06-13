import Foundation

final class DragonCachedDataSource: DragonDataSource {
    private let remote: DragonDataSource
    private let snapshotStore: DragonSnapshotStore

    init(remote: DragonDataSource, snapshotStore: DragonSnapshotStore = .shared) {
        self.remote = remote
        self.snapshotStore = snapshotStore
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        try await fetchWithSnapshot(key: .home) {
            try await remote.fetchHome()
        }
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await fetchWithSnapshot(key: .articles(limit: limit)) {
            try await remote.fetchArticles(limit: limit)
        }
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        try await fetchWithSnapshot(key: .books(limit: limit, offset: offset, query: query)) {
            try await remote.fetchBooks(limit: limit, offset: offset, query: query)
        }
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        try await fetchWithSnapshot(key: .movies(limit: limit)) {
            try await remote.fetchMovies(limit: limit)
        }
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        try await fetchWithSnapshot(key: .youTube(source: source, section: section, limit: limit, offset: offset, query: query)) {
            try await remote.fetchYouTubeVideos(source: source, section: section, limit: limit, offset: offset, query: query)
        }
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        try await fetchWithSnapshot(key: .youTubeVideos(section: section, limit: limit, offset: offset)) {
            try await remote.fetchYouTubeVideos(section: section, limit: limit, offset: offset)
        }
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        try await fetchWithSnapshot(key: .youTubeSections) {
            try await remote.fetchYouTubeSections()
        }
    }

    private func fetchWithSnapshot<Response: Codable>(
        key: DragonSnapshotCacheKey,
        remoteFetch: () async throws -> DragonAPIFetchResult<Response>
    ) async throws -> DragonAPIFetchResult<Response> {
        do {
            let result = try await remoteFetch()
            await snapshotStore.save(result.value, for: key)
            return result
        } catch {
            if let cachedResult = await snapshotStore.load(Response.self, for: key) {
                return cachedResult
            }
            throw error
        }
    }
}
