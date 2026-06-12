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

    private let client: DragonAPIClient
    private let sectionKey: String
    private let limit: Int

    init(
        sectionKey: String,
        limit: Int = 50,
        client: DragonAPIClient = .shared,
        initialState: State = .idle,
        initialResponse: DragonYouTubeVideosResponse? = nil
    ) {
        self.client = client
        self.sectionKey = sectionKey
        self.limit = limit
        self.state = initialState
        self.response = initialResponse
    }

    var videos: [DragonYouTubeVideo] {
        response?.items ?? []
    }

    func loadVideos() async {
        state = .loading

        do {
            let response = try await client.fetchYouTubeVideos(section: sectionKey, limit: limit)
            guard response.ok else {
                self.response = nil
                state = .failed("Dragon API responded but ok=false")
                return
            }

            self.response = response
            state = response.items.isEmpty ? .empty : .loaded
        } catch {
            self.response = nil
            state = .failed("Could not load /api/v1/youtube/videos: \(error.localizedDescription)")
        }
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
        count: 2
    )
}
