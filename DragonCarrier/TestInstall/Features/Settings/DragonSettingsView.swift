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
    @State private var articleCacheCount: Int = 0
    @State private var movieCacheCount: Int = 0
    @State private var totalCacheCount: Int = 0
    @State private var cacheSizeBytes: Int64 = 0
    @State private var isRefreshingCacheInfo = false
    @State private var cacheStatusText: String?
    @State private var showClearCacheConfirmation = false
    private let settingsStore = DragonBackendSettingsStore()
    private let notionSettingsStore = DragonNotionSettingsStore()
    private let notionMoviesDataSource = DragonNotionMoviesDataSource()
    private let responseCache = DragonResponseCache.shared

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Settings")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)

                        sectionCard(
                            title: "Dragon Connection",
                            subtitle: "Configure the backend URL and test the current server."
                        ) {
                            connectionCardContent
                        }

                        sectionCard(
                            title: "Movies in Notion",
                            subtitle: "When configured, Movies loads from Notion first."
                        ) {
                            notionCardContent
                        }

                        sectionCard(
                            title: "Articles / Cache",
                            subtitle: "Inspect and clear stored responses used by the app."
                        ) {
                            cacheCardContent
                        }

                        sectionCard(
                            title: "Developer Debug",
                            subtitle: "Local section controls, diagnostics, and admin tools."
                        ) {
                            developerDebugCardContent
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 24)
                }
            }
            .task {
                backendURLDraft = settingsStore.backendURL
                notionSourceIDDraft = notionSettingsStore.moviesSourceIdentifier
                await refreshCacheInfo()
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

    private var connectionCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("http://127.0.0.1:5000", text: $backendURLDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .font(.footnote.monospaced())
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

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

    private var cacheCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(totalCacheCount) total cached response\(totalCacheCount == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }

                Spacer()

                Text(formattedCacheSize)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("Articles cache: \(articleCacheCount) • Movies cache: \(movieCacheCount)")
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

                Button("Clear Movies Cache") {
                    Task {
                        await clearCache(for: .movies)
                    }
                }
                .buttonStyle(DragonOutlineButtonStyle())
            }

            HStack(spacing: 12) {
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

                Button {
                    showClearCacheConfirmation = true
                } label: {
                    Text("Clear All Cache")
                }
                .buttonStyle(DragonFilledButtonStyle())
                .disabled(isRefreshingCacheInfo)
            }
        }
    }

    private var notionCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When configured, Movies loads from Notion first. If Notion is not configured, Dragon keeps using the legacy API.")
                .font(.caption)
                .foregroundStyle(.gray)

            Text("Notion source ID")
                .font(.caption)
                .foregroundStyle(.gray)

            TextField("Database or data source ID", text: $notionSourceIDDraft)
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

    private var developerDebugCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                DragonAdminView()
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Manage Dragon")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Local section controls, TV cache actions, and diagnostics.")
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
                .background(DragonTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(DragonTheme.red.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            content()
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter
    }()
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
