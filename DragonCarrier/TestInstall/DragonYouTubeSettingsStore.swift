import Foundation
import Security

let dragonYouTubePlaylistURLDefaultsKey = "dragon.youtube.playlistURL"
let dragonYouTubePlaylistIDDefaultsKey = "dragon.youtube.playlistID"
let dragonYouTubePlaylistDisplayNameDefaultsKey = "dragon.youtube.displayName"
let dragonYouTubeConfigurationDidChangeNotification = Notification.Name("dragonYouTubeConfigurationDidChange")

struct DragonYouTubePlaylistConfiguration: Equatable {
    let playlistURL: String
    let playlistID: String
    let displayName: String
    let apiKey: String

    var hasPlaylist: Bool {
        !playlistID.isEmpty
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    var isConfigured: Bool {
        hasPlaylist && hasAPIKey
    }

    var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return "YouTube Playlist"
    }
}

enum DragonYouTubeSettingsStoreError: LocalizedError {
    case emptyPlaylistInput
    case invalidPlaylistURL
    case invalidPlaylistID

    var errorDescription: String? {
        switch self {
        case .emptyPlaylistInput:
            return "Paste a YouTube playlist URL or playlist ID."
        case .invalidPlaylistURL:
            return "Invalid playlist URL. Paste a normal YouTube playlist link."
        case .invalidPlaylistID:
            return "Could not extract a valid playlist ID from that value."
        }
    }
}

enum DragonYouTubePlaylistIdentifier {
    static func extract(from rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if isLikelyPlaylistID(trimmedValue) {
            return trimmedValue
        }

        let candidateValue: String
        if trimmedValue.contains("://") {
            candidateValue = trimmedValue
        } else {
            candidateValue = "https://\(trimmedValue)"
        }

        guard let components = URLComponents(string: candidateValue) else {
            return nil
        }

        let host = components.host?.lowercased() ?? ""
        let isYouTubeHost = host.contains("youtube.com") || host.contains("youtu.be")
        guard isYouTubeHost else {
            return nil
        }

        if let playlistID = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("list") == .orderedSame })?.value,
           isLikelyPlaylistID(playlistID) {
            return playlistID
        }

        return nil
    }

    static func isLikelyPlaylistID(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.count >= 10 && trimmedValue.count <= 200 else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return trimmedValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }
}

struct DragonYouTubeSettingsStore {
    private let defaults: UserDefaults
    private let keychainStore: DragonKeychainStore
    private let keychainService = "Dragon.YouTube"
    private let keychainAccount = "playlist-api-key"

    init(
        defaults: UserDefaults = .standard,
        keychainStore: DragonKeychainStore = DragonKeychainStore()
    ) {
        self.defaults = defaults
        self.keychainStore = keychainStore
    }

    var playlistURL: String {
        sanitized(defaults.string(forKey: dragonYouTubePlaylistURLDefaultsKey) ?? "")
    }

    var playlistID: String {
        sanitized(defaults.string(forKey: dragonYouTubePlaylistIDDefaultsKey) ?? "")
    }

    var displayName: String {
        sanitized(defaults.string(forKey: dragonYouTubePlaylistDisplayNameDefaultsKey) ?? "")
    }

    var hasAPIKey: Bool {
        (try? keychainStore.string(for: keychainService, account: keychainAccount))?.isEmpty == false
    }

    func loadAPIKey() throws -> String? {
        try keychainStore.string(for: keychainService, account: keychainAccount)
    }

    func loadConfiguration(
        playlistValueOverride: String? = nil,
        displayNameOverride: String? = nil,
        apiKeyOverride: String? = nil
    ) throws -> DragonYouTubePlaylistConfiguration {
        let rawPlaylistValue = sanitized(playlistValueOverride ?? playlistURL)
        let extractedPlaylistID = DragonYouTubePlaylistIdentifier.extract(from: rawPlaylistValue) ?? playlistID
        let storedAPIKey = try loadAPIKey() ?? ""
        let resolvedAPIKey = sanitized(apiKeyOverride ?? storedAPIKey)

        return DragonYouTubePlaylistConfiguration(
            playlistURL: rawPlaylistValue,
            playlistID: sanitized(extractedPlaylistID),
            displayName: sanitized(displayNameOverride ?? displayName),
            apiKey: resolvedAPIKey
        )
    }

    @discardableResult
    func saveConfiguration(
        playlistValue: String,
        displayName: String,
        apiKey: String?
    ) throws -> DragonYouTubePlaylistConfiguration {
        let sanitizedPlaylistValue = sanitized(playlistValue)
        guard !sanitizedPlaylistValue.isEmpty else {
            throw DragonYouTubeSettingsStoreError.emptyPlaylistInput
        }

        let extractedPlaylistID: String
        if let playlistID = DragonYouTubePlaylistIdentifier.extract(from: sanitizedPlaylistValue) {
            extractedPlaylistID = playlistID
        } else if sanitizedPlaylistValue.contains("youtube.com") || sanitizedPlaylistValue.contains("youtu.be") || sanitizedPlaylistValue.contains("playlist") || sanitizedPlaylistValue.contains("?") {
            throw DragonYouTubeSettingsStoreError.invalidPlaylistURL
        } else {
            throw DragonYouTubeSettingsStoreError.invalidPlaylistID
        }

        defaults.set(sanitizedPlaylistValue, forKey: dragonYouTubePlaylistURLDefaultsKey)
        defaults.set(extractedPlaylistID, forKey: dragonYouTubePlaylistIDDefaultsKey)

        let sanitizedDisplayName = sanitized(displayName)
        if sanitizedDisplayName.isEmpty {
            defaults.removeObject(forKey: dragonYouTubePlaylistDisplayNameDefaultsKey)
        } else {
            defaults.set(sanitizedDisplayName, forKey: dragonYouTubePlaylistDisplayNameDefaultsKey)
        }

        if let apiKey {
            let sanitizedAPIKey = sanitized(apiKey)
            if !sanitizedAPIKey.isEmpty {
                try keychainStore.save(sanitizedAPIKey, service: keychainService, account: keychainAccount)
            }
        }

        let configuration = try loadConfiguration(
            playlistValueOverride: sanitizedPlaylistValue,
            displayNameOverride: sanitizedDisplayName
        )
        postConfigurationDidChange()
        return configuration
    }

    func clearConfiguration() throws {
        defaults.removeObject(forKey: dragonYouTubePlaylistURLDefaultsKey)
        defaults.removeObject(forKey: dragonYouTubePlaylistIDDefaultsKey)
        defaults.removeObject(forKey: dragonYouTubePlaylistDisplayNameDefaultsKey)
        try keychainStore.delete(service: keychainService, account: keychainAccount)
        postConfigurationDidChange()
    }

    func postConfigurationDidChange() {
        NotificationCenter.default.post(name: dragonYouTubeConfigurationDidChangeNotification, object: nil)
    }

    private func sanitized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
