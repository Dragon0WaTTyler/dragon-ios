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
                    label: "Catalog channels",
                    value: viewModel.metricValue(viewModel.cachedChannelCount)
                )
                DragonAdminMetricView(
                    label: "Working channels",
                    value: viewModel.metricValue(viewModel.workingChannelCount, fallback: "Not checked yet")
                )
                DragonAdminMetricView(
                    label: "Checked channels",
                    value: viewModel.metricValue(viewModel.checkedChannelCount, fallback: "Not checked yet")
                )
                DragonAdminMetricView(
                    label: "Raw",
                    value: viewModel.metricValue(viewModel.rawChannelCount)
                )
                DragonAdminMetricView(
                    label: "Deduped",
                    value: viewModel.metricValue(viewModel.dedupedChannelCount)
                )
                DragonAdminMetricView(
                    label: "Failed sources",
                    value: "\(viewModel.catalogFailedSourceCount)"
                )
                DragonAdminMetricView(
                    label: "Failed checks",
                    value: viewModel.metricValue(viewModel.failedHealthChannelCount, fallback: "Not checked yet")
                )
                DragonAdminMetricView(
                    label: "Favorites",
                    value: "\(viewModel.favoriteCount)"
                )
                DragonAdminMetricView(
                    label: "Sources",
                    value: "\(viewModel.sourceCount)"
                )
                DragonAdminMetricView(
                    label: "Enabled sources",
                    value: "\(viewModel.enabledSourceCount)"
                )
                DragonAdminMetricView(
                    label: "Diagnostics",
                    value: viewModel.metricValue(viewModel.diagnosticsCount)
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
                        await viewModel.refreshCatalog()
                    }
                } label: {
                    HStack {
                        if viewModel.status == .loading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(viewModel.status == .loading ? "Refreshing..." : "Refresh Catalog")
                    }
                }
                .buttonStyle(DragonAdminFilledButtonStyle())
                .disabled(viewModel.status == .loading)

                Button {
                    Task {
                        await viewModel.runHealthCheck()
                    }
                } label: {
                    Text("Run Health Check")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(viewModel.status == .loading)
            }

            Button {
                Task {
                    await viewModel.clearCache()
                }
            } label: {
                Text("Clear TV Cache")
            }
            .buttonStyle(DragonAdminOutlineButtonStyle())
            .disabled(viewModel.status == .loading)

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
                Text("Diagnostics appear after a catalog refresh or a manual health check.")
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
                        lastUpdatedAt: viewModel.lastHealthCheckedAt ?? viewModel.lastCatalogUpdatedAt
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

struct DragonTVSettingsStatusPanel: View {
    @StateObject private var viewModel = DragonTVAdminViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                DragonAdminMetricView(
                    label: "Total channels",
                    value: viewModel.metricValue(viewModel.cachedChannelCount)
                )
                DragonAdminMetricView(
                    label: "Working",
                    value: viewModel.metricValue(viewModel.workingChannelCount, fallback: "Not checked yet")
                )
                DragonAdminMetricView(
                    label: "Checked",
                    value: viewModel.metricValue(viewModel.checkedChannelCount, fallback: "Not checked yet")
                )
                DragonAdminMetricView(
                    label: "Failed",
                    value: viewModel.metricValue(viewModel.failedHealthChannelCount, fallback: "Not checked yet")
                )
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.gray)

            Text(viewModel.lastRefreshLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            if let errorText = viewModel.errorText?.dragonTrimmedOrNil {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.refreshCatalog()
                    }
                } label: {
                    HStack {
                        if viewModel.status == .loading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(viewModel.status == .loading ? "Refreshing..." : "Refresh Catalog")
                    }
                }
                .buttonStyle(DragonAdminFilledButtonStyle())
                .disabled(viewModel.status == .loading)

                Button {
                    Task {
                        await viewModel.runHealthCheck()
                    }
                } label: {
                    Text("Run Health Check")
                }
                .buttonStyle(DragonAdminOutlineButtonStyle())
                .disabled(viewModel.status == .loading)
            }

            if !viewModel.sourceDiagnostics.isEmpty {
                NavigationLink {
                    DragonTVAdminDiagnosticsView(
                        diagnostics: viewModel.sourceDiagnostics,
                        lastUpdatedAt: viewModel.lastHealthCheckedAt ?? viewModel.lastCatalogUpdatedAt
                    )
                } label: {
                    HStack {
                        Text("View Per-Source Diagnostics")
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
        .task {
            await viewModel.loadIfNeeded()
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
    @Published private(set) var rawChannelCount: Int?
    @Published private(set) var dedupedChannelCount: Int?
    @Published private(set) var lastCatalogUpdatedAt: Date?
    @Published private(set) var lastHealthCheckedAt: Date?
    @Published private(set) var sourceCount = 0
    @Published private(set) var enabledSourceCount = 0
    @Published private(set) var workingChannelCount: Int?
    @Published private(set) var checkedChannelCount: Int?
    @Published private(set) var failedHealthChannelCount: Int?
    @Published private(set) var diagnosticsCount: Int?
    @Published private(set) var catalogFailedSourceCount = 0
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

    func refreshCatalog() async {
        status = .loading
        errorText = nil
        statusMessage = "Refreshing the TV playlist catalog."
        reloadLocalSources()

        do {
            let result = try await dataSource.refreshChannels()
            favoriteCount = favoritesStore.favoriteCount()
            applyCatalog(
                report: result.report,
                updatedAt: result.refreshedAt,
                status: .ready
            )
            statusMessage = refreshMessage(for: result.report)
        } catch {
            errorText = error.localizedDescription
            status = .error
            statusMessage = "TV catalog refresh failed."
            favoriteCount = favoritesStore.favoriteCount()
        }
    }

    func runHealthCheck() async {
        status = .loading
        errorText = nil
        statusMessage = "Checking channel health with timeouts and limited concurrency."
        reloadLocalSources()

        do {
            let result = try await dataSource.runHealthCheck()
            favoriteCount = favoritesStore.favoriteCount()
            applyHealth(snapshot: result.snapshot, status: .ready)
            statusMessage = healthRefreshMessage(for: result.snapshot)
        } catch {
            errorText = error.localizedDescription
            status = .error
            statusMessage = "TV health check failed."
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

    func metricValue(_ value: Int?, fallback: String = "Unavailable") -> String {
        guard let value else {
            return fallback
        }

        return "\(value)"
    }

    var lastRefreshLabel: String {
        if let lastHealthCheckedAt {
            return "Last health check: \(Self.dateFormatter.string(from: lastHealthCheckedAt))"
        }

        guard let lastCatalogUpdatedAt else {
            return "Last update: Not available"
        }

        return "Last catalog refresh: \(Self.dateFormatter.string(from: lastCatalogUpdatedAt))"
    }

    var sourcesStatusText: String {
        "\(enabledSourceCount)/\(sourceCount) enabled"
    }

    private func loadCachedState(defaultMessage: String) async {
        do {
            let cachedCatalog = try await cacheStore.loadCachedReport()
            let cachedHealthSnapshot = try await cacheStore.loadCachedHealthSnapshot()

            if let cachedCatalog {
                applyCatalog(
                    report: cachedCatalog.report,
                    updatedAt: cachedCatalog.cachedAt,
                    status: .cached
                )

                if let cachedHealthSnapshot {
                    applyHealth(snapshot: cachedHealthSnapshot.snapshot, status: .cached)
                    statusMessage = "Loaded cached TV catalog and last health snapshot."
                } else {
                    clearHealthSnapshot(status: .cached)
                    statusMessage = "Loaded cached TV catalog. Health not checked yet."
                }
            } else {
                setEmptyDiagnosticsState(status: .cached, message: defaultMessage)
            }
        } catch {
            status = .error
            errorText = error.localizedDescription
            statusMessage = "Could not read the local TV cache."
            cachedChannelCount = nil
            rawChannelCount = nil
            dedupedChannelCount = nil
            lastCatalogUpdatedAt = nil
            lastHealthCheckedAt = nil
            workingChannelCount = nil
            checkedChannelCount = nil
            failedHealthChannelCount = nil
            diagnosticsCount = nil
            catalogFailedSourceCount = 0
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
            rawChannelCount = nil
            dedupedChannelCount = nil
            lastCatalogUpdatedAt = nil
            lastHealthCheckedAt = nil
            workingChannelCount = nil
            checkedChannelCount = nil
            failedHealthChannelCount = nil
            diagnosticsCount = nil
            catalogFailedSourceCount = 0
            interestingDiscoveryCount = nil
            sourceDiagnostics = []
        }
    }

    private func setEmptyDiagnosticsState(status: Status, message: String) {
        self.status = status
        statusMessage = message
        errorText = nil
        cachedChannelCount = 0
        rawChannelCount = 0
        dedupedChannelCount = 0
        lastCatalogUpdatedAt = nil
        lastHealthCheckedAt = nil
        workingChannelCount = nil
        checkedChannelCount = nil
        failedHealthChannelCount = nil
        diagnosticsCount = 0
        catalogFailedSourceCount = 0
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

    private func applyCatalog(
        report: IPTVLoadReport,
        updatedAt: Date,
        status: Status
    ) {
        reloadLocalSources()
        self.status = status
        errorText = nil
        cachedChannelCount = report.channels.count
        rawChannelCount = report.rawChannelCount
        dedupedChannelCount = report.dedupedChannelCount
        lastCatalogUpdatedAt = updatedAt
        catalogFailedSourceCount = report.sourceFailures.count
        interestingDiscoveryCount = report.interestingChannelDiagnostics.count

        if lastHealthCheckedAt == nil {
            sourceDiagnostics = report.sourceDiagnostics
            diagnosticsCount = report.sourceDiagnostics.count
        }
    }

    private func applyHealth(snapshot: IPTVHealthSnapshot, status: Status) {
        self.status = status
        errorText = nil
        lastHealthCheckedAt = snapshot.lastCheckedAt
        workingChannelCount = snapshot.workingChannelCount
        checkedChannelCount = snapshot.checkedChannelCount
        failedHealthChannelCount = snapshot.failedChannelCount
        sourceDiagnostics = snapshot.sourceDiagnostics
        diagnosticsCount = snapshot.sourceDiagnostics.count
    }

    private func clearHealthSnapshot(status: Status) {
        self.status = status
        lastHealthCheckedAt = nil
        workingChannelCount = nil
        checkedChannelCount = nil
        failedHealthChannelCount = nil
    }

    private func refreshMessage(for report: IPTVLoadReport) -> String {
        if report.channels.isEmpty {
            if report.sourceFailures.isEmpty {
                return "Catalog refresh finished, but no TV channels were parsed."
            }

            return "Catalog refresh finished with source failures and no TV channels."
        }

        if report.sourceFailures.isEmpty {
            return "Catalog refresh finished with \(report.channels.count) TV channels."
        }

        return "Catalog refresh finished with \(report.channels.count) TV channels and \(report.sourceFailures.count) failed source\(report.sourceFailures.count == 1 ? "" : "s")."
    }

    private func healthRefreshMessage(for snapshot: IPTVHealthSnapshot) -> String {
        "Health check finished with \(snapshot.workingChannelCount) working channel\(snapshot.workingChannelCount == 1 ? "" : "s"), \(snapshot.failedChannelCount) failed, \(snapshot.checkedChannelCount) checked."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
