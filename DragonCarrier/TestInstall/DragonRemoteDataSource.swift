import Foundation

final class DragonRemoteDataSource: DragonDataSource {
    static let shared = DragonRemoteDataSource()

    private let apiClient: DragonAPIClient

    init(apiClient: DragonAPIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        try await apiClient.fetchHome()
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await apiClient.fetchArticles(limit: limit)
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        try await apiClient.fetchBooks(limit: limit, offset: offset, query: query)
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        try await apiClient.fetchMovies(limit: limit)
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        try await apiClient.fetchYouTubeVideos(source: source, section: section, limit: limit, offset: offset, query: query)
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        try await apiClient.fetchYouTubeVideos(section: section, limit: limit, offset: offset)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        try await apiClient.fetchYouTubeSections()
    }
}
