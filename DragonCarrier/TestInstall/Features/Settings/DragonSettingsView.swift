import SwiftUI

struct DragonSettingsView: View {
    @State private var backendURLDraft = DragonBackendSettingsStore().backendURL
    @State private var connectionState: DragonBackendConnectionState = .notTested
    @State private var isChecking = false
    @State private var lastCheckedAt: Date?
    private let settingsStore = DragonBackendSettingsStore()

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text("Dragon connection")
                    .font(.headline)
                    .foregroundStyle(.gray)

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

                Spacer()
            }
            .padding(24)
            .task {
                backendURLDraft = settingsStore.backendURL
            }
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
