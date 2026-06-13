import Foundation
import Combine

@MainActor
final class DragonYouTubeVideosViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonYouTubeVideosResponse?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var refreshErrorText: String?
    @Published private(set) var isLoadingMore = false
    @Published private(set) var statusText: String?

    private let dataSource: DragonDataSource
    private let sectionKey: String
    private let limit: Int

    init(
        sectionKey: String,
        limit: Int = 50,
        dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource,
        initialState: State = .idle,
        initialResponse: DragonYouTubeVideosResponse? = nil
    ) {
        self.dataSource = dataSource
        self.sectionKey = sectionKey
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
    }

    var videos: [DragonYouTubeVideo] {
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

    func loadVideos() async {
        state = .loading

        do {
            let result = try await dataSource.fetchYouTubeVideos(section: sectionKey, limit: limit, offset: 0)
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
            handleFailure(dragonUserFacingMessage(for: error))
        }
    }

    func loadMoreVideos() async {
        guard !isLoading, !isLoadingMore, let response, response.has_more else {
            return
        }

        isLoadingMore = true

        do {
            let nextOffset = response.next_offset ?? response.items.count
            let nextPageResult = try await dataSource.fetchYouTubeVideos(section: sectionKey, limit: limit, offset: nextOffset)
            let nextPage = nextPageResult.value
            guard nextPage.ok else {
                handleLoadMoreFailure("Backend returned an error.")
                return
            }

            let mergedItems = mergeVideos(existing: response.items, incoming: nextPage.items)
            self.response = DragonYouTubeVideosResponse(
                api_version: nextPage.api_version,
                ok: nextPage.ok,
                section: nextPage.section,
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
        let hasVisibleVideos = !(response?.items.isEmpty ?? true)
        if hasVisibleVideos {
            refreshErrorText = nil
        } else {
            refreshErrorText = message
            statusText = nil
        }
        isLoadingMore = false

        guard let response else {
            state = .failed(message)
            return
        }

        state = response.items.isEmpty ? .empty : .loaded
    }

    private func handleLoadMoreFailure(_ message: String) {
        let hasVisibleVideos = !(response?.items.isEmpty ?? true)
        if hasVisibleVideos {
            refreshErrorText = nil
        } else {
            refreshErrorText = message
            statusText = nil
        }
        isLoadingMore = false
    }

    private func mergeVideos(existing: [DragonYouTubeVideo], incoming: [DragonYouTubeVideo]) -> [DragonYouTubeVideo] {
        var merged = existing
        var seenIDs = Set(existing.map { videoKey($0) })

        for video in incoming {
            let key = videoKey(video)
            if seenIDs.contains(key) {
                continue
            }
            seenIDs.insert(key)
            merged.append(video)
        }

        return merged
    }

    private func videoKey(_ video: DragonYouTubeVideo) -> String {
        let candidates = [video.id, video.video_id, video.url]
        return candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? UUID().uuidString
    }
}

extension DragonYouTubeVideosResponse {
    static let preview = DragonYouTubeVideosResponse(
        api_version: "v1",
        ok: true,
        section: "tech",
        items: [
            DragonYouTubeVideo(
                id: "mn9JF3lz6Bk",
                video_id: "mn9JF3lz6Bk",
                title: "Claude + Hermes Agent = Superpowers!",
                channel: "Julian Goldie SEO",
                thumbnail: "https://i.ytimg.com/vi/mn9JF3lz6Bk/maxresdefault.jpg",
                url: "https://www.youtube.com/watch?v=mn9JF3lz6Bk",
                published_at: "2026-06-12T15:00:28Z",
                saved_at: "",
                duration: "",
                section: "tech",
                group: "",
                playlist: "",
                source: "pockettube"
            ),
            DragonYouTubeVideo(
                id: "sample-2",
                video_id: "sample-2",
                title: "Preview Video",
                channel: "Dragon Notes",
                thumbnail: "",
                url: "https://www.youtube.com/watch?v=sample-2",
                published_at: "2026-06-11T10:00:00Z",
                saved_at: "",
                duration: "12:34",
                section: "tech",
                group: "",
                playlist: "",
                source: "pockettube"
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
