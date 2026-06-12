import Foundation

let dragonBackendBaseURLDefaultsKey = "dragon.backendBaseURL"
let dragonDefaultBackendBaseURL = "http://127.0.0.1:5000"

protocol DragonHomeFetching {
    func fetchHome() async throws -> DragonHomeResponse
}

protocol DragonArticlesFetching {
    func fetchArticles(limit: Int) async throws -> DragonArticlesResponse
}

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

    var backendBaseURL: String {
        baseURLProvider()
    }

    init(
        session: URLSession = .shared,
        baseURLProvider: @escaping () -> String = currentDragonBackendBaseURL
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: backendBaseURL) else {
            return nil
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    func fetchHome() async throws -> DragonHomeResponse {
        guard let url = endpointURL(path: "/api/v1/home") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonHomeResponse.self, from: data)
    }

    func fetchArticles(limit: Int = 20) async throws -> DragonArticlesResponse {
        guard let url = endpointURL(path: "/api/v1/articles", queryItems: [URLQueryItem(name: "limit", value: String(limit))]) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonArticlesResponse.self, from: data)
    }

    func fetchBooks(limit: Int = 20) async throws -> DragonBooksResponse {
        guard let url = endpointURL(path: "/api/v1/books", queryItems: [URLQueryItem(name: "limit", value: String(limit))]) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonBooksResponse.self, from: data)
    }

    func fetchMovies(limit: Int = 20) async throws -> DragonMoviesResponse {
        guard let url = endpointURL(path: "/api/v1/movies", queryItems: [URLQueryItem(name: "limit", value: String(limit))]) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonMoviesResponse.self, from: data)
    }

    func fetchYouTubeVideos(source: String = "all", section: String? = nil, limit: Int = 20) async throws -> DragonYouTubeResponse {
        var queryItems = [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "section", value: section))
        }

        guard let url = endpointURL(path: "/api/v1/youtube", queryItems: queryItems) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonYouTubeResponse.self, from: data)
    }

    func fetchYouTubeVideos(section: String, limit: Int = 50) async throws -> DragonYouTubeVideosResponse {
        let queryItems = [
            URLQueryItem(name: "section", value: section),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = endpointURL(path: "/api/v1/youtube/videos", queryItems: queryItems) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonYouTubeVideosResponse.self, from: data)
    }

    func fetchYouTubeSections() async throws -> DragonYouTubeSectionsResponse {
        guard let url = endpointURL(path: "/api/v1/youtube/sections") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonYouTubeSectionsResponse.self, from: data)
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

extension DragonAPIClient: DragonHomeFetching, DragonArticlesFetching {}
