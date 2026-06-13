import Foundation

final class DragonSnapshotFallback {
    static let shared = DragonSnapshotFallback()

    private let youtubeSnapshotURL = URL(string: "https://raw.githubusercontent.com/Dragon0WaTTyler/dragon-dashboard/main/cache/youtube_latest_snapshot.json")!
    private let decoder = JSONDecoder()

    func apiResponseData(for originalURL: URL, session: URLSession) async throws -> Data? {
        guard let request = SnapshotRequest(url: originalURL) else {
            return nil
        }

        let snapshot = try await fetchYouTubeSnapshot(session: session)
        switch request {
        case .youtubeVideos(let query):
            return try makeYouTubeVideosResponse(snapshot: snapshot, query: query)
        case .youtubeSections:
            return try makeYouTubeSectionsResponse(snapshot: snapshot)
        }
    }

    private func fetchYouTubeSnapshot(session: URLSession) async throws -> YouTubeSnapshot {
        let request = URLRequest(
            url: youtubeSnapshotURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DragonSnapshotFallbackError.invalidSnapshotResponse
        }
        return try decoder.decode(YouTubeSnapshot.self, from: data)
    }

    private func makeYouTubeVideosResponse(snapshot: YouTubeSnapshot, query: YouTubeVideoQuery) throws -> Data {
        let allItems = flattenedVideos(from: snapshot, section: query.section)
            .filter { video in
                guard let localQuery = query.q else {
                    return true
                }
                return video.matches(query: localQuery)
            }

        let offset = min(query.offset, allItems.count)
        let endIndex = min(offset + query.limit, allItems.count)
        let pageItems = Array(allItems[offset..<endIndex])
        let hasMore = endIndex < allItems.count

        let response: [String: Any] = [
            "api_version": "v1",
            "ok": true,
            "section": query.section ?? "all",
            "items": pageItems.map(\.apiDictionary),
            "count": pageItems.count,
            "total": allItems.count,
            "limit": query.limit,
            "offset": query.offset,
            "has_more": hasMore,
            "next_offset": hasMore ? endIndex : NSNull()
        ]

        return try JSONSerialization.data(withJSONObject: response, options: [])
    }

    private func makeYouTubeSectionsResponse(snapshot: YouTubeSnapshot) throws -> Data {
        let sections = snapshot.groups.values
            .map { group in
                [
                    "key": group.resolvedSectionKey,
                    "label": group.resolvedSectionName,
                    "count": group.videos.count
                ] as [String: Any]
            }
            .sorted { left, right in
                let leftLabel = left["label"] as? String ?? ""
                let rightLabel = right["label"] as? String ?? ""
                return leftLabel.localizedCaseInsensitiveCompare(rightLabel) == .orderedAscending
            }

        let response: [String: Any] = [
            "api_version": "v1",
            "ok": true,
            "sections": sections
        ]

        return try JSONSerialization.data(withJSONObject: response, options: [])
    }

    private func flattenedVideos(from snapshot: YouTubeSnapshot, section: String?) -> [YouTubeSnapshotVideo] {
        let selectedGroups = snapshot.groups.values
            .filter { group in
                guard let section else {
                    return true
                }
                return group.matches(section: section)
            }

        var seen = Set<String>()
        let videos = selectedGroups
            .flatMap { group in
                group.videos.map { video in
                    video.withFallbackSection(
                        key: group.resolvedSectionKey,
                        name: group.resolvedSectionName
                    )
                }
            }
            .sorted { left, right in
                left.published_at > right.published_at
            }
            .filter { video in
                let key = video.dedupeKey
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }

        return videos
    }
}

private enum DragonSnapshotFallbackError: Error {
    case invalidSnapshotResponse
}

private enum SnapshotRequest {
    case youtubeVideos(YouTubeVideoQuery)
    case youtubeSections

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.path {
        case "/api/v1/youtube":
            guard let query = YouTubeVideoQuery(queryItems: components.queryItems ?? []) else {
                return nil
            }
            self = .youtubeVideos(query)
        case "/api/v1/youtube/sections":
            self = .youtubeSections
        default:
            return nil
        }
    }
}

private struct YouTubeVideoQuery {
    let source: String
    let section: String?
    let limit: Int
    let offset: Int
    let q: String?

    init?(queryItems: [URLQueryItem]) {
        let source = queryItems.stringValue(named: "source")?.lowercased() ?? "all"
        guard source == "pockettube" else {
            return nil
        }

        self.source = source
        self.section = queryItems.trimmedStringValue(named: "section")
        self.limit = max(1, queryItems.intValue(named: "limit") ?? 50)
        self.offset = max(0, queryItems.intValue(named: "offset") ?? 0)
        self.q = queryItems.trimmedStringValue(named: "q")?.lowercased()
    }
}

private struct YouTubeSnapshot: Decodable {
    let groups: [String: YouTubeSnapshotGroup]
}

private struct YouTubeSnapshotGroup: Decodable {
    let group_name: String?
    let group_key: String?
    let section_name: String?
    let section_key: String?
    let videos: [YouTubeSnapshotVideo]

    var resolvedSectionKey: String {
        [section_key, group_key, section_name, group_name]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? "unknown"
    }

    var resolvedSectionName: String {
        [section_name, group_name, section_key, group_key]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? resolvedSectionKey
    }

    func matches(section: String) -> Bool {
        let normalizedSection = section.normalizedSnapshotKey
        return [section_key, group_key, section_name, group_name]
            .compactMap { $0?.normalizedSnapshotKey }
            .contains(normalizedSection)
    }
}

private struct YouTubeSnapshotVideo: Decodable {
    let entry_id: String?
    let video_id: String?
    let title: String?
    let channel_name: String?
    let channel_title: String?
    let thumbnail: String?
    let thumbnail_url: String?
    let image_url: String?
    let thumb: String?
    let url: String?
    let published_at: String
    let group_name: String?
    let group_key: String?
    let group_names: [String]?
    let group_keys: [String]?

    private enum CodingKeys: String, CodingKey {
        case entry_id
        case video_id
        case title
        case channel_name
        case channel_title
        case thumbnail
        case thumbnail_url
        case image_url
        case thumb
        case url
        case published_at
        case group_name
        case group_key
        case group_names
        case group_keys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entry_id = try container.decodeIfPresent(String.self, forKey: .entry_id)
        self.video_id = try container.decodeIfPresent(String.self, forKey: .video_id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.channel_name = try container.decodeIfPresent(String.self, forKey: .channel_name)
        self.channel_title = try container.decodeIfPresent(String.self, forKey: .channel_title)
        self.thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        self.thumbnail_url = try container.decodeIfPresent(String.self, forKey: .thumbnail_url)
        self.image_url = try container.decodeIfPresent(String.self, forKey: .image_url)
        self.thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.published_at = try container.decodeIfPresent(String.self, forKey: .published_at) ?? ""
        self.group_name = try container.decodeIfPresent(String.self, forKey: .group_name)
        self.group_key = try container.decodeIfPresent(String.self, forKey: .group_key)
        self.group_names = try container.decodeIfPresent([String].self, forKey: .group_names)
        self.group_keys = try container.decodeIfPresent([String].self, forKey: .group_keys)
    }

    private init(
        entry_id: String?,
        video_id: String?,
        title: String?,
        channel_name: String?,
        channel_title: String?,
        thumbnail: String?,
        thumbnail_url: String?,
        image_url: String?,
        thumb: String?,
        url: String?,
        published_at: String,
        group_name: String?,
        group_key: String?,
        group_names: [String]?,
        group_keys: [String]?
    ) {
        self.entry_id = entry_id
        self.video_id = video_id
        self.title = title
        self.channel_name = channel_name
        self.channel_title = channel_title
        self.thumbnail = thumbnail
        self.thumbnail_url = thumbnail_url
        self.image_url = image_url
        self.thumb = thumb
        self.url = url
        self.published_at = published_at
        self.group_name = group_name
        self.group_key = group_key
        self.group_names = group_names
        self.group_keys = group_keys
    }

    var dedupeKey: String {
        [video_id, entry_id, url]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? UUID().uuidString
    }

    var apiDictionary: [String: Any] {
        let resolvedID = [entry_id, video_id, url].compactMap { $0?.trimmedNonEmpty }.first ?? ""
        let resolvedVideoID = video_id?.trimmedNonEmpty ?? resolvedID
        let resolvedSection = [group_key, group_keys?.first, group_name, group_names?.first]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? ""
        let resolvedChannel = [channel_name, channel_title]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? ""
        let resolvedThumbnail = [thumbnail, thumbnail_url, image_url, thumb]
            .compactMap { $0?.trimmedNonEmpty }
            .first ?? ""

        return [
            "id": resolvedID,
            "video_id": resolvedVideoID,
            "title": title?.trimmedNonEmpty ?? "Untitled video",
            "channel": resolvedChannel,
            "thumbnail": resolvedThumbnail,
            "url": url?.trimmedNonEmpty ?? "",
            "published_at": published_at,
            "saved_at": "",
            "duration": "",
            "section": resolvedSection,
            "group": group_name?.trimmedNonEmpty ?? resolvedSection,
            "playlist": "",
            "source": "pockettube"
        ]
    }

    func matches(query: String) -> Bool {
        let haystack = [
            title,
            channel_name,
            channel_title,
            group_name,
            group_key,
            url,
            video_id
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return haystack.contains(query)
    }

    func withFallbackSection(key: String, name: String) -> YouTubeSnapshotVideo {
        YouTubeSnapshotVideo(
            entry_id: entry_id,
            video_id: video_id,
            title: title,
            channel_name: channel_name,
            channel_title: channel_title,
            thumbnail: thumbnail,
            thumbnail_url: thumbnail_url,
            image_url: image_url,
            thumb: thumb,
            url: url,
            published_at: published_at,
            group_name: group_name?.trimmedNonEmpty ?? name,
            group_key: group_key?.trimmedNonEmpty ?? key,
            group_names: group_names,
            group_keys: group_keys
        )
    }
}

private extension Array where Element == URLQueryItem {
    func stringValue(named name: String) -> String? {
        first { $0.name == name }?.value
    }

    func trimmedStringValue(named name: String) -> String? {
        stringValue(named: name)?.trimmedNonEmpty
    }

    func intValue(named name: String) -> Int? {
        guard let value = stringValue(named: name) else {
            return nil
        }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSnapshotKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
