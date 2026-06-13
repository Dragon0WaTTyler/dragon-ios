import Foundation
import Combine
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonHomeResponse?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var refreshErrorText: String?
    @Published private(set) var statusText: String?

    private let client: DragonHomeFetching

    init(
        client: DragonHomeFetching = DragonAPIClient.shared,
        initialState: State = .idle,
        initialResponse: DragonHomeResponse? = nil
    ) {
        self.client = client
        self.state = initialState
        self.response = initialResponse
    }

    var sections: [DragonSection] {
        response?.sections ?? []
    }

    var appName: String {
        response?.app_name ?? "Dragon"
    }

    var serverTimeText: String {
        guard let serverTime = response?.server_time, !serverTime.isEmpty else {
            return "Waiting for backend"
        }

        return "Server time \(serverTime)"
    }

    var errorText: String {
        if let refreshErrorText {
            return refreshErrorText
        }
        if case .failed(let message) = state {
            return message
        }
        return ""
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadHome() async {
        state = .loading

        do {
            let result = try await client.fetchHome()
            let response = result.value
            guard response.ok else {
                refreshErrorText = "Backend returned an error."
                statusText = nil
                state = .failed("Backend returned an error.")
                return
            }

            self.response = response
            self.lastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            self.refreshErrorText = nil
            self.statusText = result.source.statusMessage
            state = .loaded
        } catch {
            refreshErrorText = dragonUserFacingMessage(for: error)
            statusText = nil
            state = .failed(dragonUserFacingMessage(for: error))
        }
    }
}

private extension DragonHomeResponse {
    static let preview = DragonHomeResponse(
        app_name: "Dragon",
        api_version: "v1",
        ok: true,
        server_time: "2026-06-12T12:00:00Z",
        sections: [
            DragonSection(
                api_path: "/api/v1/movies",
                key: "movies",
                label: "Movies",
                status: "available",
                count: 4,
                href: "/api/v1/movies"
            ),
            DragonSection(
                api_path: "/api/v1/youtube/sections",
                key: "youtube",
                label: "YouTube",
                status: "available",
                count: 3,
                href: "/api/v1/youtube/sections"
            ),
            DragonSection(
                api_path: "/api/v1/articles",
                key: "articles",
                label: "Articles",
                status: "available",
                count: 2,
                href: "/api/v1/articles"
            ),
            DragonSection(
                api_path: "/api/v1/books",
                key: "books",
                label: "Books",
                status: "unknown",
                count: nil,
                href: "/api/v1/books"
            ),
            DragonSection(
                api_path: "/api/v1/chess/home",
                key: "chess",
                label: "Chess",
                status: "available",
                count: 1,
                href: "/api/v1/chess/home"
            ),
        ],
        service: "dragon"
    )
}

struct DragonHomeView: View {
    @StateObject private var viewModel: HomeViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: HomeViewModel())
    }

    init(viewModel: HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.appName)
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Native home from /api/v1/home")
                                .font(.headline)
                                .foregroundStyle(.gray)

                            Text(viewModel.serverTimeText)
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Button {
                            Task {
                                await viewModel.loadHome()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(DragonTheme.card)
                                .clipShape(Circle())
                        }
                    }

                    if viewModel.isLoading && viewModel.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading Dragon home...")
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }

                    if viewModel.response != nil || viewModel.isLoading || !viewModel.errorText.isEmpty || viewModel.lastUpdatedAt != nil {
                        DragonRefreshStatusView(
                            lastUpdatedAt: viewModel.lastUpdatedAt,
                            isRefreshing: viewModel.isLoading,
                            errorText: viewModel.response == nil ? viewModel.errorText : viewModel.refreshErrorText,
                            statusText: viewModel.statusText
                        )
                    }

                    VStack(spacing: 12) {
                        if viewModel.sections.isEmpty && !viewModel.isLoading {
                            HomeCard(
                                title: "No data yet",
                                subtitle: "Tap refresh to load Dragon API",
                                value: "—",
                                detail: nil
                            )
                        } else {
                            ForEach(viewModel.sections) { section in
                                HomeCard(
                                    title: section.label,
                                    subtitle: "Status: \(section.statusDisplayText)",
                                    value: section.displayCount,
                                    detail: section.api_path
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadHome()
            }
        }
    }
}

struct HomeCard: View {
    let title: String
    let subtitle: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(DragonTheme.red.opacity(0.9))
                }
            }

            Spacer()

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DragonTheme.red)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    DragonHomeView(
        viewModel: HomeViewModel(
            initialState: .loaded,
            initialResponse: .preview
        )
    )
}
