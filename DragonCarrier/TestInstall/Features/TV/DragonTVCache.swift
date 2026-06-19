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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(responseCache: DragonResponseCache = .shared) {
        self.responseCache = responseCache

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadCachedReport() async -> DragonTVCachedChannelsResult? {
        guard let cachedResponse = await responseCache.load(for: cacheURL),
              let report = try? decoder.decode(IPTVLoadReport.self, from: cachedResponse.data) else {
            return nil
        }

        return DragonTVCachedChannelsResult(report: report, cachedAt: cachedResponse.metadata.cachedAt)
    }

    func save(_ report: IPTVLoadReport) async -> DragonTVRefreshResult {
        let refreshedAt = Date()

        if let data = try? encoder.encode(report) {
            await responseCache.save(data: data, for: cacheURL)
        }

        return DragonTVRefreshResult(report: report, refreshedAt: refreshedAt)
    }

    private var cacheURL: URL {
        var components = URLComponents()
        components.scheme = "dragon-cache"
        components.host = "tv"
        components.path = "/working-channels-v1"
        return components.url ?? URL(string: "dragon-cache://tv/working-channels-v1")!
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
}
