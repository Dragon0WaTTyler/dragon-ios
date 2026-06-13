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
    @Published private(set) var statusText: String?

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
            let result = try await client.fetchYouTubeSections()
            let response = result.value
            guard response.ok else {
                handleFailure("Backend returned an error.")
                return
            }

            self.response = response
            self.lastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            self.refreshErrorText = nil
            self.statusText = result.source.statusMessage
            state = response.sections.isEmpty ? .empty : .loaded
        } catch {
            handleFailure(dragonUserFacingMessage(for: error))
        }
    }

    private func handleFailure(_ message: String) {
        let hasVisibleSections = !(response?.sections.isEmpty ?? true)
        if hasVisibleSections {
            refreshErrorText = nil
        } else {
            refreshErrorText = message
            statusText = nil
        }

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
