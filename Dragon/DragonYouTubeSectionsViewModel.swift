import Foundation
import Combine

@MainActor
final class DragonYouTubeSectionsViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonYouTubeSectionsResponse?

    private let client: DragonAPIClient

    init(
        client: DragonAPIClient = .shared,
        initialState: State = .idle,
        initialResponse: DragonYouTubeSectionsResponse? = nil
    ) {
        self.client = client
        self.state = initialState
        self.response = initialResponse
    }

    var sections: [DragonYouTubeSection] {
        response?.sections ?? []
    }

    func loadSections() async {
        state = .loading

        do {
            let response = try await client.fetchYouTubeSections()
            guard response.ok else {
                self.response = nil
                state = .failed("Dragon API responded but ok=false")
                return
            }

            self.response = response
            state = response.sections.isEmpty ? .empty : .loaded
        } catch {
            self.response = nil
            state = .failed("Could not load /api/v1/youtube/sections: \(error.localizedDescription)")
        }
    }
}

extension DragonYouTubeSectionsResponse {
    static let preview = DragonYouTubeSectionsResponse(
        api_version: "v1",
        ok: true,
        sections: [
            DragonYouTubeSection(key: "archive", label: "archive", count: 200),
            DragonYouTubeSection(key: "islamic knowledge", label: "islamic knowledge", count: 200),
            DragonYouTubeSection(key: "My Favorite", label: "My Favorite", count: 200)
        ]
    )
}

#if DEBUG
extension DragonYouTubeSectionsViewModel {
    convenience init(preview response: DragonYouTubeSectionsResponse) {
        self.init(initialState: .loaded, initialResponse: response)
    }
}
#endif
