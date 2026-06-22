import Foundation

enum DragonArticlesSourceStoreError: LocalizedError {
    case emptyURL
    case invalidURL
    case duplicateURL

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Enter an RSS feed URL."
        case .invalidURL:
            return "Enter a valid http:// or https:// RSS feed URL."
        case .duplicateURL:
            return "This RSS source is already configured."
        }
    }
}

struct DragonArticlesSourceStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let sourcesKey = "dragon.articles.rssSources"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSources() -> [DragonRSSSourceDescriptor] {
        guard let data = defaults.data(forKey: sourcesKey) else {
            return DragonArticlesFeedRegistry.v1Feeds
        }

        guard let sources = try? decoder.decode([DragonRSSSourceDescriptor].self, from: data) else {
            return DragonArticlesFeedRegistry.v1Feeds
        }

        return sources.map(Self.normalizedSource)
    }

    func save(_ source: DragonRSSSourceDescriptor) throws {
        var sources = loadSources()
        let normalized = Self.normalizedSource(source)

        if let index = sources.firstIndex(where: { $0.id == normalized.id }) {
            sources[index] = normalized
        } else {
            sources.append(normalized)
        }

        try persist(sources)
    }

    func deleteSource(id: String) throws {
        let filteredSources = loadSources().filter { $0.id != id }
        try persist(filteredSources)
    }

    func validate(
        name: String,
        feedURL: String,
        excludingSourceID: String? = nil
    ) throws -> ValidatedSourceInput {
        let normalizedURLString = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURLString.isEmpty else {
            throw DragonArticlesSourceStoreError.emptyURL
        }

        guard let resolvedURL = URL(string: normalizedURLString),
              let scheme = resolvedURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              resolvedURL.host?.dragonTrimmedOrNil != nil else {
            throw DragonArticlesSourceStoreError.invalidURL
        }

        let duplicateSources = loadSources().contains { source in
            guard source.id != excludingSourceID else {
                return false
            }

            return source.normalizedFeedURL.caseInsensitiveCompare(resolvedURL.absoluteString) == .orderedSame
        }
        guard !duplicateSources else {
            throw DragonArticlesSourceStoreError.duplicateURL
        }

        return ValidatedSourceInput(
            name: Self.resolvedName(from: name, fallbackURL: resolvedURL),
            feedURL: resolvedURL.absoluteString
        )
    }

    func makeSource(
        id: String = "rss-\(UUID().uuidString.lowercased())",
        name: String,
        feedURL: String,
        active: Bool = true,
        language: String? = nil,
        category: String? = nil,
        excludingSourceID: String? = nil
    ) throws -> DragonRSSSourceDescriptor {
        let validated = try validate(
            name: name,
            feedURL: feedURL,
            excludingSourceID: excludingSourceID
        )

        return DragonRSSSourceDescriptor(
            id: id,
            name: validated.name,
            feedURL: validated.feedURL,
            language: language?.dragonTrimmedOrNil,
            category: category?.dragonTrimmedOrNil,
            active: active
        )
    }

    private func persist(_ sources: [DragonRSSSourceDescriptor]) throws {
        let data = try encoder.encode(sources.map(Self.normalizedSource))
        defaults.set(data, forKey: sourcesKey)
    }

    private static func normalizedSource(_ source: DragonRSSSourceDescriptor) -> DragonRSSSourceDescriptor {
        let normalizedURL = source.normalizedFeedURL
        let resolvedURL = URL(string: normalizedURL)

        return DragonRSSSourceDescriptor(
            id: source.id,
            name: resolvedName(from: source.name, fallbackURL: resolvedURL),
            feedURL: normalizedURL,
            language: source.language?.dragonTrimmedOrNil,
            category: source.category?.dragonTrimmedOrNil,
            active: source.active
        )
    }

    private static func resolvedName(from rawValue: String, fallbackURL: URL?) -> String {
        if let trimmedName = rawValue.dragonTrimmedOrNil {
            return trimmedName
        }

        let host = fallbackURL?.host?.dragonTrimmedOrNil ?? ""
        let normalizedHost = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        return normalizedHost.isEmpty ? "RSS Source" : normalizedHost
    }
}

struct ValidatedSourceInput {
    let name: String
    let feedURL: String
}
