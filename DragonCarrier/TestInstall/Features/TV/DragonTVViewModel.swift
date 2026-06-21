import Combine
import Foundation

@MainActor
final class DragonTVViewModel: ObservableObject {
    @Published private(set) var channels: [IPTVChannel]
    @Published private(set) var rawChannelCount: Int
    @Published private(set) var dedupedChannelCount: Int
    @Published private(set) var validChannelCount: Int
    @Published private(set) var failedSourceCount: Int
    @Published private(set) var sourceFailures: [IPTVSourceFailure]
    @Published private(set) var sourceDiagnostics: [IPTVSourceDiagnostic]
    @Published private(set) var interestingChannelDiagnostics: [IPTVInterestingChannelDiagnostic]
    @Published private(set) var isLoading: Bool
    @Published private(set) var statusText: String
    @Published private(set) var lastUpdatedAt: Date?
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
        initialValidChannelCount: Int = 0,
        initialFailedSourceCount: Int = 0,
        initialSourceFailures: [IPTVSourceFailure] = [],
        initialSourceDiagnostics: [IPTVSourceDiagnostic] = [],
        initialInterestingChannelDiagnostics: [IPTVInterestingChannelDiagnostic] = [],
        initialIsLoading: Bool = false,
        initialStatusText: String = "",
        initialLastUpdatedAt: Date? = nil,
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
        self.validChannelCount = initialValidChannelCount
        self.failedSourceCount = initialFailedSourceCount
        self.sourceFailures = initialSourceFailures
        self.sourceDiagnostics = initialSourceDiagnostics
        self.interestingChannelDiagnostics = initialInterestingChannelDiagnostics
        self.isLoading = initialIsLoading
        self.statusText = initialStatusText
        self.lastUpdatedAt = initialLastUpdatedAt
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
                channel.group ?? "",
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
        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let shouldRevealSupplementalChannels =
            selectedFilter == .sports ||
            Self.diagnosticSearchKeywords.contains { normalizedSearch.contains($0) }

        guard shouldRevealSupplementalChannels else {
            return []
        }

        let primaryChannelIDs = Set(channels.map(\.id))

        return interestingChannelDiagnostics.compactMap { diagnostic in
            guard diagnostic.status == .parsedButFailedValidation,
                  !primaryChannelIDs.contains(diagnostic.channelID) else {
                return nil
            }

            let channel = IPTVChannel(
                id: diagnostic.channelID,
                name: diagnostic.name,
                url: diagnostic.streamURL,
                tvgId: nil,
                group: diagnostic.group,
                logo: diagnostic.logoURL,
                httpUserAgent: diagnostic.httpUserAgent,
                sourceURLs: diagnostic.sourceURLs,
                isFavorite: favoriteIDs.contains(diagnostic.channelID)
            )

            guard selectedFilter.matches(channel) else {
                return nil
            }

            guard !normalizedSearch.isEmpty else {
                return channel
            }

            let searchableValues = [
                channel.name,
                channel.group ?? "",
                channel.tvgId ?? "",
                channel.sourceSummary,
                channel.hostLabel
            ]
            .joined(separator: " ")
            .lowercased()

            return searchableValues.contains(normalizedSearch) ? channel : nil
        }
    }

    private static let diagnosticSearchKeywords: [String] = [
        "arryadia",
        "al kass",
        "alkass",
        "ksa sports",
        "sharjah sports",
        "bahrain sports",
        "ktv sport",
        "oman sports",
        "iraqia sport",
        "sport",
        "sports",
        "bein"
    ]

    var favoriteCount: Int {
        channels.filter(\.isFavorite).count
    }

    var channelCountLabel: String {
        "\(validChannelCount) working"
    }

    var downloadedSourceCount: Int {
        sourceDiagnostics.filter(\.downloadSucceeded).count
    }

    var totalSourceCount: Int {
        sourceDiagnostics.count
    }

    var interestingParsedCount: Int {
        interestingChannelDiagnostics.count
    }

    var interestingWorkingCount: Int {
        interestingChannelDiagnostics.filter { $0.status == .validatedWorking }.count
    }

    var interestingFailedCount: Int {
        interestingChannelDiagnostics.filter { $0.status == .parsedButFailedValidation }.count
    }

    func loadCachedThenRefreshIfNeeded() async {
        guard !hasLoadedInitially else {
            return
        }

        hasLoadedInitially = true
        favoriteIDs = favoritesStore.loadFavoriteIDs()

        if let cachedResult = await dataSource.loadCachedChannels() {
            apply(report: cachedResult.report, updatedAt: cachedResult.cachedAt)
            statusText = cachedResult.report.channels.isEmpty
                ? "TV cache is empty. Refreshing playlists now."
                : "Showing cached channels while refreshing playlists."
            await refresh()
        } else {
            statusText = "No TV cache yet. Loading public playlists."
            await refresh()
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        if channels.isEmpty {
            statusText = "Downloading playlists, deduplicating channels, and validating streams."
        } else {
            statusText = "Refreshing channels and rechecking stream reachability."
        }

        do {
            let result = try await dataSource.refreshChannels()
            apply(report: result.report, updatedAt: result.refreshedAt)

            if result.report.channels.isEmpty {
                statusText = result.report.sourceFailures.isEmpty
                    ? "Refresh completed but no reachable channels were found."
                    : "Refresh completed with source failures and no reachable channels."
            } else if result.report.sourceFailures.isEmpty {
                statusText = "Refresh completed with \(result.report.channels.count) working channels."
            } else {
                statusText = "Refresh completed with \(result.report.channels.count) working channels and \(result.report.sourceFailures.count) source failure\(result.report.sourceFailures.count == 1 ? "" : "s")."
            }
        } catch {
            errorMessage = error.localizedDescription

            if channels.isEmpty {
                statusText = "TV refresh failed and no cached channels are available."
            } else {
                statusText = "TV refresh failed. Showing cached channels."
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

    private func apply(report: IPTVLoadReport, updatedAt: Date) {
        channels = report.channels.map { $0.applyingFavorite(favoriteIDs.contains($0.id)) }
        rawChannelCount = report.rawChannelCount
        dedupedChannelCount = report.dedupedChannelCount
        validChannelCount = report.validChannelCount
        failedSourceCount = report.sourceFailures.count
        sourceFailures = report.sourceFailures
        sourceDiagnostics = report.sourceDiagnostics
        interestingChannelDiagnostics = report.interestingChannelDiagnostics
        lastUpdatedAt = updatedAt
    }
}
