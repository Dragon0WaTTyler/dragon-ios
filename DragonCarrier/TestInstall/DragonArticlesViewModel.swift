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
        limit: Int = dragonArticlesRequestLimit,
        initialState: State = .idle,
        initialResponse: DragonArticlesResponse? = nil
    ) {
        self.dataSource = dataSource
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
        self.refreshPhase = initialResponse?.items.isEmpty == false ? .refreshed : .idle
        self.sourceLabel = initialResponse?.items.isEmpty == false ? "Preview" : "Empty"
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
            sourceLabel = cachedResult.source.displayLabel
            statusText = statusLine(sourceLabel: sourceLabel, count: cachedResult.response.items.count, detail: "Refreshing")
            refreshPhase = cachedResult.response.items.isEmpty ? .empty : .cached
            state = .loading
        } else {
            sourceLabel = "Empty"
            statusText = statusLine(sourceLabel: sourceLabel, count: 0, detail: "Refreshing")
            refreshPhase = .refreshing
            state = .loading
        }

        do {
            let result = try await dataSource.refreshArticles(limit: limit)
            let response = result.response
            guard response.ok else {
                handleFailure("Article refresh returned an invalid response.")
                return
            }

            self.response = response
            self.lastUpdatedAt = result.refreshedAt
            self.refreshErrorText = result.warningMessage
            self.sourceLabel = result.source.displayLabel
            self.statusText = statusLine(sourceLabel: sourceLabel, count: response.items.count)
            self.refreshPhase = result.warningMessage == nil
                ? (response.items.isEmpty ? .empty : .refreshed)
                : (response.items.isEmpty ? .empty : .failedUsingCache)
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

        if response.items.isEmpty {
            sourceLabel = "Empty"
            statusText = nil
            refreshPhase = .empty
            state = .empty
            return
        }

        if statusText == nil || statusText?.isEmpty == true {
            statusText = statusLine(sourceLabel: sourceLabel, count: response.items.count)
        }
        refreshPhase = .failedUsingCache
        state = .loaded
    }

    func refreshOnForegroundIfNeeded() async {
        guard !isLoading else {
            return
        }

        guard let lastUpdatedAt else {
            await loadArticles()
            return
        }

        if Date().timeIntervalSince(lastUpdatedAt) >= 300 {
            await loadArticles()
        }
    }

    private func statusLine(sourceLabel: String, count: Int, detail: String? = nil) -> String {
        let articleLabel = count == 1 ? "recent article" : "recent articles"
        if let detail, !detail.isEmpty {
            return "Source: \(sourceLabel) • \(count) \(articleLabel) • Last 24h • \(detail)"
        }
        return "Source: \(sourceLabel) • \(count) \(articleLabel) • Last 24h"
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
                published_at: "2026-06-21T10:45:00Z",
                saved_at: "2026-06-21T11:00:00Z",
                excerpt: "A lightweight native slice that shows title, source, date, and excerpt while leaving room for a fuller reader later.",
                status: "unread",
                read_state: "unread"
            ),
            DragonArticle(
                id: "reading-preview-2",
                title: "Preview Data Keeps SwiftUI Fast and Reliable",
                source: "Local Mock Feed",
                url: "https://example.com/articles/previews",
                published_at: "2026-06-21T03:20:00Z",
                saved_at: "",
                excerpt: "Mock data lets the list and placeholder detail render in previews even when the backend is offline.",
                status: "reading",
                read_state: "reading"
            )
        ],
        count: 2
    )
}
