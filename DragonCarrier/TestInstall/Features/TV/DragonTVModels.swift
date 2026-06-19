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
        IPTVPlaylistSource(id: "category-sports", label: "Sports", urlString: "https://iptv-org.github.io/iptv/categories/sports.m3u"),
        IPTVPlaylistSource(id: "category-movies", label: "Movies", urlString: "https://iptv-org.github.io/iptv/categories/movies.m3u"),
        IPTVPlaylistSource(id: "category-documentary", label: "Documentary", urlString: "https://iptv-org.github.io/iptv/categories/documentary.m3u"),
        IPTVPlaylistSource(id: "country-us", label: "US", urlString: "https://iptv-org.github.io/iptv/countries/us.m3u"),
        IPTVPlaylistSource(id: "country-uk", label: "UK", urlString: "https://iptv-org.github.io/iptv/countries/uk.m3u"),
        IPTVPlaylistSource(id: "region-arab", label: "Arab", urlString: "https://iptv-org.github.io/iptv/regions/arab.m3u"),
        IPTVPlaylistSource(id: "index", label: "Index", urlString: "https://iptv-org.github.io/iptv/index.m3u"),
        IPTVPlaylistSource(id: "pastebin", label: "Pastebin", urlString: "https://pastebin.com/raw/qgCC2HTU"),
        IPTVPlaylistSource(id: "free-tv", label: "Free TV", urlString: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8")
    ]

    static let lookupByURLString: [String: IPTVPlaylistSource] = {
        Dictionary(uniqueKeysWithValues: defaultSources.map { ($0.url.absoluteString, $0) })
    }()
}

struct IPTVChannel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let tvgId: String?
    let group: String?
    let logo: URL?
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
            sourceURLs: Array(NSOrderedSet(array: sourceURLs + incoming.sourceURLs)) as? [URL] ?? sourceURLs,
            isFavorite: isFavorite || incoming.isFavorite
        )
    }

    func applyingFavorite(_ isFavorite: Bool) -> IPTVChannel {
        var updated = self
        updated.isFavorite = isFavorite
        return updated
    }

    func sourceLabels(using lookup: [String: IPTVPlaylistSource] = IPTVPlaylistSource.lookupByURLString) -> [String] {
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

struct IPTVLoadReport: Codable, Sendable {
    let rawChannelCount: Int
    let dedupedChannelCount: Int
    let validChannelCount: Int
    let sourceFailures: [IPTVSourceFailure]
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
            return channel.sourceURLs.contains { sourceURL in
                guard let source = IPTVPlaylistSource.lookupByURLString[sourceURL.absoluteString] else {
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
            return ["language-ara"]
        case .english:
            return ["language-eng"]
        case .news:
            return ["category-news"]
        case .sports:
            return ["category-sports"]
        case .movies:
            return ["category-movies"]
        case .documentary:
            return ["category-documentary"]
        case .us:
            return ["country-us"]
        case .uk:
            return ["country-uk"]
        case .arab:
            return ["region-arab"]
        }
    }
}

extension String {
    var dragonTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
