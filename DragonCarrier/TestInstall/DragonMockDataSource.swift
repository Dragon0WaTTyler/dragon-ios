import Foundation

final class MockDragonDataSource: DragonDataSource {
    private let resolvedURL = URL(string: "dragon://mock/local")!

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        result(
            DragonHomeResponse(
                app_name: "Dragon",
                api_version: "v1",
                ok: true,
                server_time: "Local mock",
                sections: [
                    DragonSection(api_path: "/api/v1/articles", key: "articles", label: "Articles", status: "available", count: mockArticles.count, href: "/api/v1/articles"),
                    DragonSection(api_path: "/api/v1/books", key: "books", label: "Books", status: "available", count: mockBooks.count, href: "/api/v1/books"),
                    DragonSection(api_path: "/api/v1/youtube/sections", key: "youtube", label: "YouTube", status: "available", count: mockYouTubeSections.count, href: "/api/v1/youtube/sections"),
                    DragonSection(api_path: "/api/v1/movies", key: "movies", label: "Movies", status: "available", count: mockMovies.count, href: "/api/v1/movies")
                ],
                service: "dragon-local"
            )
        )
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        let items = Array(mockArticles.prefix(max(0, limit)))
        return result(DragonArticlesResponse(api_version: "v1", ok: true, items: items, count: items.count))
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        let filtered = filter(mockBooks, query: query) { book in
            [book.title, book.author, book.authors.joined(separator: " "), book.status, book.excerpt]
        }
        let page = page(filtered, limit: limit, offset: offset)
        return result(
            DragonBooksResponse(
                api_version: "v1",
                ok: true,
                items: page.items,
                count: page.items.count,
                total: filtered.count,
                limit: limit,
                offset: offset,
                has_more: page.hasMore,
                next_offset: page.nextOffset
            )
        )
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        let items = Array(mockMovies.prefix(max(0, limit)))
        return result(DragonMoviesResponse(api_version: "v1", ok: true, items: items, count: items.count))
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredBySource = mockYouTubeVideos.filter { video in
            normalizedSource == "all" || video.source.lowercased() == normalizedSource
        }
        let filteredBySection = filteredBySource.filter { video in
            guard let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            return video.section.caseInsensitiveCompare(section) == .orderedSame
        }
        let filtered = filter(filteredBySection, query: query) { video in
            [video.title, video.channel, video.section, video.group, video.playlist]
        }
        return try await makeYouTubeResponse(items: filtered, section: section ?? "all", limit: limit, offset: offset)
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        let filtered = mockYouTubeVideos.filter { video in
            video.section.caseInsensitiveCompare(section) == .orderedSame
        }
        return try await makeYouTubeResponse(items: filtered, section: section, limit: limit, offset: offset)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        result(DragonYouTubeSectionsResponse(api_version: "v1", ok: true, sections: mockYouTubeSections))
    }

    private func makeYouTubeResponse(items: [DragonYouTubeVideo], section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        let page = page(items, limit: limit, offset: offset)
        return result(
            DragonYouTubeVideosResponse(
                api_version: "v1",
                ok: true,
                section: section,
                items: page.items,
                count: page.items.count,
                total: items.count,
                limit: limit,
                offset: offset,
                has_more: page.hasMore,
                next_offset: page.nextOffset
            )
        )
    }

    private func result<Response>(_ value: Response) -> DragonAPIFetchResult<Response> {
        DragonAPIFetchResult(value: value, source: .network, resolvedURL: resolvedURL)
    }

    private func page<Item>(_ items: [Item], limit: Int, offset: Int) -> (items: [Item], hasMore: Bool, nextOffset: Int?) {
        let safeLimit = max(1, limit)
        let safeOffset = min(max(0, offset), items.count)
        let endIndex = min(safeOffset + safeLimit, items.count)
        let pageItems = Array(items[safeOffset..<endIndex])
        let hasMore = endIndex < items.count
        return (pageItems, hasMore, hasMore ? endIndex : nil)
    }

    private func filter<Item>(_ items: [Item], query: String?, fields: (Item) -> [String]) -> [Item] {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty else {
            return items
        }

        return items.filter { item in
            fields(item).contains { field in
                field.lowercased().contains(query)
            }
        }
    }

    private var mockArticles: [DragonArticle] {
        [
            DragonArticle(
                id: "mock-article-1",
                title: "Local Dragon Client Notes",
                source: "Dragon Core",
                url: "dragon://mock/articles/1",
                published_at: "2026-06-13T12:00:00Z",
                saved_at: "",
                excerpt: "A small local data source keeps screens testable without assuming one backend is the master.",
                status: "unread",
                read_state: "unread"
            )
        ]
    }

    private var mockBooks: [DragonBook] {
        [
            DragonBook(
                id: "mock-book-1",
                title: "Native Dragon Data",
                author: "Dragon Core",
                authors: ["Dragon Core"],
                cover: "",
                year: "2026",
                status: "reading",
                score: "",
                excerpt: "Mock data for exercising the native client boundary."
            )
        ]
    }

    private var mockMovies: [DragonMovie] {
        [
            DragonMovie(
                id: "mock-movie-1",
                title: "Local Mode",
                year: "2026",
                poster: "",
                status: "available",
                score: "",
                type: "movie",
                overview: "A placeholder movie from the local data source."
            )
        ]
    }

    private var mockYouTubeSections: [DragonYouTubeSection] {
        [
            DragonYouTubeSection(key: "pockettube", label: "PocketTube", count: mockYouTubeVideos.count)
        ]
    }

    private var mockYouTubeVideos: [DragonYouTubeVideo] {
        [
            DragonYouTubeVideo(
                id: "mock-video-1",
                video_id: "mock-video-1",
                title: "Dragon Local Data Source",
                channel: "Dragon Core",
                thumbnail: "",
                url: "dragon://mock/youtube/1",
                published_at: "2026-06-13T12:00:00Z",
                saved_at: "",
                duration: "",
                section: "pockettube",
                group: "pockettube",
                playlist: "",
                source: "pockettube"
            )
        ]
    }
}
