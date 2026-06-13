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
    @Published private(set) var isLoadingMore = false
    @Published private(set) var searchQuery = ""
    @Published private(set) var statusText: String?

    private let dataSource: DragonDataSource
    private let limit: Int
    private var requestGeneration = 0

    init(
        dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource,
        limit: Int = 50,
        initialState: State = .idle,
        initialResponse: DragonBooksResponse? = nil
    ) {
        self.dataSource = dataSource
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

    var hasMore: Bool {
        response?.has_more ?? false
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    func updateSearchQuery(_ newValue: String) async {
        let normalizedValue = normalizeSearchQuery(newValue)
        guard normalizedValue != searchQuery else {
            return
        }

        searchQuery = normalizedValue
        await loadBooks()
    }

    func loadBooks() async {
        requestGeneration += 1
        let requestID = requestGeneration
        state = .loading

        do {
            let result = try await dataSource.fetchBooks(limit: limit, offset: 0, query: searchQuery)
            guard requestID == requestGeneration else {
                return
            }
            let response = result.value
            guard response.ok else {
                handleFailure("Backend returned an error.")
                return
            }

            self.response = response
            self.lastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            self.refreshErrorText = nil
            self.statusText = result.source.statusMessage
            self.isLoadingMore = false
            state = response.items.isEmpty ? .empty : .loaded
        } catch {
            guard requestID == requestGeneration else {
                return
            }
            handleFailure(dragonUserFacingMessage(for: error))
        }
    }

    func loadMoreBooks() async {
        guard !isLoading, !isLoadingMore, let response, response.has_more else {
            return
        }

        isLoadingMore = true

        do {
            let nextOffset = response.next_offset ?? response.items.count
            let nextPageResult = try await dataSource.fetchBooks(limit: limit, offset: nextOffset, query: searchQuery)
            let nextPage = nextPageResult.value
            guard nextPage.ok else {
                handleLoadMoreFailure("Backend returned an error.")
                return
            }

            let mergedItems = mergeBooks(existing: response.items, incoming: nextPage.items)
            self.response = DragonBooksResponse(
                api_version: nextPage.api_version,
                ok: nextPage.ok,
                items: mergedItems,
                count: mergedItems.count,
                total: nextPage.total,
                limit: nextPage.limit,
                offset: 0,
                has_more: nextPage.has_more,
                next_offset: nextPage.next_offset
            )
            self.lastUpdatedAt = nextPageResult.source.cachedMetadata?.cachedAt ?? Date()
            self.refreshErrorText = nil
            self.statusText = nextPageResult.source.statusMessage
            state = mergedItems.isEmpty ? .empty : .loaded
        } catch {
            handleLoadMoreFailure(dragonUserFacingMessage(for: error))
        }

        isLoadingMore = false
    }

    private func handleFailure(_ message: String) {
        refreshErrorText = message
        isLoadingMore = false
        statusText = nil

        guard let response else {
            state = .failed(message)
            return
        }

        state = response.items.isEmpty ? .empty : .loaded
    }

    private func handleLoadMoreFailure(_ message: String) {
        refreshErrorText = message
        isLoadingMore = false
        statusText = nil
    }

    private func mergeBooks(existing: [DragonBook], incoming: [DragonBook]) -> [DragonBook] {
        var merged = existing
        var seenIDs = Set(existing.map(\.id))

        for book in incoming {
            if seenIDs.contains(book.id) {
                continue
            }
            seenIDs.insert(book.id)
            merged.append(book)
        }

        return merged
    }

    private func normalizeSearchQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        count: 2,
        total: 2,
        limit: 50,
        offset: 0,
        has_more: false,
        next_offset: nil
    )
}
