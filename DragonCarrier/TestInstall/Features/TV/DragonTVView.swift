import AVKit
import SwiftUI

private enum DragonTVPrimarySection: Equatable {
    case live
    case channels
}

struct DragonTVView: View {
    @StateObject private var viewModel: DragonTVViewModel
    @State private var selectedChannel: IPTVChannel?
    @State private var currentChannel: IPTVChannel?
    @State private var selectedSection: DragonTVPrimarySection = .channels

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

                VStack(alignment: .leading, spacing: 18) {
                    DragonTVHeader(
                        countLabel: viewModel.channelCountLabel,
                        isRefreshing: viewModel.isLoading,
                        selectedSection: selectedSection,
                        currentChannelName: currentChannel?.name,
                        onSelectSection: { selectedSection = $0 },
                        onRefresh: refreshChannels
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    DragonTVSearchField(searchText: $viewModel.searchText)
                        .padding(.horizontal, 20)

                    DragonTVFilterStrip(selectedFilters: $viewModel.selectedFilters)

                    ScrollView(showsIndicators: false) {
                        content
                            .padding(.horizontal, 20)
                            .padding(.bottom, 96)
                            .padding(.top, 2)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

        if selectedSection == .live {
            DragonTVLiveCard(
                currentChannel: currentChannel,
                onResume: {
                    guard let currentChannel else {
                        return
                    }

                    selectedChannel = currentChannel
                },
                onShowChannels: {
                    selectedSection = .channels
                }
            )
        } else if viewModel.isLoading && !hasAnyContent {
            DragonTVStateCard(
                title: "Loading TV",
                message: "Fetching playlists and rebuilding the cached channel catalog."
            ) {
                ProgressView()
                    .tint(.white)
            }
        } else if !hasAnyContent {
            DragonTVStateCard(
                title: "No Channels Yet",
                message: "No cached channel catalog is available right now. Refresh to rebuild it."
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
                title: noMatchesTitle,
                message: noMatchesMessage
            ) {
                Button(clearFiltersButtonTitle) {
                    viewModel.searchText = ""
                    viewModel.selectedFilters = []
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
                            currentChannel = channel
                            selectedChannel = channel
                            selectedSection = .live
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

    private var noMatchesTitle: String {
        if viewModel.hasActiveFilters && viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No channels match these filters."
        }

        return "No Matches"
    }

    private var noMatchesMessage: String {
        if viewModel.hasActiveFilters && viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try removing one or more filters or switch to another TV section."
        }

        return "Try a different search or switch to another TV filter."
    }

    private var clearFiltersButtonTitle: String {
        let hasSearch = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSearch && viewModel.hasActiveFilters {
            return "Clear Search & Filters"
        }
        if viewModel.hasActiveFilters {
            return "Clear Filters"
        }

        return "Clear Search"
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
    let selectedSection: DragonTVPrimarySection
    let currentChannelName: String?
    let onSelectSection: (DragonTVPrimarySection) -> Void
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
                Button {
                    onSelectSection(.live)
                } label: {
                    DragonTVHeaderNavLabel(
                        title: "Live",
                        subtitle: currentChannelName,
                        isSelected: selectedSection == .live
                    )
                }
                .buttonStyle(.plain)

                Button {
                    onSelectSection(.channels)
                } label: {
                    DragonTVHeaderNavLabel(
                        title: "Channels",
                        subtitle: nil,
                        isSelected: selectedSection == .channels
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DragonTVHeaderNavLabel: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.52))

            if let subtitle, !subtitle.isEmpty, isSelected {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Capsule()
                .fill(isSelected ? Color.white : Color.clear)
                .frame(width: isSelected ? 28 : 0, height: 2)
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

private struct DragonTVLiveCard: View {
    let currentChannel: IPTVChannel?
    let onResume: () -> Void
    let onShowChannels: () -> Void

    var body: some View {
        DragonTVStateCard(
            title: currentChannel == nil ? "Live" : "Now Playing",
            message: currentChannelMessage
        ) {
            if let currentChannel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        DragonTVChannelLogo(logoURL: currentChannel.logo)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentChannel.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            if let group = currentChannel.displayGroupLabel, !group.isEmpty {
                                Text(group)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }

                            Text(currentChannel.sourceSummary)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Play Current Stream", action: onResume)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DragonTheme.red)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Button("Browse Channels", action: onShowChannels)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(DragonTheme.red.opacity(0.45), lineWidth: 1)
                            )
                    }
                }
            } else {
                Button("Open Channel List", action: onShowChannels)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DragonTheme.red)
                    .clipShape(Capsule())
            }
        }
    }

    private var currentChannelMessage: String {
        if currentChannel != nil {
            return "Resume the latest stream you opened, or jump back to the channel list."
        }

        return "Choose a channel first, then Live will keep the current stream area handy."
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
    @Binding var selectedFilters: Set<DragonTVFilter>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DragonTVFilter.allCases) { filter in
                    Button {
                        toggle(filter)
                    } label: {
                        Text(filter.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected(filter) ? .white : .gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isSelected(filter) ? DragonTheme.red.opacity(0.9) : DragonTheme.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func isSelected(_ filter: DragonTVFilter) -> Bool {
        if filter == .all {
            return selectedFilters.normalizedTVFilters.isEmpty
        }

        return selectedFilters.contains(filter)
    }

    private func toggle(_ filter: DragonTVFilter) {
        if filter == .all {
            selectedFilters.removeAll()
            return
        }

        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
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

                if let group = channel.displayGroupLabel, !group.isEmpty {
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
