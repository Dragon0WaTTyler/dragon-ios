import Combine
import Foundation

@MainActor
final class DragonTVViewModel: ObservableObject {
    @Published private(set) var channels: [IPTVChannel]
    @Published private(set) var rawChannelCount: Int
    @Published private(set) var dedupedChannelCount: Int
    @Published private(set) var workingChannelCount: Int?
    @Published private(set) var checkedChannelCount: Int?
    @Published private(set) var failedHealthChannelCount: Int?
    @Published private(set) var failedSourceCount: Int
    @Published private(set) var isLoading: Bool
    @Published private(set) var statusText: String
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastHealthCheckedAt: Date?
    @Published var searchText: String
    @Published var selectedFilter: DragonTVFilter
    @Published var errorMessage: String?

    private let dataSource: DragonTVDataSource
    private let favoritesStore: DragonTVFavoritesStore
    private var favoriteIDs: Set<String>
    private var hasLoadedInitially = false

    init(
        dataSource: DragonTVDataSource = DragonDefaultTVDataSource(),
        favoritesStore: DragonTVFavoritesStore = DragonTVFavoritesStore(),
        initialChannels: [IPTVChannel] = [],
        initialRawChannelCount: Int = 0,
        initialDedupedChannelCount: Int = 0,
        initialWorkingChannelCount: Int? = nil,
        initialCheckedChannelCount: Int? = nil,
        initialFailedHealthChannelCount: Int? = nil,
        initialFailedSourceCount: Int = 0,
        initialIsLoading: Bool = false,
        initialStatusText: String = "",
        initialLastUpdatedAt: Date? = nil,
        initialLastHealthCheckedAt: Date? = nil,
        initialSearchText: String = "",
        initialSelectedFilter: DragonTVFilter = .all,
        initialErrorMessage: String? = nil
    ) {
        let loadedFavoriteIDs = favoritesStore.loadFavoriteIDs()

        self.dataSource = dataSource
        self.favoritesStore = favoritesStore
        self.favoriteIDs = loadedFavoriteIDs
        self.channels = initialChannels.map { $0.applyingFavorite(loadedFavoriteIDs.contains($0.id)) }
        self.rawChannelCount = initialRawChannelCount
        self.dedupedChannelCount = initialDedupedChannelCount
        self.workingChannelCount = initialWorkingChannelCount
        self.checkedChannelCount = initialCheckedChannelCount
        self.failedHealthChannelCount = initialFailedHealthChannelCount
        self.failedSourceCount = initialFailedSourceCount
        self.isLoading = initialIsLoading
        self.statusText = initialStatusText
        self.lastUpdatedAt = initialLastUpdatedAt
        self.lastHealthCheckedAt = initialLastHealthCheckedAt
        self.searchText = initialSearchText
        self.selectedFilter = initialSelectedFilter
        self.errorMessage = initialErrorMessage
    }

    var visibleChannels: [IPTVChannel] {
        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return channels.filter { channel in
            guard selectedFilter.matches(channel) else {
                return false
            }

            guard !normalizedSearch.isEmpty else {
                return true
            }

            let searchableValues = [
                channel.name,
                channel.displayGroupLabel ?? channel.group ?? "",
                channel.tvgId ?? "",
                channel.sourceSummary,
                channel.hostLabel
            ]
            .joined(separator: " ")
            .lowercased()

            return searchableValues.contains(normalizedSearch)
        }
    }

    var visibleSupplementalChannels: [IPTVChannel] {
        []
    }

    var favoriteCount: Int {
        channels.filter(\.isFavorite).count
    }

    var channelCountLabel: String {
        "\(channels.count) channel\(channels.count == 1 ? "" : "s")"
    }

    func loadCachedThenRefreshIfNeeded() async {
        guard !hasLoadedInitially else {
            return
        }

        hasLoadedInitially = true
        favoriteIDs = favoritesStore.loadFavoriteIDs()

        if let cachedResult = await dataSource.loadCachedChannels() {
            applyCatalog(report: cachedResult.report, updatedAt: cachedResult.cachedAt)
            statusText = cachedResult.report.channels.isEmpty
                ? "TV catalog cache is empty. Refresh to rebuild the playlist catalog."
                : "Showing cached TV catalog."
        } else {
            statusText = "No TV cache yet. Loading playlist catalog."
            await refresh()
        }

        if let cachedHealthSnapshot = await dataSource.loadCachedHealthSnapshot() {
            applyHealth(snapshot: cachedHealthSnapshot.snapshot)
        } else {
            clearHealthSnapshot()
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        statusText = channels.isEmpty
            ? "Downloading playlists and building the TV catalog."
            : "Refreshing the cached TV catalog."

        do {
            let result = try await dataSource.refreshChannels()
            applyCatalog(report: result.report, updatedAt: result.refreshedAt)

            if result.report.channels.isEmpty {
                statusText = result.report.sourceFailures.isEmpty
                    ? "Catalog refresh completed, but no TV channels were parsed."
                    : "Catalog refresh completed with source failures and no parsed TV channels."
            } else if result.report.sourceFailures.isEmpty {
                statusText = "Catalog refresh completed with \(result.report.channels.count) channels."
            } else {
                statusText = "Catalog refresh completed with \(result.report.channels.count) channels and \(result.report.sourceFailures.count) failed source\(result.report.sourceFailures.count == 1 ? "" : "s")."
            }
        } catch {
            errorMessage = error.localizedDescription

            if channels.isEmpty {
                statusText = "TV catalog refresh failed and no cached channels are available."
            } else {
                statusText = "TV catalog refresh failed. Showing cached channels."
            }
        }

        isLoading = false
    }

    func toggleFavorite(_ channel: IPTVChannel) {
        let shouldFavorite = !favoriteIDs.contains(channel.id)
        favoriteIDs = favoritesStore.updateFavorite(id: channel.id, isFavorite: shouldFavorite)
        channels = channels.map { current in
            guard current.id == channel.id else {
                return current
            }

            return current.applyingFavorite(shouldFavorite)
        }
    }

    private func applyCatalog(report: IPTVLoadReport, updatedAt: Date) {
        channels = report.channels.map { $0.applyingFavorite(favoriteIDs.contains($0.id)) }
        rawChannelCount = report.rawChannelCount
        dedupedChannelCount = report.dedupedChannelCount
        failedSourceCount = report.sourceFailures.count
        lastUpdatedAt = updatedAt
    }

    private func applyHealth(snapshot: IPTVHealthSnapshot) {
        checkedChannelCount = snapshot.checkedChannelCount
        workingChannelCount = snapshot.workingChannelCount
        failedHealthChannelCount = snapshot.failedChannelCount
        lastHealthCheckedAt = snapshot.lastCheckedAt
    }

    private func clearHealthSnapshot() {
        checkedChannelCount = nil
        workingChannelCount = nil
        failedHealthChannelCount = nil
        lastHealthCheckedAt = nil
    }
}
