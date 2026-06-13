import SwiftUI

struct DragonYouTubeBrowserView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case watchLater
        case pocketTube

        var id: String { rawValue }
    }

    private struct FilterChip: Identifiable, Equatable {
        let key: String?
        let label: String

        var id: String { key ?? "__all__" }
    }

    @State private var selectedMode: Mode = .watchLater
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
    @State private var watchLaterLastUpdatedAt: Date?
    @State private var pocketTubeLastUpdatedAt: Date?
    @State private var didLoadSections = false
    @State private var hasMoreVideos = false
    @State private var nextVideoOffset: Int?
    @State private var pendingVideoReset = false
    @State private var submittedSearchQuery = ""

    private let limit = 50

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        Picker("YouTube Mode", selection: $selectedMode) {
                            Text("Watch Later").tag(Mode.watchLater)
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

                Text(selectedMode == .watchLater ? "Watch Later" : "PocketTube")
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
            loadingCard(text: "Loading videos...")
        } else if videos.isEmpty {
            if hasActiveSearch {
                NoMatchesView()
            } else {
                stateCard(
                    title: emptyStateTitle,
                    message: emptyStateMessage,
                    buttonTitle: "Reload"
                ) {
                    await refreshCurrentMode(forceSectionsReload: selectedMode == .pocketTube)
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

    private var filterChips: [FilterChip] {
        let pocketTubeSections = sections
            .filter { section in
                let normalizedKey = normalizedSectionKey(section.key)
                let normalizedLabel = normalizedSectionKey(section.label)
                return normalizedKey != "watchlater"
                    && normalizedKey != "last"
                    && normalizedLabel != "watch later"
                    && normalizedLabel != "last"
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        return [FilterChip(key: nil, label: "All")] + pocketTubeSections.map {
            FilterChip(key: $0.key, label: $0.label.isEmpty ? "Untitled" : $0.label)
        }
    }

    private func isSelectedChip(_ chip: FilterChip) -> Bool {
        chip.key == selectedPocketTubeSectionKey
    }

    private var shouldShowRefreshStatus: Bool {
        currentLastUpdatedAt != nil || isRefreshing || currentErrorText != nil
    }

    private var currentLastUpdatedAt: Date? {
        switch selectedMode {
        case .watchLater:
            return watchLaterLastUpdatedAt
        case .pocketTube:
            return pocketTubeLastUpdatedAt
        }
    }

    private var currentErrorText: String? {
        guard videos.isEmpty else {
            return nil
        }

        switch selectedMode {
        case .watchLater:
            return videoErrorText
        case .pocketTube:
            return videoErrorText ?? sectionErrorText
        }
    }

    private var currentStatusText: String? {
        switch selectedMode {
        case .watchLater:
            return videoStatusText
        case .pocketTube:
            return videoStatusText ?? sectionStatusText
        }
    }

    private var isRefreshing: Bool {
        isLoadingVideos || (selectedMode == .pocketTube && isLoadingSections)
    }

    private var emptyStateTitle: String {
        selectedMode == .watchLater ? "No Watch Later videos found." : "No videos in this section."
    }

    private var emptyStateMessage: String {
        if let currentErrorText {
            return currentErrorText
        }

        if selectedMode == .watchLater {
            return "Pull to refresh to check again."
        }

        return "Pull to refresh to check again."
    }

    private var hasActiveSearch: Bool {
        !normalizedActiveSearchQuery.isEmpty
    }

    private var normalizedActiveSearchQuery: String {
        normalizedSearchText(searchText)
    }

    @MainActor
    private func initialize() async {
        if selectedMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
        }
        await loadVideosForCurrentMode(reset: true)
    }

    @MainActor
    private func handleModeChange(_ newMode: Mode) async {
        if newMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
            if selectedPocketTubeSectionKey == nil && filterChips.count > 1 {
                selectedPocketTubeSectionKey = filterChips.dropFirst().first?.key
            }
        }
        await loadVideosForCurrentMode(reset: true)
    }

    @MainActor
    private func refreshCurrentMode(forceSectionsReload: Bool) async {
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
            let result = try await DragonAPIClient.shared.fetchYouTubeSections()
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
            if let selectedPocketTubeSectionKey, !availableSectionKeys.contains(selectedPocketTubeSectionKey) {
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
            let response: DragonYouTubeResponse
            let offset = reset ? 0 : (nextVideoOffset ?? videos.count)
            let result: DragonAPIFetchResult<DragonYouTubeResponse>

            switch selectedMode {
            case .watchLater:
                result = try await DragonAPIClient.shared.fetchYouTubeVideos(
                    source: "watchlater",
                    limit: limit,
                    offset: offset,
                    query: activeQuery
                )
            case .pocketTube:
                result = try await DragonAPIClient.shared.fetchYouTubeVideos(
                    source: "pockettube",
                    section: selectedPocketTubeSectionKey,
                    limit: limit,
                    offset: offset,
                    query: activeQuery
                )
            }
            response = result.value

            guard response.ok else {
                handleVideoFailure("Backend returned an error.", hadVisibleData: hadVisibleVideos)
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

            switch selectedMode {
            case .watchLater:
                watchLaterLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            case .pocketTube:
                pocketTubeLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            }
        } catch {
            handleVideoFailure(dragonUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadVideosForCurrentMode(reset: true)
        }
    }

    @MainActor
    private func loadMoreVideosForCurrentMode() async {
        guard !isLoadingVideos, !isLoadingMoreVideos, hasMoreVideos else {
            return
        }

        isLoadingMoreVideos = true
        let hadVisibleVideos = !videos.isEmpty

        do {
            let response: DragonYouTubeResponse
            let offset = nextVideoOffset ?? videos.count
            let result: DragonAPIFetchResult<DragonYouTubeResponse>

            switch selectedMode {
            case .watchLater:
                result = try await DragonAPIClient.shared.fetchYouTubeVideos(
                    source: "watchlater",
                    limit: limit,
                    offset: offset,
                    query: normalizedActiveSearchQuery
                )
            case .pocketTube:
                result = try await DragonAPIClient.shared.fetchYouTubeVideos(
                    source: "pockettube",
                    section: selectedPocketTubeSectionKey,
                    limit: limit,
                    offset: offset,
                    query: normalizedActiveSearchQuery
                )
            }
            response = result.value

            guard response.ok else {
                handleLoadMoreFailure("Backend returned an error.", hadVisibleData: hadVisibleVideos)
                isLoadingMoreVideos = false
                return
            }

            videos = mergeVideos(existing: videos, incoming: response.items)
            hasMoreVideos = response.has_more
            nextVideoOffset = response.next_offset
            videoErrorText = nil
            videoStatusText = result.source.statusMessage
            switch selectedMode {
            case .watchLater:
                watchLaterLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            case .pocketTube:
                pocketTubeLastUpdatedAt = result.source.cachedMetadata?.cachedAt ?? Date()
            }
        } catch {
            handleLoadMoreFailure(dragonUserFacingMessage(for: error), hadVisibleData: hadVisibleVideos)
        }

        isLoadingMoreVideos = false
        if pendingVideoReset {
            pendingVideoReset = false
            await loadVideosForCurrentMode(reset: true)
        }
    }

    private func handleVideoFailure(_ message: String, hadVisibleData: Bool) {
        if hadVisibleData {
            videoErrorText = nil
        } else {
            videoErrorText = message
            videoStatusText = nil
        }
    }

    private func handleLoadMoreFailure(_ message: String, hadVisibleData: Bool) {
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

    private func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
