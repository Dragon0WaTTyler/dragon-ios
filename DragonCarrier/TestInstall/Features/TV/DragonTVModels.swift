import Foundation

struct IPTVPlaylistSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let url: URL

    init(id: String, label: String, urlString: String) {
        self.id = id
        self.label = label
        self.url = URL(string: urlString)!
    }

    static let defaultSources: [IPTVPlaylistSource] = [
        IPTVPlaylistSource(id: "language-ara", label: "Arabic", urlString: "https://iptv-org.github.io/iptv/languages/ara.m3u"),
        IPTVPlaylistSource(id: "language-eng", label: "English", urlString: "https://iptv-org.github.io/iptv/languages/eng.m3u"),
        IPTVPlaylistSource(id: "category-news", label: "News", urlString: "https://iptv-org.github.io/iptv/categories/news.m3u"),
        IPTVPlaylistSource(id: "category-documentary", label: "Documentary", urlString: "https://iptv-org.github.io/iptv/categories/documentary.m3u"),
        IPTVPlaylistSource(id: "streams-ma", label: "Morocco Sports", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/ma.m3u"),
        IPTVPlaylistSource(id: "streams-qa", label: "Qatar / Al Kass / Al Jazeera", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/qa.m3u"),
        IPTVPlaylistSource(id: "streams-sa", label: "Saudi Sports / News", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/sa.m3u"),
        IPTVPlaylistSource(id: "streams-ae", label: "UAE Sports / News", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/ae.m3u"),
        IPTVPlaylistSource(id: "streams-bh", label: "Bahrain Sports", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/bh.m3u"),
        IPTVPlaylistSource(id: "streams-kw", label: "Kuwait Sports", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/kw.m3u"),
        IPTVPlaylistSource(id: "streams-om", label: "Oman Sports", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/om.m3u"),
        IPTVPlaylistSource(id: "streams-iq", label: "Iraq Sports", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/iq.m3u"),
        IPTVPlaylistSource(id: "streams-uk-bbc", label: "BBC UK", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/uk_bbc.m3u"),
        IPTVPlaylistSource(id: "streams-fr", label: "France", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/fr.m3u"),
        IPTVPlaylistSource(id: "streams-de", label: "Germany / DW", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/de.m3u"),
        IPTVPlaylistSource(id: "streams-us-samsung", label: "Samsung TV Plus US", urlString: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/us_samsung.m3u")
    ]

    static let lookupByURLString: [String: IPTVPlaylistSource] = {
        Dictionary(uniqueKeysWithValues: defaultSources.map { ($0.url.absoluteString, $0) })
    }()

    static func effectiveLookupByURLString(
        sourceStore: DragonTVSourceStore = DragonTVSourceStore()
    ) -> [String: IPTVPlaylistSource] {
        Dictionary(
            uniqueKeysWithValues: sourceStore.enabledPlaylistSources().map { ($0.url.absoluteString, $0) }
        )
    }

    static func mergedWithCustomSources(_ customSources: [URL]) -> [IPTVPlaylistSource] {
        var merged = defaultSources
        var seenURLs = Set(defaultSources.map(\.url.absoluteString))

        for (index, url) in customSources.enumerated() {
            guard seenURLs.insert(url.absoluteString).inserted else {
                continue
            }

            let inferredLabel = url.host?.dragonTrimmedOrNil ?? "Custom Source \(index + 1)"
            merged.append(
                IPTVPlaylistSource(
                    id: "custom-\(index + 1)",
                    label: inferredLabel,
                    urlString: url.absoluteString
                )
            )
        }

        return merged
    }
}

struct IPTVChannel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let tvgId: String?
    let group: String?
    let category: String?
    let metadataLabels: [String]?
    let logo: URL?
    let httpUserAgent: String?
    let sourceURLs: [URL]
    var isFavorite: Bool

    var hostLabel: String {
        if let host = url.host, !host.isEmpty {
            return host
        }

        return url.absoluteString
    }

    var displayGroupLabel: String? {
        effectiveMetadataLabels.lazy
            .compactMap(Self.normalizedGroupLabel(_:))
            .first
    }

    var canonicalCategoryTags: Set<DragonTVCategoryTag> {
        DragonTVCategoryNormalizer.tags(for: self)
    }

    var effectiveMetadataLabels: [String] {
        let labels = metadataLabels?.compactMap(\.dragonTrimmedOrNil) ?? []
        if !labels.isEmpty {
            return labels.dragonOrderedUnique()
        }

        return [group, category]
            .compactMap { $0?.dragonTrimmedOrNil }
            .dragonOrderedUnique()
    }

    func merged(with incoming: IPTVChannel) -> IPTVChannel {
        let mergedMetadataLabels = (effectiveMetadataLabels + incoming.effectiveMetadataLabels).dragonOrderedUnique()
        return IPTVChannel(
            id: id,
            name: name,
            url: url,
            tvgId: tvgId ?? incoming.tvgId,
            group: group ?? incoming.group,
            category: category ?? incoming.category,
            metadataLabels: mergedMetadataLabels.isEmpty ? nil : mergedMetadataLabels,
            logo: logo ?? incoming.logo,
            httpUserAgent: httpUserAgent ?? incoming.httpUserAgent,
            sourceURLs: Array(NSOrderedSet(array: sourceURLs + incoming.sourceURLs)) as? [URL] ?? sourceURLs,
            isFavorite: isFavorite || incoming.isFavorite
        )
    }

    func applyingFavorite(_ isFavorite: Bool) -> IPTVChannel {
        var updated = self
        updated.isFavorite = isFavorite
        return updated
    }

    func sourceLabels(
        using lookup: [String: IPTVPlaylistSource] = IPTVPlaylistSource.effectiveLookupByURLString()
    ) -> [String] {
        var labels: [String] = []

        for sourceURL in sourceURLs {
            if let label = lookup[sourceURL.absoluteString]?.label, !labels.contains(label) {
                labels.append(label)
            }
        }

        return labels
    }

    var sourceSummary: String {
        let labels = sourceLabels()
        if !labels.isEmpty {
            return labels.joined(separator: " • ")
        }

        return hostLabel
    }

    private static func normalizedGroupLabel(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.dragonTrimmedOrNil else {
            return nil
        }

        let normalized = rawValue
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "arab", "arabic", "العربية":
            return "Arabic"
        default:
            return rawValue
        }
    }
}

struct IPTVSourceFailure: Identifiable, Codable, Hashable, Sendable {
    let sourceID: String
    let label: String
    let url: URL
    let message: String

    var id: String {
        sourceID
    }
}

struct IPTVSourceDiagnostic: Identifiable, Codable, Hashable, Sendable {
    let sourceID: String
    let label: String
    let url: URL
    let downloadSucceeded: Bool
    let parsedChannelCount: Int
    let validChannelCount: Int?
    let interestingMatchCount: Int
    let errorMessage: String?

    var id: String {
        sourceID
    }
}

enum IPTVInterestingChannelStatus: String, Codable, Hashable, Sendable {
    case validatedWorking
    case parsedButFailedValidation
}

struct IPTVInterestingChannelDiagnostic: Identifiable, Codable, Hashable, Sendable {
    let channelID: String
    let name: String
    let streamURL: URL
    let group: String?
    let logoURL: URL?
    let httpUserAgent: String?
    let matchedKeywords: [String]
    let sourceLabels: [String]
    let sourceURLs: [URL]
    let status: IPTVInterestingChannelStatus
    let statusCode: Int?
    let errorMessage: String?

    var id: String {
        channelID
    }
}

struct IPTVHealthSnapshot: Codable, Sendable {
    let checkedChannelCount: Int
    let workingChannelCount: Int
    let failedChannelCount: Int
    let sourceDiagnostics: [IPTVSourceDiagnostic]
    let lastCheckedAt: Date
}

struct IPTVLoadReport: Codable, Sendable {
    let rawChannelCount: Int
    let dedupedChannelCount: Int
    let sourceFailures: [IPTVSourceFailure]
    let sourceDiagnostics: [IPTVSourceDiagnostic]
    let interestingChannelDiagnostics: [IPTVInterestingChannelDiagnostic]
    let channels: [IPTVChannel]
}

enum DragonTVFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case arabic
    case sports
    case movies
    case news
    case docs
    case kids
    case music
    case general
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
        case .arabic:
            return "Arabic"
        case .sports:
            return "Sports"
        case .movies:
            return "Movies"
        case .news:
            return "News"
        case .docs:
            return "Docs"
        case .kids:
            return "Kids"
        case .music:
            return "Music"
        case .general:
            return "General"
        case .other:
            return "Other"
        }
    }

    func matches(_ channel: IPTVChannel) -> Bool {
        switch self {
        case .all:
            return true
        case .favorites:
            return channel.isFavorite
        default:
            guard let categoryTag else {
                return false
            }

            return channel.canonicalCategoryTags.contains(categoryTag)
        }
    }

    private var categoryTag: DragonTVCategoryTag? {
        switch self {
        case .all, .favorites:
            return nil
        case .arabic:
            return .arabic
        case .sports:
            return .sports
        case .movies:
            return .movies
        case .news:
            return .news
        case .docs:
            return .docs
        case .kids:
            return .kids
        case .music:
            return .music
        case .general:
            return .general
        case .other:
            return .other
        }
    }
}

enum DragonTVCategoryTag: String, CaseIterable, Sendable {
    case arabic
    case sports
    case movies
    case news
    case docs
    case kids
    case music
    case general
    case other
}

private enum DragonTVCategoryNormalizer {
    static func tags(for channel: IPTVChannel) -> Set<DragonTVCategoryTag> {
        let metadataLabels = channel.effectiveMetadataLabels
        if !metadataLabels.isEmpty {
            let metadataTags = tags(in: metadataLabels)
            return metadataTags.isEmpty ? [.other] : metadataTags
        }

        let nameTags = tags(in: [channel.name])
        return nameTags.isEmpty ? [.other] : nameTags
    }

    private static func tags(in rawValues: [String]) -> Set<DragonTVCategoryTag> {
        var tags: Set<DragonTVCategoryTag> = []

        for rawValue in rawValues {
            let normalizedValue = normalize(rawValue)
            guard !normalizedValue.isEmpty else {
                continue
            }

            let tokenSet = Set(tokens(in: normalizedValue))

            if matchesArabic(normalizedValue, tokenSet: tokenSet) {
                tags.insert(.arabic)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["sport", "sports", "football", "soccer", "basketball", "baseball", "cricket", "tennis", "golf", "boxing", "wrestling", "mma", "motorsport", "racing", "espn", "eurosport"],
                phrases: ["bein sports", "sky sports", "fox sports", "nbc sports", "nfl network", "nba tv", "mlb network", "nhl network"]
            ) {
                tags.insert(.sports)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["movie", "movies", "cinema", "film", "films", "cinemax"],
                phrases: ["box office", "movie channel", "film channel"]
            ) {
                tags.insert(.movies)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["news", "newsroom", "newshour", "cnn", "cnbc", "msnbc", "euronews"],
                phrases: ["breaking news", "world news", "news channel", "al jazeera news", "france 24", "sky news", "bbc news", "fox news", "dw news"]
            ) {
                tags.insert(.news)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["documentary", "documentaries", "docs", "docu"],
                phrases: ["doc channel", "documentary channel"]
            ) {
                tags.insert(.docs)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["kids", "kid", "children", "childrens", "cartoon", "cartoons", "toons", "junior", "youth"],
                phrases: ["cartoon network", "disney junior", "nick jr", "kids channel", "children channel", "family kids"]
            ) {
                tags.insert(.kids)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["music", "karaoke", "concert", "mtv", "vh1", "vevo"],
                phrases: ["music channel", "live music"]
            ) {
                tags.insert(.music)
            }

            if matchesAny(
                normalizedValue,
                tokenSet: tokenSet,
                keywords: ["general", "entertainment", "variety"],
                phrases: ["general entertainment", "entertainment channel"]
            ) {
                tags.insert(.general)
            }
        }

        return tags
    }

    private static func matchesArabic(_ normalizedValue: String, tokenSet: Set<String>) -> Bool {
        if tokenSet.contains("arab") || tokenSet.contains("arabic") || normalizedValue.contains("العربية") {
            return true
        }

        return false
    }

    private static func matchesAny(
        _ normalizedValue: String,
        tokenSet: Set<String>,
        keywords: Set<String>,
        phrases: [String]
    ) -> Bool {
        if tokenSet.isDisjoint(with: keywords) == false {
            return true
        }

        return phrases.contains(where: normalizedValue.contains(_:))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(in value: String) -> [String] {
        value.split { character in
            !character.isLetter && !character.isNumber
        }
        .map(String.init)
    }
}

extension String {
    var dragonTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == String {
    func dragonOrderedUnique() -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for value in self {
            guard seen.insert(value).inserted else {
                continue
            }

            ordered.append(value)
        }

        return ordered
    }
}
