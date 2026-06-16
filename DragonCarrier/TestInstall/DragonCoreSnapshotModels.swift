import Foundation

struct DragonCoreSnapshot: Codable {
    let schema_version: String
    let generated_at: String
    let producer: DragonCoreSnapshotProducer?
    let status: DragonCoreSnapshotStatus?
    let home: DragonCoreSnapshotHome?
    let books: DragonCoreSnapshotDomain<DragonBook>?
    let articles: DragonCoreSnapshotDomain<DragonArticle>?
    let movies: DragonCoreSnapshotDomain<DragonMovie>?
    let youtube: DragonCoreSnapshotYouTube?

    private enum CodingKeys: String, CodingKey {
        case schema_version
        case generated_at
        case producer
        case status
        case home
        case books
        case articles
        case movies
        case youtube
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema_version = container.decodeFlexibleString(forKey: .schema_version) ?? ""
        self.generated_at = container.decodeFlexibleString(forKey: .generated_at) ?? ""
        self.producer = try? container.decode(DragonCoreSnapshotProducer.self, forKey: .producer)
        self.status = try? container.decode(DragonCoreSnapshotStatus.self, forKey: .status)
        self.home = try? container.decode(DragonCoreSnapshotHome.self, forKey: .home)
        self.books = try? container.decode(DragonCoreSnapshotDomain<DragonBook>.self, forKey: .books)
        self.articles = try? container.decode(DragonCoreSnapshotDomain<DragonArticle>.self, forKey: .articles)
        self.movies = try? container.decode(DragonCoreSnapshotDomain<DragonMovie>.self, forKey: .movies)
        self.youtube = try? container.decode(DragonCoreSnapshotYouTube.self, forKey: .youtube)
    }
}

struct DragonCoreSnapshotProducer: Codable {
    let name: String
    let version: String
    let build: String
    let environment: String

    private enum CodingKeys: String, CodingKey {
        case name
        case version
        case build
        case environment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = container.decodeFlexibleString(forKey: .name) ?? ""
        self.version = container.decodeFlexibleString(forKey: .version) ?? ""
        self.build = container.decodeFlexibleString(forKey: .build) ?? ""
        self.environment = container.decodeFlexibleString(forKey: .environment) ?? ""
    }
}

struct DragonCoreSnapshotStatus: Codable {
    let overall: String
    let home: String
    let books: String
    let articles: String
    let movies: String
    let youtube: String

    private enum CodingKeys: String, CodingKey {
        case overall
        case home
        case books
        case articles
        case movies
        case youtube
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.overall = container.decodeFlexibleString(forKey: .overall) ?? ""
        self.home = container.decodeFlexibleString(forKey: .home) ?? ""
        self.books = container.decodeFlexibleString(forKey: .books) ?? ""
        self.articles = container.decodeFlexibleString(forKey: .articles) ?? ""
        self.movies = container.decodeFlexibleString(forKey: .movies) ?? ""
        self.youtube = container.decodeFlexibleString(forKey: .youtube) ?? ""
    }

    func status(forDomainKey domainKey: String) -> String? {
        switch domainKey.lowercased() {
        case "home":
            return home.nonEmptyValue
        case "books":
            return books.nonEmptyValue
        case "articles":
            return articles.nonEmptyValue
        case "movies":
            return movies.nonEmptyValue
        case "youtube":
            return youtube.nonEmptyValue
        default:
            return overall.nonEmptyValue
        }
    }
}

struct DragonCoreSnapshotHome: Codable {
    let app_name: String
    let api_version: String
    let ok: Bool?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.app_name = container.decodeFlexibleString(forKey: .app_name) ?? ""
        self.api_version = container.decodeFlexibleString(forKey: .api_version) ?? ""
        self.ok = container.decodeFlexibleBool(forKey: .ok)
        self.server_time = container.decodeFlexibleString(forKey: .server_time) ?? ""
        self.sections = (try? container.decode([DragonSection].self, forKey: .sections)) ?? []
        self.service = container.decodeFlexibleString(forKey: .service) ?? ""
    }
}

struct DragonCoreSnapshotDomain<Item: Codable>: Codable {
    let total: Int
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case total
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = (try? container.decode([Item].self, forKey: .items)) ?? []
        self.total = container.decodeFlexibleInt(forKey: .total) ?? items.count
    }
}

struct DragonCoreSnapshotYouTube: Codable {
    let sections: [DragonYouTubeSection]
    let videos: [DragonYouTubeVideo]

    private enum CodingKeys: String, CodingKey {
        case sections
        case videos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sections = (try? container.decode([DragonYouTubeSection].self, forKey: .sections)) ?? []
        self.videos = (try? container.decode([DragonYouTubeVideo].self, forKey: .videos)) ?? []
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? decode(Double.self, forKey: key) {
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        }

        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return nil
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }

        if let value = try? decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }

        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }

        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }

        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let value = try? decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }

        return nil
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
