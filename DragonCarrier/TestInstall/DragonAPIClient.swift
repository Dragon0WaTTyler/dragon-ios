import Foundation

let dragonBackendBaseURLDefaultsKey = "dragon.backendBaseURL"
let dragonDefaultBackendBaseURL = "http://127.0.0.1:5000"
let dragonBooksRemoteRescueBaseURL = "https://dragon99.pythonanywhere.com"
let dragonArticlesRequestLimit = 300

func normalizeDragonBackendBaseURL(_ rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    guard normalized.hasPrefix("http://") || normalized.hasPrefix("https://") else {
        return nil
    }
    guard URL(string: normalized) != nil else {
        return nil
    }

    return normalized
}

func currentDragonBackendBaseURL() -> String {
    let storedValue = UserDefaults.standard.string(forKey: dragonBackendBaseURLDefaultsKey) ?? ""
    return normalizeDragonBackendBaseURL(storedValue) ?? dragonDefaultBackendBaseURL
}

final class DragonAPIClient {
    static let shared = DragonAPIClient()

    private let session: URLSession
    private let baseURLProvider: () -> String
    private let responseCache: DragonResponseCache
    private let snapshotFallback: DragonSnapshotFallback

    var backendBaseURL: String {
        baseURLProvider()
    }

    init(
        session: URLSession = .shared,
        baseURLProvider: @escaping () -> String = currentDragonBackendBaseURL,
        responseCache: DragonResponseCache = .shared,
        snapshotFallback: DragonSnapshotFallback = .shared
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
        self.responseCache = responseCache
        self.snapshotFallback = snapshotFallback
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: backendBaseURL) else {
            return nil
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        try await fetchDecodable(DragonHomeResponse.self, path: "/api/v1/home")
    }

    func fetchArticles(limit: Int = dragonArticlesRequestLimit) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        try await fetchDecodable(
            DragonArticlesResponse.self,
            path: "/api/v1/articles",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw DragonAPIError.invalidURL
        }

        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw DragonAPIError.invalidURL
        }

        let result = try await fetchDecodable(
            DragonArticleDetailResponse.self,
            path: "/api/v1/articles/\(encodedID)"
        )

        guard result.value.ok else {
            throw DragonAPIError.invalidResponse
        }

        return DragonAPIFetchResult(
            value: result.value.item,
            source: result.source,
            resolvedURL: result.resolvedURL
        )
    }

    func fetchBooks(limit: Int = 50, offset: Int = 0, query: String? = nil) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        return try await fetchDecodable(DragonBooksResponse.self, path: "/api/v1/books", queryItems: queryItems)
    }

    func fetchMovies(limit: Int = 20) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        try await fetchMovies(limit: limit, offset: 0)
    }

    func fetchMovies(limit: Int = 20, offset: Int = 0, allowsCaching: Bool = true) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        return try await fetchDecodable(
            DragonMoviesResponse.self,
            path: "/api/v1/movies",
            queryItems: queryItems,
            allowsCaching: allowsCaching
        )
    }

    func fetchYouTubeVideos(source: String = "all", section: String? = nil, limit: Int = 50, offset: Int = 0, query: String? = nil) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        var queryItems = [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "section", value: section))
        }
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        return try await fetchDecodable(DragonYouTubeResponse.self, path: "/api/v1/youtube", queryItems: queryItems)
    }

    func fetchYouTubeVideos(section: String, limit: Int = 50, offset: Int = 0) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        let queryItems = [
            URLQueryItem(name: "section", value: section),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        return try await fetchDecodable(DragonYouTubeVideosResponse.self, path: "/api/v1/youtube/videos", queryItems: queryItems)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        try await fetchDecodable(DragonYouTubeSectionsResponse.self, path: "/api/v1/youtube/sections")
    }

    func testBackendConnection() async -> Result<Void, DragonAPIError> {
        do {
            try await fetchHealth()
            return .success(())
        } catch {
            return .failure(error as? DragonAPIError ?? .invalidResponse)
        }
    }

    private func fetchHealth() async throws {
        guard let url = endpointURL(path: "/api/v1/health") else {
            throw DragonAPIError.invalidURL
        }

        if let response = try? await session.data(from: url).1, try isSuccessfulHTTPResponse(response) {
            return
        }

        guard let fallbackURL = endpointURL(path: "/api/v1/home") else {
            throw DragonAPIError.invalidURL
        }

        let (_, fallbackResponse) = try await session.data(from: fallbackURL)
        guard try isSuccessfulHTTPResponse(fallbackResponse) else {
            throw DragonAPIError.invalidResponse
        }
    }

    private func isSuccessfulHTTPResponse(_ response: URLResponse) throws -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            return false
        }

        return true
    }

    private func fetchDecodable<Response: Decodable>(
        _ responseType: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        allowsCaching: Bool = true
    ) async throws -> DragonAPIFetchResult<Response> {
        guard let url = endpointURL(path: path, queryItems: queryItems) else {
            throw DragonAPIError.invalidURL
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        let decoder = JSONDecoder()

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DragonAPIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw DragonAPIError.httpStatus(httpResponse.statusCode)
            }

            let decoded = try decoder.decode(Response.self, from: data)
            if allowsCaching {
                await responseCache.save(data: data, for: url)
            }
            return DragonAPIFetchResult(value: decoded, source: .network, resolvedURL: url)
        } catch let networkError {
            guard allowsCaching else {
                throw networkError
            }

            if let cachedResponse = await responseCache.load(for: url) {
                do {
                    let decoded = try decoder.decode(Response.self, from: cachedResponse.data)
                    return DragonAPIFetchResult(
                        value: decoded,
                        source: .cache(cachedResponse.metadata),
                        resolvedURL: url
                    )
                } catch {
                    throw error
                }
            }

            let snapshotData: Data
            do {
                guard let data = try await snapshotFallback.apiResponseData(for: url, session: session) else {
                    throw networkError
                }
                snapshotData = data
            } catch let snapshotError {
#if DEBUG
                print("Dragon snapshot fallback unavailable for \(url.absoluteString): \(snapshotError)")
#endif
                throw networkError
            }

            do {
                let decoded = try decoder.decode(Response.self, from: snapshotData)
                await responseCache.save(data: snapshotData, for: url)
                return DragonAPIFetchResult(
                    value: decoded,
                    source: .snapshot,
                    resolvedURL: url
                )
            } catch let decodingError {
#if DEBUG
                print("Dragon snapshot fallback decode failed for \(url.absoluteString): \(decodingError)")
#endif
                throw decodingError
            }
        }
    }
}

enum DragonAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid backend response"
        case .httpStatus(let statusCode):
            return "HTTP \(statusCode)"
        }
    }
}

func dragonUserFacingMessage(for error: Error) -> String {
    if let apiError = error as? DragonAPIError {
        return dragonUserFacingMessage(for: apiError)
    }

    if let snapshotValidationError = error as? DragonCoreSnapshotValidationError {
        return dragonUserFacingMessage(for: snapshotValidationError)
    }

    if let remoteSnapshotError = error as? DragonRemoteSnapshotDataSourceError {
        return remoteSnapshotError.errorDescription ?? "Could not load data."
    }

    if let bundledSnapshotError = error as? DragonBundledSnapshotError {
        return dragonUserFacingMessage(for: bundledSnapshotError)
    }

    if let remoteSnapshotClientError = error as? DragonRemoteSnapshotClientError {
        return dragonUserFacingMessage(for: remoteSnapshotClientError)
    }

    if let notionError = error as? DragonNotionMoviesDataSourceError {
        return dragonUserFacingMessage(for: notionError)
    }

    if let urlError = error as? URLError {
        return dragonUserFacingMessage(for: urlError)
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        return dragonUserFacingMessage(for: URLError(_nsError: nsError))
    }

    if error is DecodingError {
        return "Backend returned empty data."
    }

    return "Could not load data."
}

func dragonUserFacingMessage(for bundledSnapshotError: DragonBundledSnapshotError) -> String {
    switch bundledSnapshotError {
    case .missingSnapshotFile:
        return "Bundled snapshot file is missing."
    case .unreadableSnapshot:
        return "Bundled snapshot could not be read."
    case .invalidSnapshot:
        return "Bundled snapshot is invalid."
    }
}

func dragonUserFacingMessage(for validationError: DragonCoreSnapshotValidationError) -> String {
    switch validationError {
    case .fileTooSmall, .invalidJSON, .invalidRootObject, .invalidSchemaVersion, .missingTopLevelKey, .missingContainer, .forbiddenKey, .suspiciousValue, .undecodableSnapshot:
        return "Dragon snapshot is invalid."
    }
}

func dragonUserFacingMessage(for remoteSnapshotClientError: DragonRemoteSnapshotClientError) -> String {
    switch remoteSnapshotClientError {
    case .invalidHTTPResponse:
        return "Remote Dragon snapshot replied unexpectedly."
    case .httpStatus(let statusCode):
        return dragonUserFacingMessage(forHTTPStatus: statusCode)
    }
}

func dragonUserFacingMessage(for notionError: DragonNotionMoviesDataSourceError) -> String {
    switch notionError {
    case .missingToken:
        return "Notion token is not configured."
    case .missingSourceIdentifier:
        return "Notion source ID is not configured."
    case .invalidResponse:
        return "Notion replied unexpectedly."
    case .dataSourceNotFound:
        return "Notion source could not be found."
    case .databaseHasNoDataSources:
        return "Notion database has no data source."
    case .httpStatus(let statusCode, let message):
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return dragonUserFacingMessage(forHTTPStatus: statusCode)
    }
}

func dragonUserFacingMessage(for apiError: DragonAPIError) -> String {
    switch apiError {
    case .invalidURL:
        return "Backend URL is invalid."
    case .invalidResponse:
        return "Backend replied unexpectedly."
    case .httpStatus(let statusCode):
        return dragonUserFacingMessage(forHTTPStatus: statusCode)
    }
}

func dragonUserFacingMessage(for urlError: URLError) -> String {
    switch urlError.code {
    case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive, .dataNotAllowed, .secureConnectionFailed:
        return "Backend is offline."
    case .timedOut:
        return "Request timed out."
    case .fileDoesNotExist:
        return "No data returned."
    default:
        return "Could not load data."
    }
}

func dragonUserFacingMessage(forHTTPStatus statusCode: Int) -> String {
    switch statusCode {
    case 404:
        return "Not found."
    case 204:
        return "No data returned."
    default:
        return "Backend returned an error."
    }
}

extension DragonAPIClient: DragonDataSource {}
