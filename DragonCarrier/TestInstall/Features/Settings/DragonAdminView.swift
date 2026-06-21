import SwiftUI

struct DragonAdminView: View {
    @StateObject private var tvAdmin = DragonTVAdminViewModel()
    @State private var showClearFavoritesConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private let placeholderSections = [
        "Movies",
        "YouTube",
        "Articles",
        "Books",
        "Chess"
    ]

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    tvSection

                    ForEach(placeholderSections, id: \.self) { section in
                        DragonAdminSectionCard(
                            title: section,
                            status: "Placeholder",
                            statusColor: .gray,
                            message: "Not wired in iOS admin yet"
                        ) {
                            EmptyView()
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
        .task {
            await tvAdmin.loadIfNeeded()
        }
        .alert("Clear TV favorites?", isPresented: $showClearFavoritesConfirmation) {
            Button("Clear", role: .destructive) {
                tvAdmin.clearFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes local TV favorite channel IDs.")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(DragonTheme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Dragon Admin")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("Local management for Dragon sections.")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    private var tvSection: some View {
        DragonAdminSectionCard(
            title: "TV",
            status: tvAdmin.status.title,
            statusColor: tvAdmin.status.color,
            message: tvAdmin.statusMessage
        ) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                DragonAdminMetricView(
                    label: "Cached channels",
                    value: tvAdmin.metricValue(tvAdmin.cachedChannelCount)
                )
                DragonAdminMetricView(
                    label: "Working channels",
                    value: tvAdmin.metricValue(tvAdmin.workingChannelCount)
                )
                DragonAdminMetricView(
                    label: "Sources",
                    value: "\(tvAdmin.sourceCount)"
                )
                DragonAdminMetricView(
                    label: "Diagnostics",
                    value: tvAdmin.metricValue(tvAdmin.diagnosticsCount)
                )
                DragonAdminMetricView(
                    label: "Failed sources",
                    value: tvAdmin.metricValue(tvAdmin.failedSourceCount)
                )
                DragonAdminMetricView(
                    label: "Favorites",
                    value: "\(tvAdmin.favoriteCount)"
                )
            }

            if let errorText = tvAdmin.errorText?.dragonTrimmedOrNil {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            Text(tvAdmin.lastRefreshLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await tvAdmin.refresh()
                    }
                } label: {
                    HStack {
                        if tvAdmin.status == .loading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(tvAdmin.status == .loading ? "Refreshing..." : "Refresh TV Channels")
                    }
                }
                .buttonStyle(DragonAdminFilledButtonStyle())
                .disabled(tvAdmin.status == .loading)

                Button {
                    Task {
                        await tvAdmin.clearCache()
                    }
                } label: {
                    Text("Clear TV Cache")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(tvAdmin.status == .loading)
            }

            if tvAdmin.favoriteCount > 0 {
                Button {
                    showClearFavoritesConfirmation = true
                } label: {
                    Text("Clear TV Favorites")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(tvAdmin.status == .loading)
            }

            if tvAdmin.sourceDiagnostics.isEmpty {
                Text("Diagnostics unavailable until a cached or refreshed TV report exists.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                NavigationLink {
                    DragonTVAdminDiagnosticsView(
                        diagnostics: tvAdmin.sourceDiagnostics,
                        lastUpdatedAt: tvAdmin.lastUpdatedAt
                    )
                } label: {
                    HStack {
                        Text("View TV Diagnostics")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding()
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }
}

@MainActor
final class DragonTVAdminViewModel: ObservableObject {
    enum Status: Equatable {
        case ready
        case loading
        case error
        case cached

        var title: String {
            switch self {
            case .ready:
                return "Ready"
            case .loading:
                return "Loading"
            case .error:
                return "Error"
            case .cached:
                return "Cached"
            }
        }

        var color: Color {
            switch self {
            case .ready:
                return .green
            case .loading:
                return Color.orange
            case .error:
                return DragonTheme.red
            case .cached:
                return .gray
            }
        }
    }

    @Published private(set) var status: Status = .cached
    @Published private(set) var statusMessage = "No cached TV data available."
    @Published private(set) var errorText: String?
    @Published private(set) var cachedChannelCount: Int?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var sourceCount = IPTVPlaylistSource.defaultSources.count
    @Published private(set) var workingChannelCount: Int?
    @Published private(set) var diagnosticsCount: Int?
    @Published private(set) var failedSourceCount: Int?
    @Published private(set) var favoriteCount = 0
    @Published private(set) var sourceDiagnostics: [IPTVSourceDiagnostic] = []

    private let dataSource: DragonTVDataSource
    private let cacheStore: DragonTVCacheStore
    private let favoritesStore: DragonTVFavoritesStore
    private var hasLoaded = false

    init(
        dataSource: DragonTVDataSource = DragonDefaultTVDataSource(),
        cacheStore: DragonTVCacheStore = DragonTVCacheStore(),
        favoritesStore: DragonTVFavoritesStore = DragonTVFavoritesStore()
    ) {
        self.dataSource = dataSource
        self.cacheStore = cacheStore
        self.favoritesStore = favoritesStore
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        favoriteCount = favoritesStore.favoriteCount()
        await loadCachedState(defaultMessage: "No cached TV data available.")
    }

    func refresh() async {
        status = .loading
        errorText = nil
        statusMessage = "Refreshing TV playlists and validating streams."

        do {
            let result = try await dataSource.refreshChannels()
            favoriteCount = favoritesStore.favoriteCount()
            apply(
                report: result.report,
                updatedAt: result.refreshedAt,
                status: .ready,
                message: refreshMessage(for: result.report)
            )
        } catch {
            errorText = error.localizedDescription
            status = .error
            statusMessage = "TV refresh failed."
            favoriteCount = favoritesStore.favoriteCount()
        }
    }

    func clearCache() async {
        do {
            try await cacheStore.clear()
            errorText = nil
            status = .cached
            statusMessage = "TV cache cleared. Refresh to scan playlists again."
            cachedChannelCount = 0
            lastUpdatedAt = nil
            workingChannelCount = 0
            diagnosticsCount = 0
            failedSourceCount = 0
            sourceDiagnostics = []
            sourceCount = IPTVPlaylistSource.defaultSources.count
            favoriteCount = favoritesStore.favoriteCount()
        } catch {
            errorText = error.localizedDescription
            status = .error
            statusMessage = "Could not clear TV cache."
        }
    }

    func clearFavorites() {
        favoritesStore.clearFavorites()
        favoriteCount = 0

        if status != .error {
            statusMessage = "TV favorites cleared."
        }
    }

    func metricValue(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value)"
    }

    var lastRefreshLabel: String {
        guard let lastUpdatedAt else {
            return "Last refresh: Not available"
        }

        return "Last refresh: \(Self.dateFormatter.string(from: lastUpdatedAt))"
    }

    private func loadCachedState(defaultMessage: String) async {
        do {
            if let cached = try await cacheStore.loadCachedReport() {
                apply(
                    report: cached.report,
                    updatedAt: cached.cachedAt,
                    status: .cached,
                    message: "Loaded TV admin data from local cache."
                )
            } else {
                status = .cached
                errorText = nil
                statusMessage = defaultMessage
                cachedChannelCount = 0
                lastUpdatedAt = nil
                workingChannelCount = 0
                diagnosticsCount = 0
                failedSourceCount = 0
                sourceDiagnostics = []
                sourceCount = IPTVPlaylistSource.defaultSources.count
            }
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "Could not read the local TV cache."
            cachedChannelCount = nil
            lastUpdatedAt = nil
            workingChannelCount = nil
            diagnosticsCount = nil
            failedSourceCount = nil
            sourceDiagnostics = []
            sourceCount = IPTVPlaylistSource.defaultSources.count
        }
    }

    private func apply(
        report: IPTVLoadReport,
        updatedAt: Date,
        status: Status,
        message: String
    ) {
        self.status = status
        statusMessage = message
        errorText = nil
        cachedChannelCount = report.channels.count
        lastUpdatedAt = updatedAt
        workingChannelCount = report.validChannelCount
        diagnosticsCount = report.sourceDiagnostics.count
        failedSourceCount = report.sourceFailures.count
        sourceDiagnostics = report.sourceDiagnostics
        sourceCount = report.sourceDiagnostics.isEmpty ? IPTVPlaylistSource.defaultSources.count : report.sourceDiagnostics.count
    }

    private func refreshMessage(for report: IPTVLoadReport) -> String {
        if report.channels.isEmpty {
            if report.sourceFailures.isEmpty {
                return "Refresh finished, but no reachable TV channels were found."
            }

            return "Refresh finished with source failures and no reachable TV channels."
        }

        if report.sourceFailures.isEmpty {
            return "Refresh finished with \(report.validChannelCount) working TV channels."
        }

        return "Refresh finished with \(report.validChannelCount) working TV channels and \(report.sourceFailures.count) failed source\(report.sourceFailures.count == 1 ? "" : "s")."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
