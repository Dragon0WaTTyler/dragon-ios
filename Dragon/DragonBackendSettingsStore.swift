import Foundation

enum DragonBackendConnectionState: Equatable {
    case notTested
    case connected
    case failed(String)
    case invalidURL
}

struct DragonBackendSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var backendURL: String {
        let storedValue = defaults.string(forKey: dragonBackendBaseURLDefaultsKey) ?? ""
        return normalizeDragonBackendBaseURL(storedValue) ?? dragonDefaultBackendBaseURL
    }

    @discardableResult
    func saveBackendURL(_ rawValue: String) -> String? {
        guard let normalized = normalizeDragonBackendBaseURL(rawValue) else {
            return nil
        }

        defaults.set(normalized, forKey: dragonBackendBaseURLDefaultsKey)
        return normalized
    }

    func resetToLocalBackendURL() -> String {
        defaults.set(dragonDefaultBackendBaseURL, forKey: dragonBackendBaseURLDefaultsKey)
        return dragonDefaultBackendBaseURL
    }
}
