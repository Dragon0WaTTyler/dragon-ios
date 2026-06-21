import CryptoKit
import Foundation

struct DragonTVCachedChannelsResult: Sendable {
    let report: IPTVLoadReport
    let cachedAt: Date
}

struct DragonTVRefreshResult: Sendable {
    let report: IPTVLoadReport
    let refreshedAt: Date
}

actor DragonTVCacheStore {
    private let responseCache: DragonResponseCache
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        responseCache: DragonResponseCache = .shared,
        fileManager: FileManager = .default
    ) {
        self.responseCache = responseCache
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedReport() async throws -> DragonTVCachedChannelsResult? {
        let recordURL = try cacheRecordURL()
        guard fileManager.fileExists(atPath: recordURL.path) else {
            return nil
        }

        let recordData = try Data(contentsOf: recordURL)
        let record = try decoder.decode(DragonCachedResponseRecord.self, from: recordData)
        guard let payloadData = Data(base64Encoded: record.payloadBase64) else {
            throw CocoaError(.coderReadCorrupt)
        }

        let report = try decoder.decode(IPTVLoadReport.self, from: payloadData)
        return DragonTVCachedChannelsResult(report: report, cachedAt: record.metadata.cachedAt)
    }

    func save(_ report: IPTVLoadReport) async -> DragonTVRefreshResult {
        let refreshedAt = Date()

        if let data = try? encoder.encode(report) {
            await responseCache.save(data: data, for: cacheURL)
        }

        return DragonTVRefreshResult(report: report, refreshedAt: refreshedAt)
    }

    func cachedChannelCount() async throws -> Int {
        try await loadCachedReport()?.report.channels.count ?? 0
    }

    func lastUpdatedAt() async throws -> Date? {
        try await loadCachedReport()?.cachedAt
    }

    func clear() async throws {
        let recordURL = try cacheRecordURL()
        guard fileManager.fileExists(atPath: recordURL.path) else {
            return
        }

        try fileManager.removeItem(at: recordURL)
    }

    private var cacheURL: URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "tv"
        components.path = "/working-channels-v1"
        return components.url ?? URL(string: "dragon-cache://tv/working-channels-v1")!
    }

    private func cacheRecordURL() throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("DragonResponseCache", isDirectory: true)

        let digest = SHA256.hash(data: Data(cacheURL.absoluteString.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return baseDirectory.appendingPathComponent("\(hash).json", isDirectory: false)
    }
}

struct DragonTVFavoritesStore {
    private let defaults: UserDefaults
    private let favoritesKey = "dragon.tv.favoriteChannelIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFavoriteIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: favoritesKey) ?? [])
    }

    func favoriteCount() -> Int {
        loadFavoriteIDs().count
    }

    @discardableResult
    func updateFavorite(id: String, isFavorite: Bool) -> Set<String> {
        var favorites = loadFavoriteIDs()

        if isFavorite {
            favorites.insert(id)
        } else {
            favorites.remove(id)
        }

        defaults.set(Array(favorites).sorted(), forKey: favoritesKey)
        return favorites
    }

    func clearFavorites() {
        defaults.removeObject(forKey: favoritesKey)
    }
}
