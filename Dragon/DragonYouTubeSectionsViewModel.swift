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
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var refreshErrorText: String?

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

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadSections() async {
        state = .loading

        do {
            let response = try await client.fetchYouTubeSections()
            guard response.ok else {
                handleFailure("Dragon API responded but ok=false")
                return
            }

            self.response = response
            self.lastUpdatedAt = Date()
            self.refreshErrorText = nil
            state = response.sections.isEmpty ? .empty : .loaded
        } catch {
            handleFailure("Could not load /api/v1/youtube/sections: \(error.localizedDescription)")
        }
    }

    private func handleFailure(_ message: String) {
        refreshErrorText = message

        guard let response else {
            state = .failed(message)
            return
        }

        state = response.sections.isEmpty ? .empty : .loaded
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
