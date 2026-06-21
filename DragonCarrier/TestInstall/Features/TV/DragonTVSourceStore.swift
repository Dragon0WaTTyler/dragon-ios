import Foundation

struct DragonTVSource: Identifiable, Codable, Hashable {
    let id: String
    var label: String
    var urlString: String
    var isEnabled: Bool
    let isBuiltIn: Bool

    var normalizedLabel: String {
        label.dragonTrimmedOrNil ?? fallbackLabel
    }

    var normalizedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedURL: URL? {
        URL(string: normalizedURLString)
    }

    func updating(
        label: String? = nil,
        urlString: String? = nil,
        isEnabled: Bool? = nil
    ) -> DragonTVSource {
        DragonTVSource(
            id: id,
            label: label ?? self.label,
            urlString: urlString ?? self.urlString,
            isEnabled: isEnabled ?? self.isEnabled,
            isBuiltIn: isBuiltIn
        )
    }

    private var fallbackLabel: String {
        resolvedURL?.host?.dragonTrimmedOrNil ?? "TV Source"
    }
}

private struct DragonTVBuiltInSourceOverrideRecord: Codable, Hashable {
    let id: String
    let label: String?
    let urlString: String?
    let isEnabled: Bool?
}

struct DragonTVSourceStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let builtInOverridesKey = "dragon.tv.sourceOverrides"
    private let customSourcesKey = "dragon.tv.customSources"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSources() -> [DragonTVSource] {
        let builtInOverrides = loadBuiltInOverrides()
        let builtInSources = IPTVPlaylistSource.defaultSources.map { source in
            let override = builtInOverrides[source.id]
            return DragonTVSource(
                id: source.id,
                label: override?.label?.dragonTrimmedOrNil ?? source.label,
                urlString: override?.urlString?.dragonTrimmedOrNil ?? source.url.absoluteString,
                isEnabled: override?.isEnabled ?? true,
                isBuiltIn: true
            )
        }

        return builtInSources + loadCustomSources()
    }

    func enabledPlaylistSources() -> [IPTVPlaylistSource] {
        loadSources().compactMap { source in
            guard source.isEnabled,
                  let url = URL(string: source.normalizedURLString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }

            return IPTVPlaylistSource(
                id: source.id,
                label: source.normalizedLabel,
                urlString: url.absoluteString
            )
        }
    }

    func sourceLookupByURLString() -> [String: DragonTVSource] {
        Dictionary(
            uniqueKeysWithValues: loadSources().compactMap { source in
                guard let url = URL(string: source.normalizedURLString) else {
                    return nil
                }

                return (url.absoluteString, source)
            }
        )
    }

    func save(_ source: DragonTVSource) throws {
        if source.isBuiltIn {
            try saveBuiltInSource(source)
        } else {
            try saveCustomSource(source)
        }
    }

    func makeCustomSource(label: String, urlString: String, isEnabled: Bool) -> DragonTVSource {
        DragonTVSource(
            id: "custom-\(UUID().uuidString.lowercased())",
            label: label,
            urlString: urlString,
            isEnabled: isEnabled,
            isBuiltIn: false
        )
    }

    func deleteCustomSource(id: String) throws {
        let filteredSources = loadCustomSources().filter { $0.id != id }
        try persistCustomSources(filteredSources)
    }

    func resetToDefaults() throws {
        defaults.removeObject(forKey: builtInOverridesKey)
        defaults.removeObject(forKey: customSourcesKey)
    }

    private func saveBuiltInSource(_ source: DragonTVSource) throws {
        guard let defaultSource = IPTVPlaylistSource.defaultSources.first(where: { $0.id == source.id }) else {
            return
        }

        var overrides = loadBuiltInOverrides()
        let normalizedSource = DragonTVSource(
            id: source.id,
            label: source.normalizedLabel,
            urlString: source.normalizedURLString,
            isEnabled: source.isEnabled,
            isBuiltIn: true
        )

        let labelOverride = normalizedSource.label == defaultSource.label ? nil : normalizedSource.label
        let urlOverride = normalizedSource.urlString == defaultSource.url.absoluteString ? nil : normalizedSource.urlString
        let enabledOverride = normalizedSource.isEnabled ? nil : false

        if labelOverride == nil, urlOverride == nil, enabledOverride == nil {
            overrides.removeValue(forKey: source.id)
        } else {
            overrides[source.id] = DragonTVBuiltInSourceOverrideRecord(
                id: source.id,
                label: labelOverride,
                urlString: urlOverride,
                isEnabled: enabledOverride
            )
        }

        try persistBuiltInOverrides(overrides)
    }

    private func saveCustomSource(_ source: DragonTVSource) throws {
        var customSources = loadCustomSources()
        let normalizedSource = DragonTVSource(
            id: source.id,
            label: source.normalizedLabel,
            urlString: source.normalizedURLString,
            isEnabled: source.isEnabled,
            isBuiltIn: false
        )

        if let index = customSources.firstIndex(where: { $0.id == source.id }) {
            customSources[index] = normalizedSource
        } else {
            customSources.append(normalizedSource)
        }

        try persistCustomSources(customSources)
    }

    private func loadBuiltInOverrides() -> [String: DragonTVBuiltInSourceOverrideRecord] {
        guard let data = defaults.data(forKey: builtInOverridesKey),
              let overrides = try? decoder.decode([DragonTVBuiltInSourceOverrideRecord].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: overrides.map { ($0.id, $0) })
    }

    private func loadCustomSources() -> [DragonTVSource] {
        guard let data = defaults.data(forKey: customSourcesKey),
              let sources = try? decoder.decode([DragonTVSource].self, from: data) else {
            return []
        }

        return sources
    }

    private func persistBuiltInOverrides(_ overrides: [String: DragonTVBuiltInSourceOverrideRecord]) throws {
        let data = try encoder.encode(Array(overrides.values).sorted { $0.id < $1.id })
        defaults.set(data, forKey: builtInOverridesKey)
    }

    private func persistCustomSources(_ sources: [DragonTVSource]) throws {
        let data = try encoder.encode(sources)
        defaults.set(data, forKey: customSourcesKey)
    }
}
