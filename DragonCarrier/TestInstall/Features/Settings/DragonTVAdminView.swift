import SwiftUI

struct DragonTVAdminView: View {
    @StateObject private var viewModel = DragonTVAdminViewModel()
    @State private var showClearFavoritesConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    diagnosticsSection

                    DragonTVAdminSourcesView(
                        sources: viewModel.sources,
                        statusText: viewModel.sourcesStatusText,
                        onSaveSource: { source in
                            Task {
                                await viewModel.saveSource(source)
                            }
                        },
                        onDeleteSource: { source in
                            Task {
                                await viewModel.deleteCustomSource(source)
                            }
                        },
                        onResetSources: {
                            Task {
                                await viewModel.resetSourcesToDefaults()
                            }
                        }
                    )
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Clear TV favorites?", isPresented: $showClearFavoritesConfirmation) {
            Button("Clear", role: .destructive) {
                viewModel.clearFavorites()
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
                Text("TV Admin")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text("Manage local TV diagnostics and editable playlist sources.")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    private var diagnosticsSection: some View {
        DragonAdminSectionCard(
            title: "Diagnostics",
            status: viewModel.status.title,
            statusColor: viewModel.status.color,
            message: viewModel.statusMessage
        ) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                DragonAdminMetricView(
                    label: "Cached channels",
                    value: viewModel.metricValue(viewModel.cachedChannelCount)
                )
                DragonAdminMetricView(
                    label: "Working channels",
                    value: viewModel.metricValue(viewModel.workingChannelCount)
                )
                DragonAdminMetricView(
                    label: "Sources",
                    value: "\(viewModel.sourceCount)"
                )
                DragonAdminMetricView(
                    label: "Failed sources",
                    value: viewModel.metricValue(viewModel.failedSourceCount)
                )
                DragonAdminMetricView(
                    label: "Diagnostics",
                    value: viewModel.metricValue(viewModel.diagnosticsCount)
                )
                DragonAdminMetricView(
                    label: "Sports/beIN",
                    value: viewModel.metricValue(viewModel.interestingDiscoveryCount)
                )
                DragonAdminMetricView(
                    label: "Favorites",
                    value: "\(viewModel.favoriteCount)"
                )
                DragonAdminMetricView(
                    label: "Enabled sources",
                    value: "\(viewModel.enabledSourceCount)"
                )
            }

            if let errorText = viewModel.errorText?.dragonTrimmedOrNil {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            Text(viewModel.lastRefreshLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    HStack {
                        if viewModel.status == .loading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(viewModel.status == .loading ? "Refreshing..." : "Refresh TV Channels")
                    }
                }
                .buttonStyle(DragonAdminFilledButtonStyle())
                .disabled(viewModel.status == .loading)

                Button {
                    Task {
                        await viewModel.clearCache()
                    }
                } label: {
                    Text("Clear TV Cache")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(viewModel.status == .loading)
            }

            if viewModel.favoriteCount > 0 {
                Button {
                    showClearFavoritesConfirmation = true
                } label: {
                    Text("Clear TV Favorites")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(viewModel.status == .loading)
            }

            if viewModel.sourceDiagnostics.isEmpty {
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
                        diagnostics: viewModel.sourceDiagnostics,
                        lastUpdatedAt: viewModel.lastUpdatedAt
                    )
                } label: {
                    HStack {
                        Text("View Full Diagnostics")
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
                return .orange
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
    @Published private(set) var sourceCount = 0
    @Published private(set) var enabledSourceCount = 0
    @Published private(set) var workingChannelCount: Int?
    @Published private(set) var diagnosticsCount: Int?
    @Published private(set) var failedSourceCount: Int?
    @Published private(set) var interestingDiscoveryCount: Int?
    @Published private(set) var favoriteCount = 0
    @Published private(set) var sourceDiagnostics: [IPTVSourceDiagnostic] = []
    @Published private(set) var sources: [DragonTVSource] = []

    private let dataSource: DragonTVDataSource
    private let cacheStore: DragonTVCacheStore
    private let favoritesStore: DragonTVFavoritesStore
    private let sourceStore: DragonTVSourceStore
    private var hasLoaded = false

    init(
        dataSource: DragonTVDataSource = DragonDefaultTVDataSource(),
        cacheStore: DragonTVCacheStore = DragonTVCacheStore(),
        favoritesStore: DragonTVFavoritesStore = DragonTVFavoritesStore(),
        sourceStore: DragonTVSourceStore = DragonTVSourceStore()
    ) {
        self.dataSource = dataSource
        self.cacheStore = cacheStore
        self.favoritesStore = favoritesStore
        self.sourceStore = sourceStore
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        reloadLocalSources()
        favoriteCount = favoritesStore.favoriteCount()
        await loadCachedState(defaultMessage: "No cached TV data available.")
    }

    func refresh() async {
        status = .loading
        errorText = nil
        statusMessage = "Refreshing TV playlists and validating streams."
        reloadLocalSources()

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
            setEmptyDiagnosticsState(
                status: .cached,
                message: "TV cache cleared. Refresh to scan playlists again."
            )
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

    func saveSource(_ source: DragonTVSource) async {
        do {
            try sourceStore.save(source)
            await invalidateCacheAfterSourceChange(message: "TV sources updated. Refresh required.")
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "Could not save TV source changes."
        }
    }

    func deleteCustomSource(_ source: DragonTVSource) async {
        guard !source.isBuiltIn else {
            return
        }

        do {
            try sourceStore.deleteCustomSource(id: source.id)
            await invalidateCacheAfterSourceChange(message: "Custom TV source deleted. Refresh required.")
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "Could not delete custom TV source."
        }
    }

    func resetSourcesToDefaults() async {
        do {
            try sourceStore.resetToDefaults()
            await invalidateCacheAfterSourceChange(message: "TV sources reset to defaults. Refresh required.")
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "Could not reset TV sources."
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

    var sourcesStatusText: String {
        "\(enabledSourceCount)/\(sourceCount) enabled"
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
                setEmptyDiagnosticsState(status: .cached, message: defaultMessage)
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
            interestingDiscoveryCount = nil
            sourceDiagnostics = []
            reloadLocalSources()
        }
    }

    private func invalidateCacheAfterSourceChange(message: String) async {
        reloadLocalSources()
        favoriteCount = favoritesStore.favoriteCount()

        do {
            try await cacheStore.clear()
            setEmptyDiagnosticsState(status: .cached, message: message)
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "TV sources changed, but the old TV cache could not be cleared."
            cachedChannelCount = nil
            lastUpdatedAt = nil
            workingChannelCount = nil
            diagnosticsCount = nil
            failedSourceCount = nil
            interestingDiscoveryCount = nil
            sourceDiagnostics = []
        }
    }

    private func setEmptyDiagnosticsState(status: Status, message: String) {
        self.status = status
        statusMessage = message
        errorText = nil
        cachedChannelCount = 0
        lastUpdatedAt = nil
        workingChannelCount = 0
        diagnosticsCount = 0
        failedSourceCount = 0
        interestingDiscoveryCount = 0
        sourceDiagnostics = []
        reloadLocalSources()
        favoriteCount = favoritesStore.favoriteCount()
    }

    private func reloadLocalSources() {
        sources = sourceStore.loadSources()
        sourceCount = sources.count
        enabledSourceCount = sources.filter(\.isEnabled).count
    }

    private func apply(
        report: IPTVLoadReport,
        updatedAt: Date,
        status: Status,
        message: String
    ) {
        reloadLocalSources()
        self.status = status
        statusMessage = message
        errorText = nil
        cachedChannelCount = report.channels.count
        lastUpdatedAt = updatedAt
        workingChannelCount = report.validChannelCount
        diagnosticsCount = report.sourceDiagnostics.count
        failedSourceCount = report.sourceFailures.count
        interestingDiscoveryCount = report.interestingChannelDiagnostics.count
        sourceDiagnostics = report.sourceDiagnostics
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
