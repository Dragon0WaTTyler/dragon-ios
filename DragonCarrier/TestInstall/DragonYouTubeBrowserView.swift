import SwiftUI

struct DragonYouTubeBrowserView: View {
    private static let fallbackPocketTubeFavoritesKey = "favorites"

    private enum Mode: String, CaseIterable, Identifiable {
        case playlist
        case pocketTube

        var id: String { rawValue }
    }

    private struct FilterChip: Identifiable, Equatable {
        let key: String?
        let label: String

        var id: String { key ?? "__all__" }
    }

    @State private var configuration: DragonYouTubePlaylistConfiguration
    @State private var selectedMode: Mode = .playlist
    @State private var selectedPocketTubeSectionKey: String?
    @State private var searchText = ""
    @State private var videos: [DragonYouTubeVideo] = []
    @State private var sections: [DragonYouTubeSection] = []
    @State private var isLoadingVideos = false
    @State private var isLoadingMoreVideos = false
    @State private var isLoadingSections = false
    @State private var videoErrorText: String?
    @State private var sectionErrorText: String?
    @State private var videoStatusText: String?
    @State private var sectionStatusText: String?
    @State private var playlistLastUpdatedAt: Date?
    @State private var pocketTubeLastUpdatedAt: Date?
    @State private var didLoadSections = false
    @State private var hasMoreVideos = false
    @State private var nextVideoOffset: Int?
    @State private var pendingVideoReset = false
    @State private var submittedSearchQuery = ""

    private let dataSource: DragonDataSource
    private let playlistLoader: (any DragonYouTubePlaylistLoading)?
    private let settingsStore = DragonYouTubeSettingsStore()
    private let limit = 50

    init(dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource) {
        self.dataSource = dataSource
        self.playlistLoader = dataSource as? any DragonYouTubePlaylistLoading

        let initialConfiguration = (dataSource as? any DragonYouTubePlaylistLoading)?.currentYouTubeConfiguration()
            ?? ((try? DragonYouTubeSettingsStore().loadConfiguration())
                ?? DragonYouTubePlaylistConfiguration(playlistURL: "", playlistID: "", displayName: "", apiKey: ""))
        _configuration = State(initialValue: initialConfiguration)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        Picker("YouTube Mode", selection: $selectedMode) {
                            Text("Playlist").tag(Mode.playlist)
                            Text("PocketTube").tag(Mode.pocketTube)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedMode) { _, newMode in
                            Task {
                                await handleModeChange(newMode)
                            }
                        }

                        if shouldShowRefreshStatus {
                            DragonRefreshStatusView(
                                lastUpdatedAt: currentLastUpdatedAt,
                                isRefreshing: isRefreshing,
                                errorText: currentErrorText,
                                statusText: currentStatusText
                            )
                        }

                        if selectedMode == .pocketTube {
                            pocketTubeFilterSection
                        }

                        content
                    }
                    .padding(24)
                    .padding(.bottom, 90)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search videos")
        .refreshable {
            await refreshCurrentMode(forceSectionsReload: selectedMode == .pocketTube)
        }
        .onReceive(NotificationCenter.default.publisher(for: dragonYouTubeConfigurationDidChangeNotification)) { _ in
            Task {
                await handleConfigurationChange()
            }
        }
        .task(id: normalizedActiveSearchQuery) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard normalizedActiveSearchQuery != submittedSearchQuery else { return }
            submittedSearchQuery = normalizedActiveSearchQuery
            await loadVideosForCurrentMode(reset: true)
        }
        .task {
            await initialize()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YouTube")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                Text(currentSubtitle)
                    .font(.headline)
                    .foregroundStyle(.gray)
            }

            Spacer()

            Button {
                Task {
                    await refreshCurrentMode(forceSectionsReload: selectedMode == .pocketTube)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(DragonTheme.card)
                    .clipShape(Circle())
            }
            .disabled(selectedMode == .playlist && !playlistCanRefresh && videos.isEmpty)
            .opacity(selectedMode == .playlist && !playlistCanRefresh && videos.isEmpty ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private var pocketTubeFilterSection: some View {
        if isLoadingSections && filterChips.count <= 1 {
            loadingCard(text: "Loading PocketTube filters...")
        } else if !filterChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(filterChips) { chip in
                        Button {
                            guard selectedPocketTubeSectionKey != chip.key else { return }
                            selectedPocketTubeSectionKey = chip.key
                            Task {
                                await loadVideosForCurrentMode(reset: true)
                            }
                        } label: {
                            Text(chip.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(isSelectedChip(chip) ? .white : .gray)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(isSelectedChip(chip) ? DragonTheme.red : DragonTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(
                                            DragonTheme.red.opacity(isSelectedChip(chip) ? 0.0 : 0.35),
                                            lineWidth: 1
                                        )
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if let sectionErrorText, videos.isEmpty {
            stateCard(
                title: "Could not load PocketTube filters",
                message: sectionErrorText,
                buttonTitle: "Try Again"
            ) {
                await loadSectionsIfNeeded(forceReload: true)
                await loadVideosForCurrentMode(reset: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingVideos && videos.isEmpty {
            loadingCard(text: selectedMode == .playlist ? "Loading playlist videos..." : "Loading PocketTube videos...")
        } else if videos.isEmpty {
            if hasActiveSearch {
                NoMatchesView()
            } else {
                switch selectedMode {
                case .playlist:
                    playlistEmptyState
                case .pocketTube:
                    stateCard(
                        title: pocketTubeEmptyStateTitle,
                        message: pocketTubeEmptyStateMessage,
                        buttonTitle: "Reload"
                    ) {
                        await refreshCurrentMode(forceSectionsReload: true)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(videos) { video in
                    NavigationLink {
                        YouTubeWatchView(video: video, videos: videos)
                    } label: {
                        YouTubeVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoadingMoreVideos || (!isLoadingVideos && hasMoreVideos) {
                DragonLoadMoreCard(
                    title: "Load More Videos",
                    isLoading: isLoadingMoreVideos
                ) {
                    await loadMoreVideosForCurrentMode()
                }
            }
        }
    }

    @ViewBuilder
    private var playlistEmptyState: some View {
        if !configuration.hasPlaylist {
            messageCard(
                title: "YouTube playlist is not configured.",
                message: "Add a playlist link in Settings -> YouTube."
            )
        } else if let videoErrorText {
            stateCard(
                title: "Could not load playlist",
                message: videoErrorText,
                buttonTitle: playlistCanRefresh ? "Reload" : "Open Settings"
            ) {
                await refreshCurrentMode(forceSectionsReload: false)
            }
        } else if !configuration.hasAPIKey {
            messageCard(
                title: "YouTube API key is not configured.",
                message: "Add a YouTube Data API key in Settings -> YouTube to refresh this playlist natively."
            )
        } else {
            messageCard(
                title: "This playlist is empty.",
                message: "Add videos to the configured playlist, then refresh to cache them on-device."
            )
        }
    }

    private var filterChips: [FilterChip] {
        let pocketTubeSections = sections
            .filter { section in
                let normalizedKey = normalizedSectionKey(section.key)
                let normalizedLabel = normalizedSectionKey(section.label)
                return normalizedKey != "watchlater"
                    && normalizedKey != "last"
                    && normalizedLabel != "watch later"
                    && normalizedLabel != "last"
                    && !sectionRepresentsFavorites(section)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        let favoritesChip = FilterChip(
            key: preferredPocketTubeFavoritesSectionKey(),
            label: favoritePocketTubeSectionLabel
        )

        return [FilterChip(key: nil, label: "All"), favoritesChip] + pocketTubeSections.map {
            FilterChip(key: $0.key, label: $0.label.isEmpty ? "Untitled" : $0.label)
        }
    }

    private func isSelectedChip(_ chip: FilterChip) -> Bool {
        chip.key == selectedPocketTubeSectionKey
    }

    private var favoritePocketTubeSection: DragonYouTubeSection? {
        sections.first(where: sectionRepresentsFavorites)
    }

    private var favoritePocketTubeSectionLabel: String {
        let label = favoritePocketTubeSection?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "Favorites" : label
    }

    private var isFavoritesSelected: Bool {
        guard let selectedPocketTubeSectionKey else {
            return false
        }

        return favoriteSectionKeyAliases.contains(normalizedSectionKey(selectedPocketTubeSectionKey))
    }

    private var currentSubtitle: String {
        switch selectedMode {
        case .playlist:
            return configuration.hasPlaylist ? configuration.resolvedDisplayName : "Playlist not configured"
        case .pocketTube:
            return "PocketTube"
        }
    }

    private var shouldShowRefreshStatus: Bool {
        currentLastUpdatedAt != nil || isRefreshing || currentErrorText != nil || currentStatusText != nil
    }

    private var currentLastUpdatedAt: Date? {
        switch selectedMode {
        case .playlist:
            return playlistLastUpdatedAt
        case .pocketTube:
            return pocketTubeLastUpdatedAt
        }
    }

    private var currentErrorText: String? {
        guard videos.isEmpty else {
            return nil
        }

        switch selectedMode {
        case .playlist:
            return videoErrorText
        case .pocketTube:
            return videoErrorText ?? sectionErrorText
        }
    }

    private var currentStatusText: String? {
        switch selectedMode {
        case .playlist:
            return videoStatusText
        case .pocketTube:
            return videoStatusText ?? sectionStatusText
        }
    }

    private var isRefreshing: Bool {
        isLoadingVideos || (selectedMode == .pocketTube && isLoadingSections)
    }

    private var pocketTubeEmptyStateTitle: String {
        if isFavoritesSelected {
            return "No favorite videos yet."
        }

        return "No videos in this section."
    }

    private var pocketTubeEmptyStateMessage: String {
        if let currentErrorText {
            return currentErrorText
        }

        if isFavoritesSelected {
            return "Add favorites in PocketTube, then pull to refresh."
        }

        return "Pull to refresh to check again."
    }

    private var playlistCanRefresh: Bool {
        configuration.hasPlaylist && configuration.hasAPIKey
    }

    private var hasActiveSearch: Bool {
        !normalizedActiveSearchQuery.isEmpty
    }

    private var normalizedActiveSearchQuery: String {
        normalizedSearchText(searchText)
    }

    @MainActor
    private func initialize() async {
        reloadConfiguration()
        if selectedMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
        }
        await loadVideosForCurrentMode(reset: true)
    }

    @MainActor
    private func handleConfigurationChange() async {
        reloadConfiguration()

        if selectedMode == .playlist {
            await loadVideosForCurrentMode(reset: true)
        }
    }

    @MainActor
    private func handleModeChange(_ newMode: Mode) async {
        reloadConfiguration()

        if newMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
            if selectedPocketTubeSectionKey == nil {
                selectedPocketTubeSectionKey = preferredPocketTubeFavoritesSectionKey()
            }
        }
        await loadVideosForCurrentMode(reset: true)
    }

    @MainActor
    private func refreshCurrentMode(forceSectionsReload: Bool) async {
        reloadConfiguration()

        if selectedMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: forceSectionsReload)
        }
        await loadVideosForCurrentMode(reset: true)
    }

    @MainActor
    private func loadSectionsIfNeeded(forceReload: Bool) async {
        if isLoadingSections {
            return
        }

        if didLoadSections && !forceReload && !sections.isEmpty {
            return
        }

        isLoadingSections = true
        let hadVisibleSections = !sections.isEmpty

        do {
            let result = try await dataSource.fetchYouTubeSections()
            let response = result.value
            guard response.ok else {
                if hadVisibleSections {
                    sectionErrorText = nil
                } else {
                    sectionErrorText = "Backend returned an error."
                    sectionStatusText = nil
                }
                isLoadingSections = false
                return
            }

            sections = response.sections
            sectionErrorText = nil
            sectionStatusText = result.source.statusMessage
            didLoadSections = true

            let availableSectionKeys = Set(filterChips.compactMap(\.key))
            if let favoritePocketTubeSection,
               let selectedPocketTubeSectionKey,
               favoriteSectionKeyAliases.contains(normalizedSectionKey(selectedPocketTubeSectionKey)) {
                self.selectedPocketTubeSectionKey = favoritePocketTubeSection.key
            } else if let selectedPocketTubeSectionKey,
                      !availableSectionKeys.contains(selectedPocketTubeSectionKey),
                      !favoriteSectionKeyAliases.contains(normalizedSectionKey(selectedPocketTubeSectionKey)) {
                self.selectedPocketTubeSectionKey = nil
            }
        } catch {
            if hadVisibleSections {
                sectionErrorText = nil
            } else {
                sectionErrorText = dragonUserFacingMessage(for: error)
                sectionStatusText = nil
            }
        }

        isLoadingSections = false
    }

    @MainActor
    private func loadVideosForCurrentMode(reset: Bool) async {
        switch selectedMode {
        case .playlist:
            await loadPlaylistVideos(reset: reset)
        case .pocketTube:
            await loadPocketTubeVideos(reset: reset)
        }
    }

    @MainActor
    private func loadPlaylistVideos(reset: Bool) async {
        if isLoadingVideos || isLoadingMoreVideos {
            if reset {
                pendingVideoReset = true
            }
            return
        }

        if reset {
            submittedSearchQuery = normalizedActiveSearchQuery
        }

        guard configuration.hasPlaylist else {
            videos = []
            hasMoreVideos = false
            nextVideoOffset = nil
            videoErrorText = nil
            videoStatusText = nil
            playlistLastUpdatedAt = nil
            return
        }

        if reset {
            await loadCachedPlaylistVideos(offset: 0)
        }

        guard playlistCanRefresh else {
            if !configuration.hasAPIKey && !videos.isEmpty {
                videoStatusText = "Showing cached videos. Add a YouTube API key in Settings to refresh this playlist."
            }
            return
        }

        isLoadingVideos = true
        let activeQuery = normalizedActiveSearchQuery
        let hadVisibleVideos = !videos.isEmpty

        do {
            let offset = reset ? 0 : (nextVideoOffset ?? videos.count)
            let result = try await dataSource.fetchYouTubeVideos(
                source: "playlist",
                section: nil,
                limit: limit,
                offset: offset,
                query: activeQuery
            )
            let response = result.value

            guard response.ok else {
                handlePlaylistFailure("YouTube returned an empty response.", hadVisibleData: hadVisibleVideos)
                isLoadingVideos = false
                return
            }

            if reset {
                videos = response.items
            } else {
                videos = mergeVideos(existing: videos, incoming: response.items)
            }
            hasMoreVideos = response.has_more
            nextVideoOffset = response.next_offset
            videoErrorText = nil
            videoStatusText = result.source.statusMessage
            playlistLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
        } catch {
            handlePlaylistFailure(youTubeUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadPlaylistVideos(reset: true)
        }
    }

    @MainActor
    private func loadCachedPlaylistVideos(offset: Int) async {
        guard let cachedResult = await playlistLoader?.loadCachedYouTubeVideos(
            limit: limit,
            offset: offset,
            query: normalizedActiveSearchQuery
        ) else {
            return
        }

        let response = cachedResult.value
        if offset == 0 {
            videos = response.items
        } else {
            videos = mergeVideos(existing: videos, incoming: response.items)
        }
        hasMoreVideos = response.has_more
        nextVideoOffset = response.next_offset
        videoStatusText = cachedResult.source.statusMessage
        videoErrorText = nil
        playlistLastUpdatedAt = cachedResult.source.cachedMetadata?.cachedAt
    }

    @MainActor
    private func loadPocketTubeVideos(reset: Bool) async {
        if isLoadingVideos || isLoadingMoreVideos {
            if reset {
                pendingVideoReset = true
            }
            return
        }

        isLoadingVideos = true
        let activeQuery = normalizedActiveSearchQuery
        let hadVisibleVideos = !videos.isEmpty
        if reset {
            submittedSearchQuery = activeQuery
        }

        do {
            let offset = reset ? 0 : (nextVideoOffset ?? videos.count)
            let result = try await dataSource.fetchYouTubeVideos(
                source: "pockettube",
                section: selectedPocketTubeSectionKey,
                limit: limit,
                offset: offset,
                query: activeQuery
            )
            let response = result.value

            guard response.ok else {
                handlePocketTubeFailure("Backend returned an error.", hadVisibleData: hadVisibleVideos)
                isLoadingVideos = false
                return
            }

            if reset {
                videos = response.items
            } else {
                videos = mergeVideos(existing: videos, incoming: response.items)
            }
            hasMoreVideos = response.has_more
            nextVideoOffset = response.next_offset
            videoErrorText = nil
            videoStatusText = result.source.statusMessage
            pocketTubeLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
        } catch {
            handlePocketTubeFailure(dragonUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadPocketTubeVideos(reset: true)
        }
    }

    @MainActor
    private func loadMoreVideosForCurrentMode() async {
        switch selectedMode {
        case .playlist:
            await loadMorePlaylistVideos()
        case .pocketTube:
            await loadMorePocketTubeVideos()
        }
    }

    @MainActor
    private func loadMorePlaylistVideos() async {
        guard !isLoadingVideos, !isLoadingMoreVideos, hasMoreVideos else {
            return
        }

        if let cachedResult = await playlistLoader?.loadCachedYouTubeVideos(
            limit: limit,
            offset: nextVideoOffset ?? videos.count,
            query: normalizedActiveSearchQuery
        ) {
            let response = cachedResult.value
            if !response.items.isEmpty {
                videos = mergeVideos(existing: videos, incoming: response.items)
                hasMoreVideos = response.has_more
                nextVideoOffset = response.next_offset
                videoStatusText = cachedResult.source.statusMessage
                videoErrorText = nil
                playlistLastUpdatedAt = cachedResult.source.cachedMetadata?.cachedAt
            }
        }

        guard playlistCanRefresh else {
            return
        }

        isLoadingMoreVideos = true
        let hadVisibleVideos = !videos.isEmpty

        do {
            let result = try await dataSource.fetchYouTubeVideos(
                source: "playlist",
                section: nil,
                limit: limit,
                offset: nextVideoOffset ?? videos.count,
                query: normalizedActiveSearchQuery
            )
            let response = result.value

            guard response.ok else {
                handlePlaylistLoadMoreFailure("YouTube returned an empty response.", hadVisibleData: hadVisibleVideos)
                isLoadingMoreVideos = false
                return
            }

            videos = mergeVideos(existing: videos, incoming: response.items)
            hasMoreVideos = response.has_more
            nextVideoOffset = response.next_offset
            videoErrorText = nil
            videoStatusText = result.source.statusMessage
            playlistLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
        } catch {
            handlePlaylistLoadMoreFailure(youTubeUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingMoreVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadPlaylistVideos(reset: true)
        }
    }

    @MainActor
    private func loadMorePocketTubeVideos() async {
        guard !isLoadingVideos, !isLoadingMoreVideos, hasMoreVideos else {
            return
        }

        isLoadingMoreVideos = true
        let hadVisibleVideos = !videos.isEmpty

        do {
            let result = try await dataSource.fetchYouTubeVideos(
                source: "pockettube",
                section: selectedPocketTubeSectionKey,
                limit: limit,
                offset: nextVideoOffset ?? videos.count,
                query: normalizedActiveSearchQuery
            )
            let response = result.value

            guard response.ok else {
                handlePocketTubeLoadMoreFailure("Backend returned an error.", hadVisibleData: hadVisibleVideos)
                isLoadingMoreVideos = false
                return
            }

            videos = mergeVideos(existing: videos, incoming: response.items)
            hasMoreVideos = response.has_more
            nextVideoOffset = response.next_offset
            videoErrorText = nil
            videoStatusText = result.source.statusMessage
            pocketTubeLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
        } catch {
            handlePocketTubeLoadMoreFailure(dragonUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingMoreVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadPocketTubeVideos(reset: true)
        }
    }

    private func handlePlaylistFailure(_ message: String, hadVisibleData: Bool) {
        if hadVisibleData {
            videoErrorText = nil
            videoStatusText = "Showing cached videos. \(message)"
        } else {
            videoErrorText = message
            videoStatusText = nil
        }
    }

    private func handlePlaylistLoadMoreFailure(_ message: String, hadVisibleData: Bool) {
        if hadVisibleData {
            videoErrorText = nil
            videoStatusText = "Showing cached videos. \(message)"
        } else {
            videoErrorText = message
            videoStatusText = nil
        }
    }

    private func handlePocketTubeFailure(_ message: String, hadVisibleData: Bool) {
        if hadVisibleData {
            videoErrorText = nil
        } else {
            videoErrorText = message
            videoStatusText = nil
        }
    }

    private func handlePocketTubeLoadMoreFailure(_ message: String, hadVisibleData: Bool) {
        if hadVisibleData {
            videoErrorText = nil
        } else {
            videoErrorText = message
            videoStatusText = nil
        }
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
        [video.id, video.video_id, video.url]
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? UUID().uuidString
    }

    private func normalizedSectionKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var favoriteSectionKeyAliases: Set<String> {
        ["favorite", "favorites", "favourite", "favourites"]
    }

    private func sectionRepresentsFavorites(_ section: DragonYouTubeSection) -> Bool {
        favoriteSectionKeyAliases.contains(normalizedSectionKey(section.key))
            || favoriteSectionKeyAliases.contains(normalizedSectionKey(section.label))
    }

    private func preferredPocketTubeFavoritesSectionKey() -> String {
        favoritePocketTubeSection?.key ?? Self.fallbackPocketTubeFavoritesKey
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func reloadConfiguration() {
        configuration = playlistLoader?.currentYouTubeConfiguration()
            ?? ((try? settingsStore.loadConfiguration())
                ?? DragonYouTubePlaylistConfiguration(playlistURL: "", playlistID: "", displayName: "", apiKey: ""))
    }

    private func loadingCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .tint(DragonTheme.red)

            Text(text)
                .foregroundStyle(.gray)
                .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func messageCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func stateCard(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)

            Button {
                Task {
                    await action()
                }
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DragonTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private func youTubeUserFacingMessage(for error: Error) -> String {
    if let youTubeError = error as? DragonYouTubePlaylistDataSourceError {
        return youTubeError.errorDescription ?? "Could not load YouTube videos."
    }

    return dragonUserFacingMessage(for: error)
}
