import Foundation

protocol DragonHomeFetching {
    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse>
}

protocol DragonArticlesFetching {
    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse>
}

protocol DragonBooksFetching {
    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse>
}

protocol DragonMoviesFetching {
    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse>
}

protocol DragonYouTubeFetching {
    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse>
    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse>
    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse>
}

protocol DragonDataSource: DragonHomeFetching, DragonArticlesFetching, DragonBooksFetching, DragonMoviesFetching, DragonYouTubeFetching {}
