import SwiftUI

enum DragonNotionConnectionState: Equatable {
    case notTested
    case connected(String)
    case failed(String)
}

struct DragonSettingsView: View {
    @State private var backendURLDraft = DragonBackendSettingsStore().backendURL
    @State private var connectionState: DragonBackendConnectionState = .notTested
    @State private var isChecking = false
    @State private var lastCheckedAt: Date?
    @State private var notionSourceIDDraft = DragonNotionSettingsStore().moviesSourceIdentifier
    @State private var notionTokenDraft = ""
    @State private var notionConnectionState: DragonNotionConnectionState = .notTested
    @State private var notionLastCheckedAt: Date?
    @State private var isCheckingNotion = false
    @State private var articleSources: [DragonRSSSourceDescriptor] = DragonArticlesSourceStore().loadSources()
    @State private var articleSourceURLDraft = ""
    @State private var articleSourceNameDraft = ""
    @State private var editingArticleSourceID: String?
    @State private var articleSourceErrorText: String?
    @State private var articleSourceStatusText: String?
    @State private var youTubePlaylistURLDraft = DragonYouTubeSettingsStore().playlistURL
    @State private var youTubeDisplayNameDraft = DragonYouTubeSettingsStore().displayName
    @State private var youTubeAPIKeyDraft = ""
    @State private var youTubeStoredPlaylistID = DragonYouTubeSettingsStore().playlistID
    @State private var youTubeHasStoredAPIKey = DragonYouTubeSettingsStore().hasAPIKey
    @State private var youTubeSettingsStatusText: String?
    @State private var youTubeSettingsErrorText: String?
    @State private var articleCacheCount: Int = 0
    @State private var movieCacheCount: Int = 0
    @State private var totalCacheCount: Int = 0
    @State private var cacheSizeBytes: Int64 = 0
    @State private var isRefreshingCacheInfo = false
    @State private var cacheStatusText: String?
    @State private var showClearCacheConfirmation = false

    private let settingsStore = DragonBackendSettingsStore()
    private let notionSettingsStore = DragonNotionSettingsStore()
    private let articlesSourceStore = DragonArticlesSourceStore()
    private let youTubeSettingsStore = DragonYouTubeSettingsStore()
    private let notionMoviesDataSource = DragonNotionMoviesDataSource()
    private let responseCache = DragonResponseCache.shared

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        homeHeader

                        NavigationLink {
                            dragonConnectionPage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "Dragon Connection",
                                message: "Legacy backend connection for developer testing only.",
                                badgeText: backendCardBadgeText,
                                badgeColor: backendCardBadgeColor
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            moviesPage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "Movies",
                                message: "Configure native Notion loading, secure token storage, and connection checks.",
                                badgeText: notionConfigurationLabel,
                                badgeColor: notionConfigurationColor
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            articlesPage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "Articles",
                                message: "Review RSS source coverage, article cache state, and refresh controls.",
                                badgeText: articlesCardBadgeText,
                                badgeColor: articlesCardBadgeColor
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            youTubePage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "YouTube",
                                message: "Configure native playlist loading, local cache behavior, and secure API key storage.",
                                badgeText: youTubeCardBadgeText,
                                badgeColor: youTubeCardBadgeColor
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            placeholderPage(
                                title: "Books",
                                subtitle: "Books settings are not configured here yet.",
                                message: "Books-specific controls can be organized here later. This task does not add or change Books data behavior."
                            )
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "Books",
                                message: "Placeholder page for future reading source and sync controls.",
                                badgeText: "Coming later",
                                badgeColor: .gray
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            tvPage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "TV / IPTV",
                                message: "TV diagnostics and editable IPTV source tools now live inside this section.",
                                badgeText: "Admin ready",
                                badgeColor: DragonTheme.red
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            developerPage
                        } label: {
                            DragonSettingsNavigationCard(
                                title: "Developer",
                                message: "Diagnostics, admin tools, and remaining cache actions for troubleshooting.",
                                badgeText: developerCardBadgeText,
                                badgeColor: developerCardBadgeColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .padding(.bottom, 24)
                }
            }
            .task {
                await loadInitialState()
            }
            .onReceive(NotificationCenter.default.publisher(for: dragonYouTubeConfigurationDidChangeNotification)) { _ in
                refreshYouTubeSettingsState()
            }
            .alert("Clear all cache?", isPresented: $showClearCacheConfirmation) {
                Button("Clear", role: .destructive) {
                    Task {
                        await clearAllCache()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes stored API response cache files only. Backend settings stay unchanged.")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Choose a section to configure Dragon without changing how the existing data sources work.")
                .font(.footnote)
                .foregroundStyle(.gray)
        }
    }

    private var dragonConnectionPage: some View {
        DragonSettingsPageScaffold(
            title: "Dragon Connection",
            subtitle: "Legacy backend controls live here for developer testing. Dragon iOS stays independent by default."
        ) {
            DragonSettingsSectionCard(
                title: "Developer / Legacy Backend",
                subtitle: "Native Movies no longer depends on this automatically."
            ) {
                connectionSettingsContent
            }
        }
    }

    private var moviesPage: some View {
        DragonSettingsPageScaffold(
            title: "Movies",
            subtitle: "Native Movies uses Notion plus local cache fallback."
        ) {
            DragonSettingsSectionCard(
                title: "Movies Status",
                subtitle: "Configuration stays in the current defaults key and secure token storage."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    DragonSettingsKeyValueRow(label: "Notion configuration", value: notionConfigurationLabel)
                    DragonSettingsKeyValueRow(label: "Connection test", value: notionConnectionLabel)
                    DragonSettingsKeyValueRow(
                        label: "Movies cache",
                        value: "\(movieCacheCount) cached response\(movieCacheCount == 1 ? "" : "s")"
                    )
                }
            }

            DragonSettingsSectionCard(
                title: "Movies in Notion",
                subtitle: "Configure a Notion token and source ID to enable native Movies loading."
            ) {
                notionSettingsContent
            }
        }
    }

    private var articlesPage: some View {
        DragonSettingsPageScaffold(
            title: "Articles",
            subtitle: "RSS source organization, cache state, and refresh controls for native Articles."
        ) {
            DragonSettingsSectionCard(
                title: editingArticleSourceID == nil ? "Add RSS Source" : "Edit RSS Source",
                subtitle: "Manage native RSS sources stored on this device for the Articles tab."
            ) {
                articleSourceEditorContent
            }

            DragonSettingsSectionCard(
                title: "Source List",
                subtitle: "Active RSS sources are fetched by the native iOS Articles loader."
            ) {
                articleSourceListContent
            }

            DragonSettingsSectionCard(
                title: "Articles Cache",
                subtitle: "Inspect article-specific cache state and local refresh tools."
            ) {
                articlesSettingsContent
            }
        }
    }

    private var developerPage: some View {
        DragonSettingsPageScaffold(
            title: "Developer",
            subtitle: "App-wide cache tools and legacy developer controls."
        ) {
            DragonSettingsSectionCard(
                title: "Developer Structure",
                subtitle: "Section-specific tools now live inside their matching Settings pages."
            ) {
                developerStructureContent
            }

            DragonSettingsSectionCard(
                title: "Cache Overview",
                subtitle: "Global cache tools for development and troubleshooting."
            ) {
                developerCacheContent
            }
        }
    }

    private var youTubePage: some View {
        DragonSettingsPageScaffold(
            title: "YouTube",
            subtitle: "Native playlist loading uses the YouTube Data API plus local on-device cache."
        ) {
            DragonSettingsSectionCard(
                title: "YouTube Status",
                subtitle: "This playlist is stored locally and loaded without a PythonAnywhere fallback."
            ) {
                youTubeStatusContent
            }

            DragonSettingsSectionCard(
                title: "Playlist Source",
                subtitle: "Paste a normal YouTube playlist link or a safe raw playlist ID."
            ) {
                youTubeSettingsContent
            }
        }
    }

    private var tvPage: some View {
        DragonSettingsPageScaffold(
            title: "TV / IPTV",
            subtitle: "TV diagnostics, source tools, and future user-facing settings live together here."
        ) {
            DragonSettingsSectionCard(
                title: "IPTV Status",
                subtitle: "Catalog totals, last saved health snapshot, and manual health actions."
            ) {
                DragonTVSettingsStatusPanel()
            }

            DragonSettingsSectionCard(
                title: "Source Tools",
                subtitle: "Editable playlist sources, cache tools, and favorites actions."
            ) {
                NavigationLink {
                    DragonTVAdminView()
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Open TV / IPTV Source Tools")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text("Manage playlist sources and advanced diagnostics from the same TV / IPTV settings section.")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DragonTheme.red.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            DragonSettingsSectionCard(
                title: "User Settings",
                subtitle: "Reserved for future TV / IPTV user-facing configuration."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    DragonSettingsStatusBadge(text: "Coming later", color: .gray)

                    Text("When TV / IPTV settings expand, they will live here in the same section as the current diagnostics and source tools.")
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Text("User-facing TV / IPTV settings can grow here without putting the status board back on the main browsing screen.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private func placeholderPage(title: String, subtitle: String, message: String) -> some View {
        DragonSettingsPageScaffold(title: title, subtitle: subtitle) {
            DragonSettingsSectionCard(
                title: "Not Configured Yet",
                subtitle: "This section is intentionally a placeholder for future work."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    DragonSettingsStatusBadge(text: "Coming later", color: .gray)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Text("No data source or storage behavior was added or modified for this section.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var connectionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use this only for legacy or developer flows. Dragon iOS native sections should continue working without a PythonAnywhere dependency.")
                .font(.caption)
                .foregroundStyle(.gray)

            DragonSettingsEditableField(
                placeholder: "http://127.0.0.1:5000",
                text: $backendURLDraft
            )
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

            Text(statusLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(statusColor)

            Text("Current backend URL: \(settingsStore.backendURL)")
                .font(.caption)
                .foregroundStyle(.gray)
                .lineLimit(2)

            Text(lastCheckedLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            if let detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button("Save") {
                    saveBackendURL()
                }
                .buttonStyle(DragonFilledButtonStyle())

                Button {
                    checkBackend()
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isChecking ? "Testing..." : "Test Connection")
                    }
                }
                .buttonStyle(DragonFilledButtonStyle())
                .disabled(isChecking)
            }

            Button("Reset backend URL") {
                resetBackendURL()
            }
            .buttonStyle(DragonOutlineButtonStyle())
        }
    }

    private var notionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Without this, Movies uses cached data only and shows a configuration prompt.")
                .font(.caption)
                .foregroundStyle(.gray)

            Text("Notion source ID")
                .font(.caption)
                .foregroundStyle(.gray)

            DragonSettingsEditableField(
                placeholder: "Database or data source ID",
                text: $notionSourceIDDraft
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

            Text("Notion token")
                .font(.caption)
                .foregroundStyle(.gray)

            SecureField(
                notionSettingsStore.hasToken ? "Stored securely. Paste a new token to replace it." : "secret_xxx",
                text: $notionTokenDraft
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.footnote.monospaced())
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(notionConfigurationLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(notionConfigurationColor)

            Text(notionConnectionLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(notionConnectionColor)

            Text(notionLastCheckedLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            if let notionDetailText {
                Text(notionDetailText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button("Save Notion Settings") {
                    saveNotionSettings()
                }
                .buttonStyle(DragonFilledButtonStyle())

                Button {
                    checkNotionConnection()
                } label: {
                    HStack {
                        if isCheckingNotion {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isCheckingNotion ? "Testing..." : "Test Notion")
                    }
                }
                .buttonStyle(DragonFilledButtonStyle())
                .disabled(isCheckingNotion)
            }

            Button("Clear Notion token") {
                clearNotionToken()
            }
            .buttonStyle(DragonOutlineButtonStyle())
        }
    }

    private var articleSourceEditorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Source Name (Optional)")
                    .font(.caption)
                    .foregroundStyle(.gray)

                DragonSettingsEditableField(
                    placeholder: "Example: BBC World",
                    text: $articleSourceNameDraft
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("RSS Feed URL")
                    .font(.caption)
                    .foregroundStyle(.gray)

                DragonSettingsEditableField(
                    placeholder: "https://example.com/feed.xml",
                    text: $articleSourceURLDraft
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Text("Only http:// and https:// RSS feed URLs are accepted. Source names are optional and default to the feed host.")
                .font(.caption)
                .foregroundStyle(.gray)

            if let articleSourceErrorText, !articleSourceErrorText.isEmpty {
                Text(articleSourceErrorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            if let articleSourceStatusText, !articleSourceStatusText.isEmpty {
                Text(articleSourceStatusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button(articleSourcePrimaryActionTitle) {
                    saveArticleSource()
                }
                .buttonStyle(DragonFilledButtonStyle())

                Button(editingArticleSourceID == nil ? "Clear" : "Cancel Edit") {
                    resetArticleSourceEditor()
                }
                .buttonStyle(DragonOutlineButtonStyle())
            }
        }
    }

    private var youTubeStatusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            DragonSettingsKeyValueRow(label: "Configuration", value: youTubeConfigurationLabel)
            DragonSettingsKeyValueRow(label: "Playlist ID", value: youTubeStoredPlaylistID.isEmpty ? "Not saved" : youTubeStoredPlaylistID)
            DragonSettingsKeyValueRow(label: "API key", value: youTubeHasStoredOrDraftAPIKey ? "Stored securely" : "Missing")

            if !youTubeResolvedDisplayName.isEmpty {
                DragonSettingsKeyValueRow(label: "Display name", value: youTubeResolvedDisplayName)
            }

            Text("The YouTube tab uses the saved playlist ID and YouTube API key directly on-device, then keeps a local cache for offline-safe fallback.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private var youTubeSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use a normal playlist URL like https://www.youtube.com/playlist?list=PLAYLIST_ID or paste a safe raw playlist ID directly.")
                .font(.caption)
                .foregroundStyle(.gray)

            VStack(alignment: .leading, spacing: 8) {
                Text("Playlist URL or ID")
                    .font(.caption)
                    .foregroundStyle(.gray)

                DragonSettingsEditableField(
                    placeholder: "https://www.youtube.com/playlist?list=...",
                    text: $youTubePlaylistURLDraft
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name (Optional)")
                    .font(.caption)
                    .foregroundStyle(.gray)

                DragonSettingsEditableField(
                    placeholder: "Example: Dragon Watch Later",
                    text: $youTubeDisplayNameDraft
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("YouTube API Key")
                    .font(.caption)
                    .foregroundStyle(.gray)

                SecureField(
                    youTubeHasStoredAPIKey ? "Stored securely. Paste a new key to replace it." : "AIza...",
                    text: $youTubeAPIKeyDraft
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.footnote.monospaced())
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let detectedPlaylistID = youTubeDetectedPlaylistID {
                Text("Detected playlist ID: \(detectedPlaylistID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.gray)
                    .textSelection(.enabled)
            }

            Text(youTubeConfigurationLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(youTubeCardBadgeColor)

            if let youTubeSettingsErrorText, !youTubeSettingsErrorText.isEmpty {
                Text(youTubeSettingsErrorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
            }

            if let youTubeSettingsStatusText, !youTubeSettingsStatusText.isEmpty {
                Text(youTubeSettingsStatusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button("Save YouTube Settings") {
                    saveYouTubeSettings()
                }
                .buttonStyle(DragonFilledButtonStyle())

                Button("Clear YouTube Settings") {
                    clearYouTubeSettings()
                }
                .buttonStyle(DragonOutlineButtonStyle())
            }
        }
    }

    private var articleSourceListContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if articleSources.isEmpty {
                Text("No RSS sources saved yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Text("Add at least one RSS feed above to let Articles refresh natively on-device.")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else {
                ForEach(articleSources) { source in
                    DragonSettingsSourceRow(
                        source: source,
                        isActive: Binding(
                            get: { source.active },
                            set: { newValue in
                                updateArticleSource(source, isActive: newValue)
                            }
                        ),
                        onEdit: {
                            beginEditingArticleSource(source)
                        },
                        onDelete: {
                            deleteArticleSource(source)
                        }
                    )
                }
            }

            Text("Only active sources are loaded by Articles. Deleting a source removes it from future native refreshes but keeps any existing cached articles until cache is cleared.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private var articlesSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(articleCacheCount) cached article response\(articleCacheCount == 1 ? "" : "s")")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("\(activeArticleFeedCount) active RSS source\(activeArticleFeedCount == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedCacheSize)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("shared cache size")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }

            Text("Articles cache participates in the shared app response cache. Refreshing info does not trigger a new RSS sync.")
                .font(.caption)
                .foregroundStyle(.gray)

            if let cacheStatusText, !cacheStatusText.isEmpty {
                Text(cacheStatusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button("Clear Articles Cache") {
                    Task {
                        await clearCache(for: .articles)
                    }
                }
                .buttonStyle(DragonOutlineButtonStyle())

                Button {
                    Task {
                        await refreshCacheInfo()
                    }
                } label: {
                    HStack {
                        if isRefreshingCacheInfo {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isRefreshingCacheInfo ? "Refreshing..." : "Refresh cache info")
                    }
                }
                .buttonStyle(DragonFilledButtonStyle())
                .disabled(isRefreshingCacheInfo)
            }
        }
    }

    private var developerStructureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dragon no longer keeps a separate admin category tree here.")
                .font(.subheadline)
                .foregroundStyle(.white)

            Text("Use each Settings section directly. Example: TV / IPTV diagnostics and source editing now open from Settings > TV / IPTV.")
                .font(.caption)
                .foregroundStyle(.gray)

            Text("Developer keeps only app-wide tools that do not belong to one content section.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private var developerCacheContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalCacheCount) total cached response\(totalCacheCount == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.gray)

                    Text("Articles cache: \(articleCacheCount) • Movies cache: \(movieCacheCount)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()

                Text(formattedCacheSize)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            if let cacheStatusText, !cacheStatusText.isEmpty {
                Text(cacheStatusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button("Clear Movies Cache") {
                    Task {
                        await clearCache(for: .movies)
                    }
                }
                .buttonStyle(DragonOutlineButtonStyle())

                Button {
                    Task {
                        await refreshCacheInfo()
                    }
                } label: {
                    HStack {
                        if isRefreshingCacheInfo {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isRefreshingCacheInfo ? "Refreshing..." : "Refresh cache info")
                    }
                }
                .buttonStyle(DragonFilledButtonStyle())
                .disabled(isRefreshingCacheInfo)
            }

            Button("Clear All Cache") {
                showClearCacheConfirmation = true
            }
            .buttonStyle(DragonFilledButtonStyle())
            .disabled(isRefreshingCacheInfo)
        }
    }

    private func loadInitialState() async {
        backendURLDraft = settingsStore.backendURL
        notionSourceIDDraft = notionSettingsStore.moviesSourceIdentifier
        articleSources = articlesSourceStore.loadSources()
        refreshYouTubeSettingsState()
        await refreshCacheInfo()
    }

    private func saveBackendURL() {
        guard let normalized = settingsStore.saveBackendURL(backendURLDraft) else {
            connectionState = .invalidURL
            return
        }

        backendURLDraft = normalized
        connectionState = .notTested
        lastCheckedAt = nil
    }

    private func saveNotionSettings() {
        notionSettingsStore.saveMoviesSourceIdentifier(notionSourceIDDraft)
        notionSourceIDDraft = notionSettingsStore.moviesSourceIdentifier

        let trimmedTokenDraft = notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTokenDraft.isEmpty {
            do {
                try notionSettingsStore.saveToken(trimmedTokenDraft)
                notionTokenDraft = ""
            } catch {
                notionConnectionState = .failed(error.localizedDescription)
                return
            }
        }

        notionSettingsStore.postMoviesConfigurationDidChange()
        notionConnectionState = .notTested
        notionLastCheckedAt = nil
    }

    private func clearNotionToken() {
        do {
            try notionSettingsStore.clearToken()
            notionTokenDraft = ""
            notionSettingsStore.postMoviesConfigurationDidChange()
            notionConnectionState = .notTested
            notionLastCheckedAt = nil
        } catch {
            notionConnectionState = .failed(error.localizedDescription)
        }
    }

    private func saveYouTubeSettings() {
        youTubeSettingsErrorText = nil
        youTubeSettingsStatusText = nil

        do {
            let configuration = try youTubeSettingsStore.saveConfiguration(
                playlistValue: youTubePlaylistURLDraft,
                displayName: youTubeDisplayNameDraft,
                apiKey: youTubeAPIKeyDraft
            )
            youTubePlaylistURLDraft = configuration.playlistURL
            youTubeDisplayNameDraft = configuration.displayName
            youTubeStoredPlaylistID = configuration.playlistID
            youTubeHasStoredAPIKey = configuration.hasAPIKey
            youTubeAPIKeyDraft = ""
            youTubeSettingsStatusText = "YouTube playlist settings saved."
        } catch {
            youTubeSettingsErrorText = error.localizedDescription
        }
    }

    private func clearYouTubeSettings() {
        youTubeSettingsErrorText = nil
        youTubeSettingsStatusText = nil

        do {
            try youTubeSettingsStore.clearConfiguration()
            refreshYouTubeSettingsState()
            youTubeSettingsStatusText = "YouTube playlist settings cleared."
        } catch {
            youTubeSettingsErrorText = error.localizedDescription
        }
    }

    private func refreshYouTubeSettingsState() {
        youTubePlaylistURLDraft = youTubeSettingsStore.playlistURL
        youTubeDisplayNameDraft = youTubeSettingsStore.displayName
        youTubeStoredPlaylistID = youTubeSettingsStore.playlistID
        youTubeHasStoredAPIKey = youTubeSettingsStore.hasAPIKey
        youTubeAPIKeyDraft = ""
    }

    private func saveArticleSource() {
        articleSourceErrorText = nil
        articleSourceStatusText = nil

        let existingSource = editingArticleSourceID.flatMap { sourceID in
            articleSources.first(where: { $0.id == sourceID })
        }

        do {
            let source = try articlesSourceStore.makeSource(
                id: existingSource?.id ?? "rss-\(UUID().uuidString.lowercased())",
                name: articleSourceNameDraft,
                feedURL: articleSourceURLDraft,
                active: existingSource?.active ?? true,
                language: existingSource?.language,
                category: existingSource?.category,
                excludingSourceID: existingSource?.id
            )
            try articlesSourceStore.save(source)

            articleSources = articlesSourceStore.loadSources()
            articleSourceStatusText = existingSource == nil ? "RSS source added." : "RSS source saved."
            resetArticleSourceEditor(keepStatus: true)
        } catch {
            articleSourceErrorText = error.localizedDescription
        }
    }

    private func beginEditingArticleSource(_ source: DragonRSSSourceDescriptor) {
        editingArticleSourceID = source.id
        articleSourceNameDraft = source.name
        articleSourceURLDraft = source.feedURL
        articleSourceErrorText = nil
        articleSourceStatusText = nil
    }

    private func updateArticleSource(_ source: DragonRSSSourceDescriptor, isActive: Bool) {
        articleSourceErrorText = nil
        articleSourceStatusText = nil

        do {
            try articlesSourceStore.save(source.updating(active: isActive))
            articleSources = articlesSourceStore.loadSources()
            articleSourceStatusText = isActive ? "RSS source activated." : "RSS source deactivated."
        } catch {
            articleSourceErrorText = "Could not update RSS source."
        }
    }

    private func deleteArticleSource(_ source: DragonRSSSourceDescriptor) {
        articleSourceErrorText = nil
        articleSourceStatusText = nil

        do {
            try articlesSourceStore.deleteSource(id: source.id)
            articleSources = articlesSourceStore.loadSources()
            if editingArticleSourceID == source.id {
                resetArticleSourceEditor(keepStatus: true)
            }
            articleSourceStatusText = "RSS source removed."
        } catch {
            articleSourceErrorText = "Could not remove RSS source."
        }
    }

    private func resetArticleSourceEditor(keepStatus: Bool = false) {
        editingArticleSourceID = nil
        articleSourceNameDraft = ""
        articleSourceURLDraft = ""
        articleSourceErrorText = nil

        if !keepStatus {
            articleSourceStatusText = nil
        }
    }

    private func resetBackendURL() {
        backendURLDraft = settingsStore.resetToLocalBackendURL()
        connectionState = .notTested
        lastCheckedAt = nil
    }

    @MainActor
    private func refreshCacheInfo() async {
        isRefreshingCacheInfo = true
        cacheStatusText = nil

        do {
            let articles = try await responseCache.cacheItemCount(for: .articles)
            let movies = try await responseCache.cacheItemCount(for: .movies)
            let count = try await responseCache.cacheItemCount()
            let sizeBytes = try await responseCache.cacheSizeBytes()

            articleCacheCount = articles
            movieCacheCount = movies
            totalCacheCount = count
            cacheSizeBytes = sizeBytes
            cacheStatusText = nil
            isRefreshingCacheInfo = false
        } catch {
            cacheStatusText = "Could not load cache info."
            isRefreshingCacheInfo = false
        }
    }

    @MainActor
    private func clearCache(for domain: DragonResponseCacheDomain) async {
        isRefreshingCacheInfo = true
        cacheStatusText = nil

        do {
            try await responseCache.clear(domain: domain)
            articleCacheCount = (try? await responseCache.cacheItemCount(for: .articles)) ?? 0
            movieCacheCount = (try? await responseCache.cacheItemCount(for: .movies)) ?? 0
            totalCacheCount = (try? await responseCache.cacheItemCount()) ?? 0
            cacheSizeBytes = (try? await responseCache.cacheSizeBytes()) ?? 0
            cacheStatusText = "\(domain.rawValue.capitalized) cache cleared."
            isRefreshingCacheInfo = false
        } catch {
            cacheStatusText = "Could not clear \(domain.rawValue) cache."
            isRefreshingCacheInfo = false
        }
    }

    @MainActor
    private func clearAllCache() async {
        isRefreshingCacheInfo = true
        cacheStatusText = nil

        do {
            try await responseCache.clearAll()
            articleCacheCount = (try? await responseCache.cacheItemCount(for: .articles)) ?? 0
            movieCacheCount = (try? await responseCache.cacheItemCount(for: .movies)) ?? 0
            totalCacheCount = (try? await responseCache.cacheItemCount()) ?? 0
            cacheSizeBytes = (try? await responseCache.cacheSizeBytes()) ?? 0
            cacheStatusText = "Local cache cleared."
            isRefreshingCacheInfo = false
        } catch {
            cacheStatusText = "Could not clear local cache."
            isRefreshingCacheInfo = false
        }
    }

    private var backendCardBadgeText: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .failed:
            return "Check failed"
        case .invalidURL:
            return "Invalid URL"
        case .notTested:
            return "Legacy"
        }
    }

    private var backendCardBadgeColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .failed, .invalidURL:
            return DragonTheme.red
        case .notTested:
            return .gray
        }
    }

    private var articlesCardBadgeText: String {
        if activeArticleFeedCount > 0 {
            return "\(activeArticleFeedCount) sources"
        }

        return "No sources"
    }

    private var articlesCardBadgeColor: Color {
        activeArticleFeedCount > 0 ? .green : DragonTheme.red
    }

    private var youTubeCardBadgeText: String {
        if !youTubeStoredPlaylistID.isEmpty && youTubeHasStoredOrDraftAPIKey {
            return "Configured"
        }

        if !youTubeStoredPlaylistID.isEmpty {
            return "API key missing"
        }

        return "Not configured"
    }

    private var youTubeCardBadgeColor: Color {
        if !youTubeStoredPlaylistID.isEmpty && youTubeHasStoredOrDraftAPIKey {
            return .green
        }

        if !youTubeStoredPlaylistID.isEmpty {
            return DragonTheme.red
        }

        return .gray
    }

    private var developerCardBadgeText: String {
        if totalCacheCount > 0 {
            return "\(totalCacheCount) cached"
        }

        return "Diagnostics"
    }

    private var developerCardBadgeColor: Color {
        totalCacheCount > 0 ? DragonTheme.red : .gray
    }

    private var articleSourcePrimaryActionTitle: String {
        editingArticleSourceID == nil ? "Add Source" : "Save Source"
    }

    private var activeArticleFeedCount: Int {
        articleSources.filter(\.active).count
    }

    private var statusLabel: String {
        switch connectionState {
        case .notTested:
            return "Not tested"
        case .connected:
            return "Connected"
        case .failed:
            return "Check failed"
        case .invalidURL:
            return "Invalid URL"
        }
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .failed, .invalidURL:
            return DragonTheme.red
        case .notTested:
            return .gray
        }
    }

    private var detailText: String? {
        switch connectionState {
        case .notTested:
            return "No API response yet"
        case .connected:
            return "Backend is reachable."
        case .failed(let message):
            return message
        case .invalidURL:
            return "Enter a valid http:// or https:// URL"
        }
    }

    private var notionConfigurationLabel: String {
        if notionHasSourceIdentifier && notionHasStoredOrDraftToken {
            return "Notion configured"
        }

        if notionHasSourceIdentifier || notionHasStoredOrDraftToken {
            return "Notion configuration incomplete"
        }

        return "Notion not configured"
    }

    private var notionConfigurationColor: Color {
        if notionHasSourceIdentifier && notionHasStoredOrDraftToken {
            return .green
        }

        if notionHasSourceIdentifier || notionHasStoredOrDraftToken {
            return DragonTheme.red
        }

        return .gray
    }

    private var youTubeConfigurationLabel: String {
        if !youTubeStoredPlaylistID.isEmpty && youTubeHasStoredOrDraftAPIKey {
            return "YouTube playlist configured"
        }

        if !youTubeStoredPlaylistID.isEmpty {
            return "Playlist saved, API key missing"
        }

        if !youTubePlaylistURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Ready to save playlist"
        }

        return "YouTube playlist not configured"
    }

    private var notionConnectionLabel: String {
        switch notionConnectionState {
        case .notTested:
            return "Not tested"
        case .connected:
            return "Connected"
        case .failed:
            return "Check failed"
        }
    }

    private var notionConnectionColor: Color {
        switch notionConnectionState {
        case .connected:
            return .green
        case .failed:
            return DragonTheme.red
        case .notTested:
            return .gray
        }
    }

    private var notionDetailText: String? {
        switch notionConnectionState {
        case .notTested:
            if notionSettingsStore.hasToken {
                return "Token is stored securely in Keychain. Leave the token field blank to keep it unchanged."
            }
            return "Paste a Notion integration token and a source ID to enable native Movies loading."
        case .connected(let sourceLabel):
            return "Connected to \(sourceLabel)."
        case .failed(let message):
            return message
        }
    }

    private func checkBackend() {
        guard normalizeDragonBackendBaseURL(backendURLDraft) != nil else {
            connectionState = .invalidURL
            lastCheckedAt = Date()
            return
        }

        isChecking = true
        connectionState = .notTested

        Task {
            defer { isChecking = false }

            let normalizedDraft = normalizeDragonBackendBaseURL(backendURLDraft) ?? settingsStore.backendURL
            let workingClient = DragonAPIClient(baseURLProvider: { normalizedDraft })

            switch await workingClient.testBackendConnection() {
            case .success:
                connectionState = .connected
                lastCheckedAt = Date()
            case .failure(let error):
                connectionState = .failed(dragonUserFacingMessage(for: error))
                lastCheckedAt = Date()
            }
        }
    }

    private func checkNotionConnection() {
        isCheckingNotion = true
        notionConnectionState = .notTested

        Task {
            defer { isCheckingNotion = false }

            let trimmedSourceID = notionSourceIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceOverride = trimmedSourceID.isEmpty ? nil : trimmedSourceID
            let trimmedToken = notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenOverride = trimmedToken.isEmpty ? nil : trimmedToken

            switch await notionMoviesDataSource.testConnection(
                sourceIdentifierOverride: sourceOverride,
                tokenOverride: tokenOverride
            ) {
            case .success(let sourceLabel):
                notionConnectionState = .connected(sourceLabel)
                notionLastCheckedAt = Date()
            case .failure(let error):
                notionConnectionState = .failed(dragonUserFacingMessage(for: error))
                notionLastCheckedAt = Date()
            }
        }
    }

    private var lastCheckedLabel: String {
        guard let lastCheckedAt else {
            return "Last checked: Never"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return "Last checked: \(formatter.string(from: lastCheckedAt))"
    }

    private var notionLastCheckedLabel: String {
        guard let notionLastCheckedAt else {
            return "Last checked: Never"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return "Last checked: \(formatter.string(from: notionLastCheckedAt))"
    }

    private var formattedCacheSize: String {
        Self.byteCountFormatter.string(fromByteCount: cacheSizeBytes)
    }

    private var notionHasSourceIdentifier: Bool {
        !notionSourceIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var notionHasStoredOrDraftToken: Bool {
        !notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || notionSettingsStore.hasToken
    }

    private var youTubeHasStoredOrDraftAPIKey: Bool {
        !youTubeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || youTubeHasStoredAPIKey
    }

    private var youTubeDetectedPlaylistID: String? {
        DragonYouTubePlaylistIdentifier.extract(from: youTubePlaylistURLDraft)
    }

    private var youTubeResolvedDisplayName: String {
        let trimmedName = youTubeDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return youTubeSettingsStore.displayName
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter
    }()
}

private struct DragonSettingsPageScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    content
                }
                .padding(24)
                .padding(.bottom, 24)
            }
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
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }
}

private struct DragonSettingsNavigationCard: View {
    let title: String
    let message: String
    let badgeText: String?
    let badgeColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let badgeText, !badgeText.isEmpty {
                        DragonSettingsStatusBadge(text: badgeText, color: badgeColor)
                    }
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(DragonTheme.red.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct DragonSettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DragonSettingsStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.22))
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct DragonSettingsEditableField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.footnote.monospaced())
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DragonSettingsDisabledField: View {
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: .constant(""))
            .disabled(true)
            .font(.footnote.monospaced())
            .foregroundStyle(.gray)
            .padding(12)
            .background(Color.black.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DragonTheme.red.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DragonSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)

            Spacer()

            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DragonSettingsSourceRow: View {
    let source: DragonRSSSourceDescriptor
    @Binding var isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(source.normalizedName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        DragonSettingsStatusBadge(
                            text: isActive ? "Active" : "Inactive",
                            color: isActive ? .green : .gray
                        )
                    }

                    Text(source.normalizedFeedURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.gray)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .tint(DragonTheme.red)
            }

            HStack(spacing: 10) {
                if let language = source.language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.gray)
                }

                if let category = source.category, !category.isEmpty {
                    Text(category.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Button("Edit", action: onEdit)
                    .buttonStyle(DragonMiniOutlineButtonStyle())

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(DragonMiniOutlineButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DragonMiniOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.18))
            .foregroundStyle(.white)
            .overlay(
                Capsule()
                    .stroke(DragonTheme.red.opacity(configuration.isPressed ? 0.6 : 1), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct DragonFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(DragonTheme.red.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DragonOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(DragonTheme.card)
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DragonTheme.red.opacity(configuration.isPressed ? 0.6 : 1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
