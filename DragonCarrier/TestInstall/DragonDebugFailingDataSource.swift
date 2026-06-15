import Foundation

enum DragonDebugFailureError: LocalizedError {
    case simulatedRemoteFailure

    var errorDescription: String? {
        "Simulated remote failure."
    }
}

#if DEBUG
final class DragonDebugFailingDataSource: DragonDataSource {
    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        throw DragonDebugFailureError.simulatedRemoteFailure
    }
}
#endif
