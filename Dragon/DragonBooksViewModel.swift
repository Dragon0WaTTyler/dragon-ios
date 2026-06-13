import Foundation
import Combine

@MainActor
final class DragonBooksViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonBooksResponse?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var refreshErrorText: String?

    private let client: DragonAPIClient
    private let limit: Int

    init(
        client: DragonAPIClient = .shared,
        limit: Int = 20,
        initialState: State = .idle,
        initialResponse: DragonBooksResponse? = nil
    ) {
        self.client = client
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
    }

    var books: [DragonBook] {
        response?.items ?? []
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadBooks() async {
        state = .loading

        do {
            let response = try await client.fetchBooks(limit: limit)
            guard response.ok else {
                handleFailure("Dragon API responded but ok=false")
                return
            }

            self.response = response
            self.lastUpdatedAt = Date()
            self.refreshErrorText = nil
            state = response.items.isEmpty ? .empty : .loaded
        } catch {
            handleFailure("Could not load /api/v1/books: \(error.localizedDescription)")
        }
    }

    private func handleFailure(_ message: String) {
        refreshErrorText = message

        guard let response else {
            state = .failed(message)
            return
        }

        state = response.items.isEmpty ? .empty : .loaded
    }
}

extension DragonBooksResponse {
    static let preview = DragonBooksResponse(
        api_version: "v1",
        ok: true,
        items: [
            DragonBook(
                id: "book-preview-1",
                title: "Clean Native Books Slice",
                author: "Dragon Notes",
                authors: ["Dragon Notes"],
                cover: "",
                year: "2026",
                status: "want to read",
                score: "8.8",
                excerpt: "Compact cards, safe fallback covers, and a detail placeholder make Books feel native without adding a reader yet."
            ),
            DragonBook(
                id: "book-preview-2",
                title: "Practical SwiftUI Preview Data",
                author: "Sample Author",
                authors: ["Sample Author"],
                cover: "https://example.com/cover.jpg",
                year: "",
                status: "reading",
                score: "",
                excerpt: "Preview-backed books keep the tab useful even when the backend is offline."
            )
        ],
        count: 2
    )
}
