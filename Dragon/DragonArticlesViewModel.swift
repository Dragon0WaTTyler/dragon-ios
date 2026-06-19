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
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var refreshErrorText: String?
    @Published private(set) var statusText: String?
    @Published private(set) var refreshPhase: DragonArticlesRefreshPhase
    @Published private(set) var sourceLabel: String

    private let dataSource: DragonArticlesDataSource
    private let limit: Int

    init(
        dataSource: DragonArticlesDataSource = DragonDefaultArticlesDataSource(),
        limit: Int = 20,
        initialState: State = .idle,
        initialResponse: DragonArticlesResponse? = nil
    ) {
        self.dataSource = dataSource
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
        self.refreshPhase = initialResponse?.items.isEmpty == false ? .refreshed : .idle
        self.sourceLabel = initialResponse?.items.isEmpty == false ? "Direct RSS" : "Empty"
    }

    var articles: [DragonArticle] {
        response?.items ?? []
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadArticles() async {
        refreshErrorText = nil

        if let cachedResult = await dataSource.loadCachedArticles(limit: limit) {
            response = cachedResult.response
            lastUpdatedAt = cachedResult.cachedAt
            sourceLabel = "Cache"
            statusText = statusLine(
                sourceLabel: "Cache",
                count: cachedResult.response.items.count,
                detail: cachedResult.source == .directRSS ? "Direct RSS cache" : "API fallback cache"
            )
            refreshPhase = cachedResult.response.items.isEmpty ? .empty : .cached
            state = .loading
        } else {
            sourceLabel = "Empty"
            statusText = statusLine(sourceLabel: "Refreshing", count: 0)
            refreshPhase = .refreshing
            state = .loading
        }

        do {
            let result = try await dataSource.refreshArticles(limit: limit)
            let response = result.response
            guard response.ok else {
                handleFailure("Dragon API responded but ok=false")
                return
            }

            self.response = response
            self.lastUpdatedAt = result.refreshedAt
            self.refreshErrorText = nil
            self.sourceLabel = result.source == .directRSS ? "Direct RSS" : "API fallback"
            self.statusText = statusLine(
                sourceLabel: sourceLabel,
                count: response.items.count
            )
            self.refreshPhase = response.items.isEmpty ? .empty : .refreshed
            state = response.items.isEmpty ? .empty : .loaded
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func handleFailure(_ message: String) {
        refreshErrorText = message

        guard let response else {
            statusText = nil
            sourceLabel = "Empty"
            refreshPhase = .idle
            state = .failed(message)
            return
        }

        sourceLabel = response.items.isEmpty ? "Empty" : "Cache"
        statusText = response.items.isEmpty ? nil : statusLine(
            sourceLabel: "Cache",
            count: response.items.count
        )
        refreshPhase = response.items.isEmpty ? .empty : .failedUsingCache
        state = response.items.isEmpty ? .empty : .loaded
    }

    private func statusLine(sourceLabel: String, count: Int, detail: String? = nil) -> String {
        let articleLabel = count == 1 ? "article" : "articles"
        if let detail, !detail.isEmpty {
            return "Source: \(sourceLabel) • \(count) \(articleLabel) • \(detail)"
        }
        return "Source: \(sourceLabel) • \(count) \(articleLabel)"
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
