import Foundation
import Combine

@MainActor
final class ArticlesViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonArticlesResponse?

    private let client: DragonArticlesFetching
    private let limit: Int

    init(
        client: DragonArticlesFetching = DragonAPIClient.shared,
        limit: Int = 20,
        initialState: State = .idle,
        initialResponse: DragonArticlesResponse? = nil
    ) {
        self.client = client
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
    }

    var articles: [DragonArticle] {
        response?.items ?? []
    }

    func loadArticles() async {
        state = .loading

        do {
            let response = try await client.fetchArticles(limit: limit)
            guard response.ok else {
                self.response = nil
                state = .failed("Dragon API responded but ok=false")
                return
            }

            self.response = response
            state = response.items.isEmpty ? .empty : .loaded
        } catch {
            self.response = nil
            state = .failed("Could not load /api/v1/articles: \(error.localizedDescription)")
        }
    }
}

extension DragonArticlesResponse {
    static let preview = DragonArticlesResponse(
        api_version: "v1",
        ok: true,
        items: [
            DragonArticle(
                id: "reading-preview-1",
                title: "How Dragon’s Articles Tab Behaves as a Native List",
                source: "Dragon Notes",
                url: "https://example.com/articles/native-list",
                published_at: "2026-06-12T10:45:00Z",
                saved_at: "2026-06-12T11:00:00Z",
                excerpt: "A lightweight native slice that shows title, source, date, and excerpt while leaving room for a fuller reader later.",
                status: "unread",
                read_state: "unread"
            ),
            DragonArticle(
                id: "reading-preview-2",
                title: "Preview Data Keeps SwiftUI Fast and Reliable",
                source: "Local Mock Feed",
                url: "https://example.com/articles/previews",
                published_at: "2026-06-11T18:20:00Z",
                saved_at: "",
                excerpt: "Mock data lets the list and placeholder detail render in previews even when the backend is offline.",
                status: "reading",
                read_state: "reading"
            )
        ],
        count: 2
    )
}
