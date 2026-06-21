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

    func merged(with incoming: IPTVChannel) -> IPTVChannel {
        IPTVChannel(
            id: id,
            name: name,
            url: url,
            tvgId: tvgId ?? incoming.tvgId,
            group: group ?? incoming.group,
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
    let validChannelCount: Int
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

struct IPTVLoadReport: Codable, Sendable {
    let rawChannelCount: Int
    let dedupedChannelCount: Int
    let validChannelCount: Int
    let sourceFailures: [IPTVSourceFailure]
    let sourceDiagnostics: [IPTVSourceDiagnostic]
    let interestingChannelDiagnostics: [IPTVInterestingChannelDiagnostic]
    let channels: [IPTVChannel]
}

enum DragonTVFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case arabic
    case english
    case news
    case sports
    case movies
    case documentary
    case us
    case uk
    case arab

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
        case .english:
            return "English"
        case .news:
            return "News"
        case .sports:
            return "Sports"
        case .movies:
            return "Movies"
        case .documentary:
            return "Documentary"
        case .us:
            return "US"
        case .uk:
            return "UK"
        case .arab:
            return "Arab"
        }
    }

    func matches(_ channel: IPTVChannel) -> Bool {
        switch self {
        case .all:
            return true
        case .favorites:
            return channel.isFavorite
        default:
            let supportedSourceIDs = sourceIDs
            let sourceLookup = IPTVPlaylistSource.effectiveLookupByURLString()
            return channel.sourceURLs.contains { sourceURL in
                guard let source = sourceLookup[sourceURL.absoluteString] else {
                    return false
                }

                return supportedSourceIDs.contains(source.id)
            }
        }
    }

    private var sourceIDs: Set<String> {
        switch self {
        case .all, .favorites:
            return []
        case .arabic:
            return [
                "language-ara",
                "streams-ma",
                "streams-qa",
                "streams-sa",
                "streams-ae",
                "streams-bh",
                "streams-kw",
                "streams-om",
                "streams-iq"
            ]
        case .english:
            return [
                "language-eng",
                "streams-uk-bbc",
                "streams-us-samsung"
            ]
        case .news:
            return [
                "category-news",
                "streams-qa",
                "streams-sa",
                "streams-ae",
                "streams-uk-bbc",
                "streams-fr",
                "streams-de",
                "streams-us-samsung"
            ]
        case .sports:
            return [
                "streams-ma",
                "streams-qa",
                "streams-sa",
                "streams-ae",
                "streams-bh",
                "streams-kw",
                "streams-om",
                "streams-iq"
            ]
        case .movies:
            return ["category-movies"]
        case .documentary:
            return [
                "category-documentary",
                "streams-fr",
                "streams-de",
                "streams-us-samsung"
            ]
        case .us:
            return ["streams-us-samsung"]
        case .uk:
            return ["streams-uk-bbc"]
        case .arab:
            return [
                "language-ara",
                "streams-ma",
                "streams-qa",
                "streams-sa",
                "streams-ae",
                "streams-bh",
                "streams-kw",
                "streams-om",
                "streams-iq"
            ]
        }
    }
}

extension String {
    var dragonTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
