import Foundation

struct DragonHealthResponse: Decodable {
    let api_version: String
    let ok: Bool
    let service: String
}

struct DragonHomeResponse: Decodable {
    let api_version: String
    let ok: Bool
    let sections: [DragonSection]
    let service: String
}

struct DragonSection: Decodable, Identifiable {
    let key: String
    let label: String
    let status: String
    let count: Int?

    var id: String {
        key
    }

    var displayCount: String {
        guard let count else {
            return "—"
        }

        return String(count)
    }
}

struct DragonArticlesResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonArticle]
    let count: Int
}

struct DragonArticle: Decodable, Identifiable {
    let id: String
    let title: String
    let source: String
    let url: String
    let published_at: String
    let saved_at: String
    let excerpt: String
}

struct DragonBooksResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonBook]
    let count: Int
}

struct DragonBook: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let authors: [String]
    let cover: String
    let year: String
    let status: String
    let score: String
    let excerpt: String
}

struct DragonMoviesResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonMovie]
    let count: Int
}

struct DragonMovie: Decodable, Identifiable {
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

struct DragonYouTubeResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonYouTubeVideo]
    let count: Int
}

struct DragonYouTubeSectionsResponse: Decodable {
    let api_version: String
    let ok: Bool
    let sections: [DragonYouTubeSection]
}

struct DragonYouTubeSection: Decodable, Identifiable {
    let key: String
    let label: String
    let count: Int

    var id: String {
        key
    }
}

struct DragonYouTubeVideo: Decodable, Identifiable {
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
