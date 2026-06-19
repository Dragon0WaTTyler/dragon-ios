import Foundation

struct DragonHealthResponse: Decodable {
    let api_version: String
    let ok: Bool
    let service: String
}

struct DragonHomeResponse: Decodable {
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

struct DragonSection: Decodable, Identifiable {
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

struct DragonArticlesResponse: Codable, Sendable {
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

struct DragonArticle: Codable, Sendable, Identifiable {
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

struct DragonBooksResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonBook]
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case items
        case count
        case total
    }

    init(api_version: String, ok: Bool, items: [DragonBook], count: Int) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonBook].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
            ?? items.count
    }
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
    let total: Int
    let limit: Int?
    let offset: Int?
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
        items: [DragonMovie],
        count: Int,
        total: Int? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        has_more: Bool? = nil,
        next_offset: Int? = nil
    ) {
        self.api_version = api_version
        self.ok = ok
        self.items = items
        self.count = count
        self.total = total ?? count
        self.limit = limit
        self.offset = offset
        self.has_more = has_more ?? false
        self.next_offset = next_offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.items = try container.decodeIfPresent([DragonMovie].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? count
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        self.has_more = try container.decodeIfPresent(Bool.self, forKey: .has_more) ?? false
        self.next_offset = try container.decodeIfPresent(Int.self, forKey: .next_offset)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(api_version, forKey: .api_version)
        try container.encode(ok, forKey: .ok)
        try container.encode(items, forKey: .items)
        try container.encode(count, forKey: .count)
        try container.encode(total, forKey: .total)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encode(has_more, forKey: .has_more)
        try container.encodeIfPresent(next_offset, forKey: .next_offset)
    }
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
    let backdrop: String?
    let genres: [String]
    let runtime: String?
    let detailURLString: String?
    let progressValue: Double?
    let progressText: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case year
        case release_year
        case release_date
        case first_air_date
        case poster
        case poster_url
        case image
        case backdrop
        case backdrop_url
        case banner
        case status
        case score
        case rating
        case vote_average
        case type
        case media_type
        case overview
        case plot
        case summary
        case genres
        case genre
        case genre_names
        case runtime
        case duration
        case length
        case detail_url
        case detailUrl
        case href
        case url
        case progress
        case watch_progress
    }

    init(
        id: String,
        title: String,
        year: String,
        poster: String,
        status: String,
        score: String,
        type: String,
        overview: String,
        backdrop: String? = nil,
        genres: [String] = [],
        runtime: String? = nil,
        detailURLString: String? = nil,
        progressValue: Double? = nil,
        progressText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.poster = poster
        self.status = status
        self.score = score
        self.type = type
        self.overview = overview
        self.backdrop = backdrop
        self.genres = genres
        self.runtime = runtime
        self.detailURLString = detailURLString
        self.progressValue = progressValue
        self.progressText = progressText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedTitle = DragonMovie.decodeString(container, forKeys: [.title, .name], default: "Untitled movie")
        let decodedYear = DragonMovie.decodeYear(container)
        let decodedPoster = DragonMovie.decodeString(container, forKeys: [.poster, .poster_url, .image])
        let decodedStatus = DragonMovie.decodeString(container, forKeys: [.status])
        let decodedScore = DragonMovie.decodeString(container, forKeys: [.score, .rating, .vote_average])
        let decodedType = DragonMovie.decodeString(container, forKeys: [.type, .media_type])
        let decodedOverview = DragonMovie.decodeString(container, forKeys: [.overview, .plot, .summary])
        let decodedBackdrop = DragonMovie.decodeOptionalString(container, forKeys: [.backdrop, .backdrop_url, .banner])
        let decodedGenres = DragonMovie.decodeStringArray(container, forKeys: [.genres, .genre_names, .genre])
        let decodedRuntime = DragonMovie.decodeOptionalString(container, forKeys: [.runtime, .duration, .length])
        let decodedDetailURL = DragonMovie.decodeOptionalString(container, forKeys: [.detail_url, .detailUrl, .href, .url])
        let decodedProgressValue = DragonMovie.decodeOptionalDouble(container, forKeys: [.progress, .watch_progress])
        let decodedProgressText = DragonMovie.decodeOptionalString(container, forKeys: [.progress, .watch_progress])

        let decodedID = DragonMovie.decodeString(container, forKeys: [.id])
        if decodedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackID = "\(decodedTitle)-\(decodedYear)"
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            self.id = fallbackID.isEmpty ? UUID().uuidString : fallbackID
        } else {
            self.id = decodedID
        }

        self.title = decodedTitle
        self.year = decodedYear
        self.poster = decodedPoster
        self.status = decodedStatus
        self.score = decodedScore
        self.type = decodedType
        self.overview = decodedOverview
        self.backdrop = decodedBackdrop
        self.genres = decodedGenres
        self.runtime = decodedRuntime
        self.detailURLString = decodedDetailURL
        self.progressValue = decodedProgressValue
        self.progressText = decodedProgressText
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(year, forKey: .year)
        try container.encode(poster, forKey: .poster)
        try container.encode(status, forKey: .status)
        try container.encode(score, forKey: .score)
        try container.encode(type, forKey: .type)
        try container.encode(overview, forKey: .overview)
        try container.encodeIfPresent(backdrop, forKey: .backdrop)
        try container.encode(genres, forKey: .genres)
        try container.encodeIfPresent(runtime, forKey: .runtime)
        try container.encodeIfPresent(detailURLString, forKey: .detail_url)
        try container.encodeIfPresent(progressValue, forKey: .progress)
        try container.encodeIfPresent(progressText, forKey: .watch_progress)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled movie" : trimmed
    }

    var posterURL: URL? {
        Self.sanitizedArtworkURL(from: poster)
    }

    var backdropURL: URL? {
        Self.sanitizedArtworkURL(from: backdrop ?? "")
    }

    var primaryArtworkURL: URL? {
        backdropURL ?? posterURL
    }

    var detailURL: URL? {
        guard let detailURLString else {
            return nil
        }

        let trimmed = detailURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return nil
        }

        return URL(string: trimmed)
    }

    var progressFraction: Double? {
        guard let progressValue else {
            return nil
        }

        if progressValue > 1 {
            return min(progressValue / 100, 1)
        }

        return max(0, min(progressValue, 1))
    }

    var progressDisplayText: String? {
        if let progressText {
            let trimmed = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let fraction = progressFraction else {
            return nil
        }

        return "\(Int((fraction * 100).rounded()))%"
    }

    var sortScore: Double {
        let normalized = score.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let numeric = Double(normalized) {
            return numeric
        }

        switch normalized {
        case "masterpiece", "excellent":
            return 9.5
        case "great":
            return 8.8
        case "very good":
            return 8.0
        case "good":
            return 7.2
        case "solid":
            return 6.8
        case "decent":
            return 6.2
        case "ok":
            return 5.5
        case "average":
            return 5.0
        case "weak":
            return 4.2
        default:
            return 0
        }
    }

    var isFinished: Bool {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus.contains("finish") || normalizedStatus.contains("watch") || normalizedStatus.contains("complete") {
            return true
        }

        if let progressFraction, progressFraction >= 0.98 {
            return true
        }

        return false
    }

    var isInProgress: Bool {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus.contains("watching") || normalizedStatus.contains("progress") || normalizedStatus.contains("continue") {
            return true
        }

        if let progressFraction, progressFraction > 0.01 && progressFraction < 0.98 {
            return true
        }

        return false
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

    private static func decodeOptionalString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        let value = decodeString(container, forKeys: keys)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeOptionalDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return Double(value)
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }

                let digitsOnly = trimmed.replacingOccurrences(of: "%", with: "")
                if let numeric = Double(digitsOnly) {
                    return trimmed.contains("%") ? numeric / 100 : numeric
                }
            }
        }

        return nil
    }

    private static func decodeStringArray(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> [String] {
        for key in keys {
            if let values = try? container.decode([String].self, forKey: key) {
                let trimmed = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let pieces = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !pieces.isEmpty {
                    return pieces
                }
            }
        }

        return []
    }

    private static func decodeYear(_ container: KeyedDecodingContainer<CodingKeys>) -> String {
        if let explicitYear = decodeOptionalString(container, forKeys: [.year, .release_year]) {
            return explicitYear
        }

        if let rawDate = decodeOptionalString(container, forKeys: [.release_date, .first_air_date]) {
            return String(rawDate.prefix(4))
        }

        return ""
    }

    private static func sanitizedArtworkURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalizedValue: String
        if trimmed.hasPrefix("//") {
            normalizedValue = "https:\(trimmed)"
        } else {
            normalizedValue = trimmed
        }

        guard var components = URLComponents(string: normalizedValue) else {
            return nil
        }

        let host = components.host?.lowercased() ?? ""
        if (host == "www.themoviedb.org" || host == "themoviedb.org"),
           components.path.hasPrefix("/t/p/") {
            components.scheme = "https"
            components.host = "image.tmdb.org"
            components.query = nil
            components.fragment = nil
        }

        return components.url
    }
}

struct DragonYouTubeVideosResponse: Decodable {
    let api_version: String
    let ok: Bool
    let section: String
    let items: [DragonYouTubeVideo]
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case api_version
        case ok
        case section
        case items
        case count
    }

    init(api_version: String, ok: Bool, section: String, items: [DragonYouTubeVideo], count: Int) {
        self.api_version = api_version
        self.ok = ok
        self.section = section
        self.items = items
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.api_version = try container.decodeIfPresent(String.self, forKey: .api_version) ?? "v1"
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.section = DragonYouTubeVideosResponse.decodeString(container, keys: [.section])
        self.items = try container.decodeIfPresent([DragonYouTubeVideo].self, forKey: .items) ?? []
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
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

struct DragonYouTubeSectionsResponse: Decodable {
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

struct DragonYouTubeSection: Decodable, Identifiable {
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
