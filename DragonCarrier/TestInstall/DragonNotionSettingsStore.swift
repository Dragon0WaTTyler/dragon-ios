import Foundation
import Security

let dragonNotionMoviesSourceIdentifierDefaultsKey = "dragon.movies.notion.sourceIdentifier"

struct DragonNotionConfiguration {
    let sourceIdentifier: String
    let token: String

    var isConfigured: Bool {
        !sourceIdentifier.isEmpty && !token.isEmpty
    }
}

enum DragonKeychainStoreError: LocalizedError {
    case unexpectedPasswordData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedPasswordData:
            return "Stored secure value could not be read."
        case .unhandledStatus(let status):
            return "Secure storage failed (\(status))."
        }
    }
}

struct DragonKeychainStore {
    func string(for service: String, account: String) throws -> String? {
        let query = baseQuery(service: service, account: account).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue as Any
        ]) { _, newValue in
            newValue
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw DragonKeychainStoreError.unexpectedPasswordData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw DragonKeychainStoreError.unhandledStatus(status)
        }
    }

    func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)
        let attributesToUpdate = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var creationQuery = query
            creationQuery[kSecValueData as String] = data

            let addStatus = SecItemAdd(creationQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw DragonKeychainStoreError.unhandledStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw DragonKeychainStoreError.unhandledStatus(updateStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DragonKeychainStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct DragonNotionSettingsStore {
    private let defaults: UserDefaults
    private let keychainStore: DragonKeychainStore
    private let keychainService = "Dragon.Notion.Movies"
    private let keychainAccount = "integration-token"

    init(
        defaults: UserDefaults = .standard,
        keychainStore: DragonKeychainStore = DragonKeychainStore()
    ) {
        self.defaults = defaults
        self.keychainStore = keychainStore
    }

    var moviesSourceIdentifier: String {
        sanitized(defaults.string(forKey: dragonNotionMoviesSourceIdentifierDefaultsKey) ?? "")
    }

    var hasToken: Bool {
        (try? keychainStore.string(for: keychainService, account: keychainAccount))?.isEmpty == false
    }

    func loadToken() throws -> String? {
        try keychainStore.string(for: keychainService, account: keychainAccount)
    }

    func loadConfiguration(
        sourceIdentifierOverride: String? = nil,
        tokenOverride: String? = nil
    ) throws -> DragonNotionConfiguration {
        let sourceIdentifier = sanitized(sourceIdentifierOverride ?? moviesSourceIdentifier)
        let storedToken = try loadToken() ?? ""
        let resolvedToken = tokenOverride ?? storedToken
        let token = sanitized(resolvedToken)
        return DragonNotionConfiguration(sourceIdentifier: sourceIdentifier, token: token)
    }

    func saveMoviesSourceIdentifier(_ rawValue: String) {
        let sanitizedValue = sanitized(rawValue)
        if sanitizedValue.isEmpty {
            defaults.removeObject(forKey: dragonNotionMoviesSourceIdentifierDefaultsKey)
        } else {
            defaults.set(sanitizedValue, forKey: dragonNotionMoviesSourceIdentifierDefaultsKey)
        }
    }

    func saveToken(_ rawValue: String) throws {
        let sanitizedValue = sanitized(rawValue)
        guard !sanitizedValue.isEmpty else {
            return
        }

        try keychainStore.save(sanitizedValue, service: keychainService, account: keychainAccount)
    }

    func clearToken() throws {
        try keychainStore.delete(service: keychainService, account: keychainAccount)
    }

    private func sanitized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
