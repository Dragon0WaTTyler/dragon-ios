import SwiftUI

struct DragonSettingsView: View {
    @State private var backendURLDraft = DragonBackendSettingsStore().backendURL
    @State private var connectionState: DragonBackendConnectionState = .notTested
    @State private var isChecking = false
    @State private var lastCheckedAt: Date?
    @State private var articleCacheCount: Int = 0
    @State private var movieCacheCount: Int = 0
    @State private var totalCacheCount: Int = 0
    @State private var cacheSizeBytes: Int64 = 0
    @State private var isRefreshingCacheInfo = false
    @State private var cacheStatusText: String?
    @State private var showClearCacheConfirmation = false
    private let settingsStore = DragonBackendSettingsStore()
    private let responseCache = DragonResponseCache.shared

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Dragon connection")
                            .font(.headline)
                            .foregroundStyle(.gray)

                        backendCard

                        cacheCard

                        adminCard

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
                    .padding(24)
                    .padding(.bottom, 24)
                }
            }
            .task {
                backendURLDraft = settingsStore.backendURL
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

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend URL")
                .font(.caption)
                .foregroundStyle(.gray)

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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cache Debug")
                        .font(.headline)
                        .foregroundStyle(.white)

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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var adminCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Admin")
                .font(.headline)
                .foregroundStyle(.gray)

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

    private func saveBackendURL() {
        guard let normalized = settingsStore.saveBackendURL(backendURLDraft) else {
            connectionState = .invalidURL
            return
        }

        backendURLDraft = normalized
        connectionState = .notTested
        lastCheckedAt = nil
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

    private var formattedCacheSize: String {
        Self.byteCountFormatter.string(fromByteCount: cacheSizeBytes)
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
