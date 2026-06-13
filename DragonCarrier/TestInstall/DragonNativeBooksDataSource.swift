import Foundation

final class DragonNativeBooksDataSource: DragonDataSource {
    private let fallback: DragonDataSource
    private let resolvedURL = URL(string: "dragon://native/books")!
    private let seedBooks: [DragonBook]

    init(fallback: DragonDataSource, seedBooks: [DragonBook] = DragonNativeBooksDataSource.defaultSeedBooks) {
        self.fallback = fallback
        self.seedBooks = seedBooks
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        let filteredBooks = filter(seedBooks, query: query) { book in
            [
                book.id,
                book.title,
                book.author,
                book.authors.joined(separator: " "),
                book.year,
                book.status,
                book.score,
                book.excerpt
            ]
        }

        let page = page(filteredBooks, limit: limit, offset: offset)
        return DragonAPIFetchResult(
            value: DragonBooksResponse(
                api_version: "v1",
                ok: true,
                items: page.items,
                count: page.items.count,
                total: filteredBooks.count,
                limit: max(1, limit),
                offset: max(0, offset),
                has_more: page.hasMore,
                next_offset: page.nextOffset
            ),
            source: .network,
            resolvedURL: resolvedURL
        )
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        try await fallback.fetchHome()
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await fallback.fetchArticles(limit: limit)
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        try await fallback.fetchMovies(limit: limit)
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        try await fallback.fetchYouTubeVideos(source: source, section: section, limit: limit, offset: offset, query: query)
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        try await fallback.fetchYouTubeVideos(section: section, limit: limit, offset: offset)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        try await fallback.fetchYouTubeSections()
    }

    private static var defaultSeedBooks: [DragonBook] {
        [
            DragonBook(
                id: "native-book-1",
                title: "Local First Notes",
                author: "Dragon Core",
                authors: ["Dragon Core"],
                cover: "",
                year: "2026",
                status: "reading",
                score: "8.4",
                excerpt: "A tiny native seed that proves Books can render without waiting on the remote backend."
            ),
            DragonBook(
                id: "native-book-2",
                title: "SwiftUI Under Control",
                author: "Alex Mercer",
                authors: ["Alex Mercer"],
                cover: "",
                year: "2025",
                status: "want to read",
                score: "9.1",
                excerpt: "Paged locally so the Books tab keeps its existing scrolling behavior."
            ),
            DragonBook(
                id: "native-book-3",
                title: "Small Data, Big Signal",
                author: "Priya Shah",
                authors: ["Priya Shah", "Dragon Notes"],
                cover: "",
                year: "2024",
                status: "finished",
                score: "8.9",
                excerpt: "Querying across title, author, status, year, and excerpt still works the same way."
            ),
            DragonBook(
                id: "native-book-4",
                title: "Fallbacks for Humans",
                author: "Mina Lopez",
                authors: ["Mina Lopez"],
                cover: "",
                year: "2023",
                status: "reading",
                score: "8.0",
                excerpt: "Fallback delegation keeps the rest of the app on the cached remote path."
            ),
            DragonBook(
                id: "native-book-5",
                title: "Pocket Guide to Dragon",
                author: "Dragon Team",
                authors: ["Dragon Team"],
                cover: "",
                year: "2026",
                status: "paused",
                score: "7.6",
                excerpt: "A compact local seed list is enough for a first native-only Books slice."
            )
        ]
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
}
