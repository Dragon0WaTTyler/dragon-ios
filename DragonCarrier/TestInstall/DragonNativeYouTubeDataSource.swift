import Foundation

protocol DragonYouTubePlaylistLoading {
    func loadCachedYouTubeVideos(limit: Int, offset: Int, query: String?) async -> DragonAPIFetchResult<DragonYouTubeResponse>?
    func currentYouTubeConfiguration() -> DragonYouTubePlaylistConfiguration
}

enum DragonYouTubePlaylistDataSourceError: LocalizedError {
    case playlistNotConfigured
    case apiKeyNotConfigured
    case invalidPlaylistIdentifier
    case invalidResponse
    case requestFailed(String)
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .playlistNotConfigured:
            return "YouTube playlist is not configured. Add a playlist link in Settings -> YouTube."
        case .apiKeyNotConfigured:
            return "YouTube API key is not configured."
        case .invalidPlaylistIdentifier:
            return "A valid YouTube playlist ID is required."
        case .invalidResponse:
            return "YouTube replied unexpectedly."
        case .requestFailed(let message):
            return message
        case .httpStatus(let statusCode, let message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            switch statusCode {
            case 400:
                return "YouTube rejected the playlist request."
            case 401, 403:
                return "YouTube API key is missing, invalid, or out of quota."
            case 404:
                return "YouTube playlist could not be found."
            default:
                return "YouTube returned an error."
            }
        }
    }
}

private struct DragonCachedYouTubePlaylistPayload: Codable {
    let response: DragonYouTubeResponse
    let playlistID: String
    let playlistURL: String
    let displayName: String
    let fetchedAt: Date
    let wasCapped: Bool
}

final class DragonNativeYouTubeDataSource: DragonDataSource, DragonYouTubePlaylistLoading {
    private let fallback: DragonDataSource
    private let settingsStore: DragonYouTubeSettingsStore
    private let responseCache: DragonResponseCache
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maxPlaylistItems = 200
    private let requestPageSize = 50

    init(
        fallback: DragonDataSource,
        settingsStore: DragonYouTubeSettingsStore = DragonYouTubeSettingsStore(),
        responseCache: DragonResponseCache = .shared,
        session: URLSession = .shared
    ) {
        self.fallback = fallback
        self.settingsStore = settingsStore
        self.responseCache = responseCache
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func currentYouTubeConfiguration() -> DragonYouTubePlaylistConfiguration {
        (try? settingsStore.loadConfiguration()) ?? DragonYouTubePlaylistConfiguration(
            playlistURL: settingsStore.playlistURL,
            playlistID: settingsStore.playlistID,
            displayName: settingsStore.displayName,
            apiKey: ""
        )
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        try await fallback.fetchHome()
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await fallback.fetchArticles(limit: limit)
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        try await fallback.fetchArticleDetail(id: id)
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        try await fallback.fetchBooks(limit: limit, offset: offset, query: query)
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        try await fallback.fetchMovies(limit: limit)
    }

    func loadCachedYouTubeVideos(limit: Int, offset: Int, query: String?) async -> DragonAPIFetchResult<DragonYouTubeResponse>? {
        let configuration = currentYouTubeConfiguration()
        guard configuration.hasPlaylist else {
            return nil
        }

        guard let cachedResponse = await responseCache.load(for: dragonYouTubePlaylistCacheURL(playlistID: configuration.playlistID)),
              let payload = try? decoder.decode(DragonCachedYouTubePlaylistPayload.self, from: cachedResponse.data),
              payload.playlistID.caseInsensitiveCompare(configuration.playlistID) == .orderedSame else {
            return nil
        }

        let response = makePagedResponse(
            from: payload.response.items,
            configuration: configuration,
            limit: limit,
            offset: offset,
            query: query
        )

        return DragonAPIFetchResult(
            value: response,
            source: .cache(cachedResponse.metadata),
            resolvedURL: dragonYouTubePlaylistCacheURL(playlistID: configuration.playlistID)
        )
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedSource == "playlist" else {
            return try await fallback.fetchYouTubeVideos(
                source: source,
                section: section,
                limit: limit,
                offset: offset,
                query: query
            )
        }

        let configuration = try settingsStore.loadConfiguration()
        guard configuration.hasPlaylist else {
            throw DragonYouTubePlaylistDataSourceError.playlistNotConfigured
        }
        guard configuration.hasAPIKey else {
            throw DragonYouTubePlaylistDataSourceError.apiKeyNotConfigured
        }
        guard DragonYouTubePlaylistIdentifier.isLikelyPlaylistID(configuration.playlistID) else {
            throw DragonYouTubePlaylistDataSourceError.invalidPlaylistIdentifier
        }

        do {
            let payload = try await refreshPlaylistPayload(configuration: configuration)
            await saveCachedPayload(payload, playlistID: configuration.playlistID)
            let response = makePagedResponse(
                from: payload.response.items,
                configuration: configuration,
                limit: limit,
                offset: offset,
                query: query
            )
            return DragonAPIFetchResult(
                value: response,
                source: .network,
                resolvedURL: dragonYouTubePlaylistCacheURL(playlistID: configuration.playlistID)
            )
        } catch {
            if let cachedResult = await loadCachedYouTubeVideos(limit: limit, offset: offset, query: query) {
                return cachedResult
            }
            throw error
        }
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        try await fallback.fetchYouTubeVideos(section: section, limit: limit, offset: offset)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        try await fallback.fetchYouTubeSections()
    }

    private func refreshPlaylistPayload(configuration: DragonYouTubePlaylistConfiguration) async throws -> DragonCachedYouTubePlaylistPayload {
        var allVideos: [DragonYouTubeVideo] = []
        var seenVideoIDs = Set<String>()
        var nextPageToken: String?
        var wasCapped = false

        repeat {
            let page = try await fetchPlaylistPage(
                playlistID: configuration.playlistID,
                apiKey: configuration.apiKey,
                pageToken: nextPageToken
            )

            for item in page.items {
                guard let video = makeVideo(from: item, configuration: configuration) else {
                    continue
                }

                let dedupeKey = video.video_id.isEmpty ? video.id : video.video_id
                guard !dedupeKey.isEmpty, !seenVideoIDs.contains(dedupeKey) else {
                    continue
                }

                seenVideoIDs.insert(dedupeKey)
                allVideos.append(video)

                if allVideos.count >= maxPlaylistItems {
                    wasCapped = page.nextPageToken != nil
                    break
                }
            }

            if allVideos.count >= maxPlaylistItems {
                break
            }

            nextPageToken = page.nextPageToken
        } while nextPageToken != nil

        let response = DragonYouTubeResponse(
            api_version: "v1",
            ok: true,
            section: "playlist",
            items: allVideos,
            count: allVideos.count,
            total: allVideos.count,
            limit: allVideos.count,
            offset: 0,
            has_more: false,
            next_offset: nil
        )

        return DragonCachedYouTubePlaylistPayload(
            response: response,
            playlistID: configuration.playlistID,
            playlistURL: configuration.playlistURL,
            displayName: configuration.displayName,
            fetchedAt: Date(),
            wasCapped: wasCapped
        )
    }

    private func fetchPlaylistPage(
        playlistID: String,
        apiKey: String,
        pageToken: String?
    ) async throws -> DragonYouTubePlaylistItemsPage {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "maxResults", value: String(requestPageSize)),
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "key", value: apiKey)
        ]

        if let pageToken, !pageToken.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        guard let url = components?.url else {
            throw DragonYouTubePlaylistDataSourceError.invalidPlaylistIdentifier
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DragonYouTubePlaylistDataSourceError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let apiError = try? decoder.decode(DragonYouTubeAPIErrorEnvelope.self, from: data)
                throw DragonYouTubePlaylistDataSourceError.httpStatus(httpResponse.statusCode, apiError?.error.message)
            }

            do {
                return try decoder.decode(DragonYouTubePlaylistItemsPage.self, from: data)
            } catch {
                throw DragonYouTubePlaylistDataSourceError.invalidResponse
            }
        } catch let error as DragonYouTubePlaylistDataSourceError {
            throw error
        } catch let urlError as URLError {
            throw DragonYouTubePlaylistDataSourceError.requestFailed(dragonUserFacingMessage(for: urlError))
        } catch {
            throw DragonYouTubePlaylistDataSourceError.requestFailed("Could not load YouTube playlist.")
        }
    }

    private func saveCachedPayload(_ payload: DragonCachedYouTubePlaylistPayload, playlistID: String) async {
        guard let data = try? encoder.encode(payload) else {
            return
        }

        await responseCache.save(data: data, for: dragonYouTubePlaylistCacheURL(playlistID: playlistID))
    }

    private func makePagedResponse(
        from allVideos: [DragonYouTubeVideo],
        configuration: DragonYouTubePlaylistConfiguration,
        limit: Int,
        offset: Int,
        query: String?
    ) -> DragonYouTubeResponse {
        let filteredVideos = filterVideos(allVideos, query: query)
        let safeOffset = max(offset, 0)
        let safeLimit = max(limit, 1)
        let pageItems = Array(filteredVideos.dropFirst(safeOffset).prefix(safeLimit))
        let hasMore = safeOffset + pageItems.count < filteredVideos.count

        return DragonYouTubeResponse(
            api_version: "v1",
            ok: true,
            section: configuration.resolvedDisplayName,
            items: pageItems,
            count: pageItems.count,
            total: filteredVideos.count,
            limit: safeLimit,
            offset: safeOffset,
            has_more: hasMore,
            next_offset: hasMore ? safeOffset + pageItems.count : nil
        )
    }

    private func filterVideos(_ videos: [DragonYouTubeVideo], query: String?) -> [DragonYouTubeVideo] {
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedQuery.isEmpty else {
            return videos
        }

        return videos.filter { video in
            [
                video.title,
                video.channel,
                video.playlist
            ]
            .map { $0.lowercased() }
            .contains { $0.contains(normalizedQuery) }
        }
    }

    private func makeVideo(
        from item: DragonYouTubePlaylistItem,
        configuration: DragonYouTubePlaylistConfiguration
    ) -> DragonYouTubeVideo? {
        let videoID = item.contentDetails?.videoId
            ?? item.snippet?.resourceId?.videoId
            ?? ""
        guard DragonYouTubeVideo.isValidYouTubeVideoID(videoID) else {
            return nil
        }

        let title = item.snippet?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let channelTitle = item.snippet?.videoOwnerChannelTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackChannelTitle = item.snippet?.channelTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbnailURL = item.snippet?.thumbnails?.bestAvailableURL ?? ""
        let playlistName = configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Playlist"
            : configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        return DragonYouTubeVideo(
            id: item.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.id! : videoID,
            video_id: videoID,
            title: title.isEmpty ? "Untitled video" : title,
            channel: channelTitle?.isEmpty == false ? channelTitle! : (fallbackChannelTitle ?? ""),
            thumbnail: thumbnailURL,
            url: "https://www.youtube.com/watch?v=\(videoID)",
            published_at: item.snippet?.publishedAt ?? "",
            saved_at: "",
            duration: "",
            section: "Playlist",
            group: "",
            playlist: playlistName,
            source: "playlist"
        )
    }
}

private struct DragonYouTubePlaylistItemsPage: Decodable {
    let nextPageToken: String?
    let items: [DragonYouTubePlaylistItem]
}

private struct DragonYouTubePlaylistItem: Decodable {
    let id: String?
    let snippet: DragonYouTubePlaylistSnippet?
    let contentDetails: DragonYouTubePlaylistContentDetails?
}

private struct DragonYouTubePlaylistSnippet: Decodable {
    let title: String?
    let channelTitle: String?
    let videoOwnerChannelTitle: String?
    let publishedAt: String?
    let thumbnails: DragonYouTubePlaylistThumbnails?
    let resourceId: DragonYouTubePlaylistResourceID?
}

private struct DragonYouTubePlaylistContentDetails: Decodable {
    let videoId: String?
}

private struct DragonYouTubePlaylistResourceID: Decodable {
    let videoId: String?
}

private struct DragonYouTubePlaylistThumbnails: Decodable {
    let `default`: DragonYouTubeThumbnailResource?
    let medium: DragonYouTubeThumbnailResource?
    let high: DragonYouTubeThumbnailResource?
    let standard: DragonYouTubeThumbnailResource?
    let maxres: DragonYouTubeThumbnailResource?

    var bestAvailableURL: String? {
        maxres?.url ?? standard?.url ?? high?.url ?? medium?.url ?? `default`?.url
    }
}

private struct DragonYouTubeThumbnailResource: Decodable {
    let url: String?
}

private struct DragonYouTubeAPIErrorEnvelope: Decodable {
    let error: DragonYouTubeAPIErrorBody
}

private struct DragonYouTubeAPIErrorBody: Decodable {
    let message: String?
}

func dragonYouTubePlaylistCacheURL(playlistID: String) -> URL {
    var components = URLComponents()
    components.scheme = "dragon-cache"
    components.host = "youtube"
    components.path = "/playlist-v1"
    components.queryItems = [
        URLQueryItem(name: "playlist_id", value: playlistID)
    ]

    return components.url
        ?? URL(string: "dragon-cache://youtube/playlist-v1?playlist_id=\(playlistID)")!
}
