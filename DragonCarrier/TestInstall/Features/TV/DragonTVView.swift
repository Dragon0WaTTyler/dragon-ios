import AVKit
import SwiftUI

struct DragonTVView: View {
    @StateObject private var viewModel: DragonTVViewModel
    @State private var selectedChannel: IPTVChannel?

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: DragonTVViewModel())
    }

    init(viewModel: DragonTVViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        DragonTVHeader(
                            countLabel: viewModel.channelCountLabel,
                            isRefreshing: viewModel.isLoading,
                            onRefresh: refreshChannels
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        DragonTVStatusCard(viewModel: viewModel)
                            .padding(.horizontal, 20)

                        DragonTVStatsGrid(viewModel: viewModel)
                            .padding(.horizontal, 20)

                        DragonTVSearchField(searchText: $viewModel.searchText)
                            .padding(.horizontal, 20)

                        DragonTVFilterStrip(selectedFilter: $viewModel.selectedFilter)

                        content
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 96)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadCachedThenRefreshIfNeeded()
        }
        .background(
            DragonTVFullscreenPlayerPresenter(selectedChannel: $selectedChannel)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var content: some View {
        let visibleChannels = viewModel.visibleChannels
        let supplementalChannels = viewModel.visibleSupplementalChannels
        let hasVisibleContent = !visibleChannels.isEmpty || !supplementalChannels.isEmpty
        let hasAnyContent = !viewModel.channels.isEmpty || !supplementalChannels.isEmpty

        if viewModel.isLoading && !hasAnyContent {
            DragonTVStateCard(
                title: "Loading TV",
                message: "Fetching playlists, removing duplicates, and testing reachable streams."
            ) {
                ProgressView()
                    .tint(.white)
            }
        } else if !hasAnyContent {
            DragonTVStateCard(
                title: "No Channels Yet",
                message: "No reachable channels are cached right now. Refresh to run a new scan."
            ) {
                Button("Refresh") {
                    refreshChannels()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DragonTheme.red)
                .clipShape(Capsule())
            }
        } else if !hasVisibleContent {
            DragonTVStateCard(
                title: "No Matches",
                message: "Try a different search or switch to another TV filter."
            ) {
                Button("Clear Search") {
                    viewModel.searchText = ""
                    viewModel.selectedFilter = .all
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    Capsule()
                        .stroke(DragonTheme.red.opacity(0.45), lineWidth: 1)
                )
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleChannels) { channel in
                    DragonTVChannelRow(
                        channel: channel,
                        onSelect: {
                            selectedChannel = channel
                        },
                        onToggleFavorite: {
                            viewModel.toggleFavorite(channel)
                        }
                    )
                }

                if !supplementalChannels.isEmpty {
                    DragonTVStateCard(
                        title: "Sports Discovery",
                        message: "These sports and beIN-related matches were parsed from playlists but skipped by preflight validation. You can still try opening them in the native fullscreen player."
                    ) {
                        EmptyView()
                    }

                    ForEach(supplementalChannels) { channel in
                        DragonTVChannelRow(
                            channel: channel,
                            onSelect: {
                                selectedChannel = channel
                            },
                            onToggleFavorite: {
                                viewModel.toggleFavorite(channel)
                            }
                        )
                    }
                }
            }
        }
    }

    private func refreshChannels() {
        Task {
            await viewModel.refresh()
        }
    }
}

private struct DragonTVHeader: View {
    let countLabel: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("DRAGON")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(DragonTheme.red)
                    .tracking(1.4)

                Spacer()

                Text(countLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DragonTheme.card)
                    .clipShape(Capsule())

                Button(action: onRefresh) {
                    ZStack {
                        Circle()
                            .fill(DragonTheme.card)
                            .frame(width: 42, height: 42)

                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("TV")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("A native IPTV browser with cache-first channel loading.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 18) {
                DragonTVHeaderNavLabel(title: "Live", isSelected: true)
                DragonTVHeaderNavLabel(title: "Channels", isSelected: true)
                DragonTVHeaderNavLabel(title: "Favorites", isSelected: false)
            }
        }
    }
}

private struct DragonTVHeaderNavLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.52))

            Capsule()
                .fill(isSelected ? Color.white : Color.clear)
                .frame(width: isSelected ? 28 : 0, height: 2)
        }
    }
}

private struct DragonTVStatusCard: View {
    @ObservedObject var viewModel: DragonTVViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DragonRefreshStatusView(
                lastUpdatedAt: viewModel.lastUpdatedAt,
                isRefreshing: viewModel.isLoading,
                errorText: viewModel.errorMessage,
                statusText: viewModel.statusText
            )

            if !viewModel.sourceFailures.isEmpty {
                Text(viewModel.sourceFailures.prefix(3).map(\.label).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DragonTVStatsGrid: View {
    @ObservedObject var viewModel: DragonTVViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DragonTVStatCard(title: "Raw", value: "\(viewModel.rawChannelCount)")
            DragonTVStatCard(title: "Deduped", value: "\(viewModel.dedupedChannelCount)")
            DragonTVStatCard(title: "Working", value: "\(viewModel.validChannelCount)")
            DragonTVStatCard(title: "Failed Sources", value: "\(viewModel.failedSourceCount)")
        }
    }
}

private struct DragonTVStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DragonTVSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)

            TextField("Search channels", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DragonTheme.red.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DragonTVFilterStrip: View {
    @Binding var selectedFilter: DragonTVFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DragonTVFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selectedFilter == filter ? .white : .gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selectedFilter == filter ? DragonTheme.red.opacity(0.9) : DragonTheme.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct DragonTVChannelRow: View {
    let channel: IPTVChannel
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            DragonTVChannelLogo(logoURL: channel.logo)

            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let group = channel.group, !group.isEmpty {
                    Text(group)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                Text("\(channel.sourceSummary) • \(channel.hostLabel)")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: channel.isFavorite ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundStyle(channel.isFavorite ? DragonTheme.red : .gray)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.02))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(14)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onSelect)
    }
}

private struct DragonTVChannelLogo: View {
    let logoURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))

            if let logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
            } else {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 60, height: 60)
    }
}

private struct DragonTVStateCard<Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)

            accessory()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
