import Foundation

struct DragonHealthResponse: Decodable {
    let api_version: String
    let ok: Bool
    let service: String
}

struct DragonHomeResponse: Codable {
    let app_name: String
    let api_version: String
    let ok: Bool
    let server_time: String
    let sections: [DragonSection]
    let service: String

    private enum CodingKeys: String, CodingKey {
        case app_name
        case api_version
        case ok
        case server_time
        case sections
        case service
    }

    init(app_name: String, api_version: String, ok: Bool, server_time: String, sections: [DragonSection], service: String) {
        self.app_name = app_name
        self.api_version = api_version
        self.ok = ok
        self.server_time = server_time
        self.sections = sections
        self.service = service
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.app_name = try container.decodeIfPresent(String.self, forKey: .app_name) ?? "Dragon"
        self.api_version = try container.decode(String.self, forKey: .api_version)
        self.ok = try container.decode(Bool.self, forKey: .ok)
        self.server_time = try container.decodeIfPresent(String.self, forKey: .server_time) ?? ""
        self.sections = try container.decode([DragonSection].self, forKey: .sections)
        self.service = try container.decode(String.self, forKey: .service)
    }
}

struct DragonSection: Codable, Identifiable {
    let api_path: String
    let key: String
    let label: String
    let status: String
    let count: Int?
    let href: String

    private enum CodingKeys: String, CodingKey {
        case api_path
        case key
        case label
        case status
        case count
        case href
    }

    init(api_path: String, key: String, label: String, status: String, count: Int?, href: String) {
        self.api_path = api_path
        self.key = key
        self.label = label
        self.status = status
        self.count = count
        self.href = href
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.label = try container.decode(String.self, forKey: .label)
        self.status = try container.decode(String.self, forKey: .status)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        let decodedHref = try container.decodeIfPresent(String.self, forKey: .href)
        let decodedAPIPath = try container.decodeIfPresent(String.self, forKey: .api_path)
        let fallbackPath = "/api/v1/\(key)"
        self.href = decodedHref ?? decodedAPIPath ?? fallbackPath
        self.api_path = decodedAPIPath ?? decodedHref ?? fallbackPath
    }

    var id: String {
        key
    }

    var displayCount: String {
        guard let count else {
            return "—"
        }

        return String(count)
    }

    var statusDisplayText: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct DragonArticlesResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonArticle]
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
    }

    init(api_version: String, ok: Bool, items: [DragonArticle], count: Int) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonArticle].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
            ?? items.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(api_version, forKey: .api_version)
        try container.encode(ok, forKey: .ok)
        try container.encode(items, forKey: .items)
        try container.encode(count, forKey: .count)
    }
}

struct DragonArticle: Codable, Identifiable {
    let id: String
    let title: String
    let source: String
    let url: String
    let published_at: String
    let saved_at: String
    let excerpt: String
    let status: String
    let read_state: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case source_name
        case url
        case published_at
        case saved_at
        case excerpt
        case summary
        case description
        case status
        case read_state
    }

    init(
        id: String,
        title: String,
        source: String,
        url: String,
        published_at: String,
        saved_at: String,
        excerpt: String,
        status: String = "",
        read_state: String = ""
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.url = url
        self.published_at = published_at
        self.saved_at = saved_at
        self.excerpt = excerpt
        self.status = status
        self.read_state = read_state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonArticle.decodeString(container, forKeys: [.id])
        self.title = DragonArticle.decodeString(container, forKeys: [.title], default: "Untitled article")
        self.source = DragonArticle.decodeString(container, forKeys: [.source, .source_name])
        self.url = DragonArticle.decodeString(container, forKeys: [.url])
        self.published_at = DragonArticle.decodeString(container, forKeys: [.published_at])
        self.saved_at = DragonArticle.decodeString(container, forKeys: [.saved_at])
        self.excerpt = DragonArticle.decodeString(container, forKeys: [.excerpt, .summary, .description])
        self.status = DragonArticle.decodeString(container, forKeys: [.status])
        self.read_state = DragonArticle.decodeString(container, forKeys: [.read_state])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(source, forKey: .source)
        try container.encode(url, forKey: .url)
        try container.encode(published_at, forKey: .published_at)
        try container.encode(saved_at, forKey: .saved_at)
        try container.encode(excerpt, forKey: .excerpt)
        try container.encode(status, forKey: .status)
        try container.encode(read_state, forKey: .read_state)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }
}

struct DragonBooksResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonBook]
    let count: Int
    let total: Int
    let limit: Int
    let offset: Int
    let has_more: Bool
    let next_offset: Int?

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
        case limit
        case offset
        case has_more
        case next_offset
    }

    init(
        api_version: String,
        ok: Bool,
        items: [DragonBook],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int = 0,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit ?? count
        self.offset = offset
        let resolvedHasMore = has_more ?? ((offset + count) < (total ?? count))
        self.has_more = resolvedHasMore
        self.next_offset = next_offset ?? (resolvedHasMore ? offset + count : nil)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonBook].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
            ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? count
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        let decodedHasMore = try container.decodeIfPresent(Bool.self, forKey: .has_more)
            ?? ((offset + count) < total)
        self.has_more = decodedHasMore
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
            ?? (decodedHasMore ? offset + count : nil)
    }
}

struct DragonBook: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let authors: [String]
    let cover: String
    let year: String
    let status: String
    let score: String
    let excerpt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case authors
        case cover
        case cover_url
        case status
        case year
        case score
        case excerpt
        case summary
    }

    init(
        id: String,
        title: String,
        author: String,
        authors: [String],
        cover: String,
        year: String,
        status: String,
        score: String,
        excerpt: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.authors = authors
        self.cover = cover
        self.year = year
        self.status = status
        self.score = score
        self.excerpt = excerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonBook.decodeString(container, keys: [.id])
        self.title = DragonBook.decodeString(container, keys: [.title], default: "Untitled book")
        self.author = DragonBook.decodeString(container, keys: [.author])
        self.authors = DragonBook.decodeStringArray(container, keys: [.authors])
        self.cover = DragonBook.decodeString(container, keys: [.cover, .cover_url])
        self.year = DragonBook.decodeString(container, keys: [.year])
        self.status = DragonBook.decodeString(container, keys: [.status])
        self.score = DragonBook.decodeString(container, keys: [.score])
        self.excerpt = DragonBook.decodeString(container, keys: [.excerpt, .summary])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(authors, forKey: .authors)
        try container.encode(cover, forKey: .cover)
        try container.encode(status, forKey: .status)
        try container.encode(year, forKey: .year)
        try container.encode(score, forKey: .score)
        try container.encode(excerpt, forKey: .excerpt)
    }

    var idValue: String {
        id
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }

    private static func decodeStringArray(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [String] {
        for key in keys {
            if let values = try? container.decode([String].self, forKey: key) {
                let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return [trimmed]
                }
            }
        }

        return []
    }
}

struct DragonMoviesResponse: Codable {
    let api_version: String
    let ok: Bool
    let items: [DragonMovie]
    let count: Int
}

struct DragonMovie: Codable, Identifiable {
    let id: String
    let title: String
    let year: String
    let poster: String
    let status: String
    let score: String
    let type: String
    let overview: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case poster
        case status
        case score
        case type
        case overview
    }

    init(id: String, title: String, year: String, poster: String, status: String, score: String, type: String, overview: String) {
        self.id = id
        self.title = title
        self.year = year
        self.poster = poster
        self.status = status
        self.score = score
        self.type = type
        self.overview = overview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonMovie.decodeString(container, forKey: .id)
        self.title = DragonMovie.decodeString(container, forKey: .title)
        self.year = DragonMovie.decodeString(container, forKey: .year)
        self.poster = DragonMovie.decodeString(container, forKey: .poster)
        self.status = DragonMovie.decodeString(container, forKey: .status)
        self.score = DragonMovie.decodeString(container, forKey: .score)
        self.type = DragonMovie.decodeString(container, forKey: .type)
        self.overview = DragonMovie.decodeString(container, forKey: .overview)
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? container.decode(Double.self, forKey: key) {
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        }

        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return ""
    }
}

struct DragonYouTubeVideosResponse: Codable {
    let api_version: String
    let ok: Bool
    let section: String
    let items: [DragonYouTubeVideo]
    let count: Int
    let total: Int
    let limit: Int
    let offset: Int
    let has_more: Bool
    let next_offset: Int?

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case section
        case items
        case count
        case total
        case limit
        case offset
        case has_more
        case next_offset
    }

    init(
        api_version: String,
        ok: Bool,
        section: String,
        items: [DragonYouTubeVideo],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int = 0,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.section = section
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit ?? count
        self.offset = offset
        let resolvedHasMore = has_more ?? ((offset + count) < (total ?? count))
        self.has_more = resolvedHasMore
        self.next_offset = next_offset ?? (resolvedHasMore ? offset + count : nil)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.section = DragonYouTubeVideosResponse.decodeString(container, keys: [.section])
        self.items = try container.decodeIfPresent([DragonYouTubeVideo].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? count
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        let decodedHasMore = try container.decodeIfPresent(Bool.self, forKey: .has_more)
            ?? ((offset + count) < total)
        self.has_more = decodedHasMore
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
            ?? (decodedHasMore ? offset + count : nil)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }

            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
        }

        return defaultValue
    }
}

typealias DragonYouTubeResponse = DragonYouTubeVideosResponse

struct DragonYouTubeSectionsResponse: Codable {
    let api_version: String
    let ok: Bool
    let sections: [DragonYouTubeSection]

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case sections
    }

    init(api_version: String, ok: Bool, sections: [DragonYouTubeSection]) {
        self.api_version = api_version
        self.ok = ok
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.sections = try container.decodeIfPresent([DragonYouTubeSection].self, forKey: .sections) ?? []
    }
}

struct DragonYouTubeSection: Codable, Identifiable {
    let key: String
    let label: String
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case count
    }

    init(key: String, label: String, count: Int) {
        self.key = key
        self.label = label
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = DragonYouTubeSection.decodeString(container, keys: [.key], default: "unknown")
        self.label = DragonYouTubeSection.decodeString(container, keys: [.label], default: key.isEmpty ? "Unknown section" : key)
        self.count = DragonYouTubeSection.decodeInt(container, keys: [.count])
    }

    var id: String {
        key.isEmpty ? label : key
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        default defaultValue: String = ""
    ) -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }
        }

        return defaultValue
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int(trimmed) {
                    return parsed
                }
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                return Int(value.rounded())
            }
        }

        return 0
    }
}

struct DragonYouTubeVideo: Codable, Identifiable {
    let id: String
    let video_id: String
    let title: String
    let channel: String
    let thumbnail: String
    let url: String
    let published_at: String
    let saved_at: String
    let duration: String
    let section: String
    let group: String
    let playlist: String
    let source: String

    private enum CodingKeys: String, CodingKey {
        case id
        case video_id
        case videoId
        case title
        case channel
        case channel_title
        case thumbnail
        case thumbnail_url
        case url
        case published_at
        case publishedAt
        case saved_at
        case savedAt
        case duration
        case section
        case group
        case playlist
        case playlist_title
        case source
    }

    init(id: String, video_id: String, title: String, channel: String, thumbnail: String, url: String, published_at: String, saved_at: String, duration: String, section: String, group: String, playlist: String, source: String) {
        self.id = id
        self.video_id = video_id
        self.title = title
        self.channel = channel
        self.thumbnail = thumbnail
        self.url = url
        self.published_at = published_at
        self.saved_at = saved_at
        self.duration = duration
        self.section = section
        self.group = group
        self.playlist = playlist
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonYouTubeVideo.decodeString(container, keys: [.id, .video_id, .videoId])
        self.video_id = DragonYouTubeVideo.decodeString(container, keys: [.video_id, .videoId, .id])
        self.title = DragonYouTubeVideo.decodeString(container, keys: [.title], default: "Untitled video")
        self.channel = DragonYouTubeVideo.decodeString(container, keys: [.channel, .channel_title])
        self.thumbnail = DragonYouTubeVideo.decodeString(container, keys: [.thumbnail, .thumbnail_url])
        self.url = DragonYouTubeVideo.decodeString(container, keys: [.url])
        self.published_at = DragonYouTubeVideo.decodeString(container, keys: [.published_at, .publishedAt])
        self.saved_at = DragonYouTubeVideo.decodeString(container, keys: [.saved_at, .savedAt])
        self.duration = DragonYouTubeVideo.decodeString(container, keys: [.duration])
        self.section = DragonYouTubeVideo.decodeString(container, keys: [.section])
        self.group = DragonYouTubeVideo.decodeString(container, keys: [.group])
        self.playlist = DragonYouTubeVideo.decodeString(container, keys: [.playlist, .playlist_title])
        self.source = DragonYouTubeVideo.decodeString(container, keys: [.source], default: "unknown")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(video_id, forKey: .video_id)
        try container.encode(title, forKey: .title)
        try container.encode(channel, forKey: .channel)
        try container.encode(thumbnail, forKey: .thumbnail)
        try container.encode(url, forKey: .url)
        try container.encode(published_at, forKey: .published_at)
        try container.encode(saved_at, forKey: .saved_at)
        try container.encode(duration, forKey: .duration)
        try container.encode(section, forKey: .section)
        try container.encode(group, forKey: .group)
        try container.encode(playlist, forKey: .playlist)
        try container.encode(source, forKey: .source)
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys], default defaultValue: String = "") -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }
        }

        return defaultValue
    }
}
