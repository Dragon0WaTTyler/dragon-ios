import Foundation

private let dragonNotionAPIVersion = "2026-03-11"

enum DragonNotionMoviesDataSourceError: LocalizedError {
    case missingToken
    case missingSourceIdentifier
    case invalidResponse
    case dataSourceNotFound
    case databaseHasNoDataSources
    case httpStatus(Int, String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Notion token is missing."
        case .missingSourceIdentifier:
            return "Notion source ID is missing."
        case .invalidResponse:
            return "Notion returned an invalid response."
        case .dataSourceNotFound:
            return "Notion source could not be resolved."
        case .databaseHasNoDataSources:
            return "Notion database has no data sources."
        case .httpStatus(let statusCode, let message):
            return message.isEmpty ? "Notion request failed (\(statusCode))." : message
        case .requestFailed(let message):
            return message
        }
    }
}

final class DragonNotionMoviesDataSource: DragonMoviesRemoteCatalogLoader {
    private let session: URLSession
    private let settingsStore: DragonNotionSettingsStore

    init(
        session: URLSession = .shared,
        settingsStore: DragonNotionSettingsStore = DragonNotionSettingsStore()
    ) {
        self.session = session
        self.settingsStore = settingsStore
    }

    var isConfigured: Bool {
        settingsStore.isMoviesConfigured
    }

    var cacheIdentity: String {
        let sourceIdentifier = settingsStore.moviesSourceIdentifier
        if sourceIdentifier.isEmpty {
            return "notion|unconfigured"
        }
        return "notion|\(normalizedPropertyName(sourceIdentifier))"
    }

    var fallbackSourceLabel: String {
        let sourceIdentifier = settingsStore.moviesSourceIdentifier
        if sourceIdentifier.isEmpty {
            return "Notion"
        }
        return "Notion • \(sourceIdentifier)"
    }

    func refreshMovies(pageLimit: Int, maxCatalogCount: Int) async throws -> DragonMoviesRefreshResult {
        let configuration = try currentConfiguration()
        let resolvedSource = try await resolveSource(configuration: configuration)
        let pageSize = max(1, min(pageLimit, 100))

        var mergedMovies: [DragonMovie] = []
        var seenMovieIDs = Set<String>()
        var nextCursor: String?
        var pageCount = 0

        repeat {
            let page = try await queryMoviesPage(
                dataSourceID: resolvedSource.dataSourceID,
                token: configuration.token,
                pageSize: pageSize,
                startCursor: nextCursor
            )
            pageCount += 1
            dragonMergeMovies(page.movies, into: &mergedMovies, seenIDs: &seenMovieIDs)
            nextCursor = page.hasMore ? page.nextCursor : nil
        } while mergedMovies.count < maxCatalogCount && nextCursor != nil

        let limitedMovies = Array(mergedMovies.prefix(maxCatalogCount))
        let response = DragonMoviesResponse(
            api_version: "notion",
            ok: true,
            items: limitedMovies,
            count: limitedMovies.count,
            total: limitedMovies.count,
            limit: pageSize,
            offset: 0,
            has_more: false,
            next_offset: nil
        )

        return DragonMoviesRefreshResult(
            response: response,
            refreshedAt: Date(),
            source: response.items.isEmpty ? .empty : .notion,
            backendURL: resolvedSource.displayLabel,
            pageCount: max(pageCount, 1)
        )
    }

    func testConnection(
        sourceIdentifierOverride: String? = nil,
        tokenOverride: String? = nil
    ) async -> Result<String, DragonNotionMoviesDataSourceError> {
        do {
            let configuration = try currentConfiguration(
                sourceIdentifierOverride: sourceIdentifierOverride,
                tokenOverride: tokenOverride
            )
            let resolvedSource = try await resolveSource(configuration: configuration)
            _ = try await queryMoviesPage(
                dataSourceID: resolvedSource.dataSourceID,
                token: configuration.token,
                pageSize: 1,
                startCursor: nil
            )
            return .success(resolvedSource.displayLabel)
        } catch let error as DragonNotionMoviesDataSourceError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    private func currentConfiguration(
        sourceIdentifierOverride: String? = nil,
        tokenOverride: String? = nil
    ) throws -> DragonNotionConfiguration {
        let configuration = try settingsStore.loadConfiguration(
            sourceIdentifierOverride: sourceIdentifierOverride,
            tokenOverride: tokenOverride
        )

        guard !configuration.token.isEmpty else {
            throw DragonNotionMoviesDataSourceError.missingToken
        }

        guard !configuration.sourceIdentifier.isEmpty else {
            throw DragonNotionMoviesDataSourceError.missingSourceIdentifier
        }

        return configuration
    }

    private func resolveSource(configuration: DragonNotionConfiguration) async throws -> DragonResolvedNotionSource {
        if let dataSource = try await retrieveDataSource(
            identifier: configuration.sourceIdentifier,
            token: configuration.token
        ) {
            return dataSource
        }

        guard let databaseObject = try await retrieveDatabase(
            identifier: configuration.sourceIdentifier,
            token: configuration.token
        ) else {
            throw DragonNotionMoviesDataSourceError.dataSourceNotFound
        }

        guard let dataSources = databaseObject["data_sources"] as? [[String: Any]],
              let firstDataSource = dataSources.first else {
            throw DragonNotionMoviesDataSourceError.databaseHasNoDataSources
        }

        let dataSourceID = trimmedString(firstDataSource["id"])
        guard !dataSourceID.isEmpty else {
            throw DragonNotionMoviesDataSourceError.databaseHasNoDataSources
        }

        let dataSourceName = trimmedString(firstDataSource["name"])
        return DragonResolvedNotionSource(
            dataSourceID: dataSourceID,
            displayLabel: notionDisplayLabel(sourceName: dataSourceName, sourceID: dataSourceID)
        )
    }

    private func retrieveDataSource(identifier: String, token: String) async throws -> DragonResolvedNotionSource? {
        do {
            let object = try await sendRequest(
                path: "/data_sources/\(encodedPathComponent(identifier))",
                method: "GET",
                body: nil,
                token: token
            )
            guard trimmedString(object["object"]) == "data_source" else {
                throw DragonNotionMoviesDataSourceError.invalidResponse
            }

            let sourceID = trimmedString(object["id"])
            guard !sourceID.isEmpty else {
                throw DragonNotionMoviesDataSourceError.invalidResponse
            }

            let title = richTextString(from: object["title"]) ?? trimmedString(object["name"])
            return DragonResolvedNotionSource(
                dataSourceID: sourceID,
                displayLabel: notionDisplayLabel(sourceName: title, sourceID: sourceID)
            )
        } catch let error as DragonNotionMoviesDataSourceError {
            if case .httpStatus(let statusCode, _) = error, statusCode == 400 || statusCode == 404 {
                return nil
            }
            throw error
        }
    }

    private func retrieveDatabase(identifier: String, token: String) async throws -> [String: Any]? {
        do {
            return try await sendRequest(
                path: "/databases/\(encodedPathComponent(identifier))",
                method: "GET",
                body: nil,
                token: token
            )
        } catch let error as DragonNotionMoviesDataSourceError {
            if case .httpStatus(let statusCode, _) = error, statusCode == 400 || statusCode == 404 {
                return nil
            }
            throw error
        }
    }

    private func queryMoviesPage(
        dataSourceID: String,
        token: String,
        pageSize: Int,
        startCursor: String?
    ) async throws -> DragonNotionMoviesPage {
        var body: [String: Any] = [
            "page_size": pageSize
        ]
        if let startCursor, !startCursor.isEmpty {
            body["start_cursor"] = startCursor
        }

        let object = try await sendRequest(
            path: "/data_sources/\(encodedPathComponent(dataSourceID))/query",
            method: "POST",
            body: body,
            token: token
        )

        guard let results = object["results"] as? [[String: Any]] else {
            throw DragonNotionMoviesDataSourceError.invalidResponse
        }

        let movies = results.compactMap(movie(from:))
        let hasMore = object["has_more"] as? Bool ?? false
        let nextCursor = trimmedString(object["next_cursor"])
        return DragonNotionMoviesPage(movies: movies, hasMore: hasMore, nextCursor: nextCursor.isEmpty ? nil : nextCursor)
    }

    private func sendRequest(
        path: String,
        method: String,
        body: [String: Any]?,
        token: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.notion.com/v1\(path)") else {
            throw DragonNotionMoviesDataSourceError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(dragonNotionAPIVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw DragonNotionMoviesDataSourceError.requestFailed(notionRequestFailureMessage(for: urlError))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw DragonNotionMoviesDataSourceError.requestFailed(
                    notionRequestFailureMessage(for: URLError(_nsError: nsError))
                )
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonNotionMoviesDataSourceError.invalidResponse
        }

        let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
        let payload = jsonObject as? [String: Any]
        let notionMessage = trimmedString(payload?["message"])

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonNotionMoviesDataSourceError.httpStatus(httpResponse.statusCode, notionMessage)
        }

        guard let payload else {
            throw DragonNotionMoviesDataSourceError.invalidResponse
        }

        return payload
    }

    private func movie(from page: [String: Any]) -> DragonMovie? {
        guard trimmedString(page["object"]) == "page" else {
            return nil
        }

        let properties = page["properties"] as? [String: Any] ?? [:]
        let title = resolvedTitle(from: properties)
        let tmdbID = resolvedString(for: ["tmdb id", "tmdb_id", "tmdb"], in: properties)
        let movieID = trimmedString(page["id"]).isEmpty ? tmdbID : trimmedString(page["id"])

        guard !movieID.isEmpty || !title.isEmpty else {
            return nil
        }

        let poster = resolvedPoster(from: properties, page: page)
        let year = resolvedYear(in: properties)
        let director = resolvedList(for: ["director", "directors", "filmmaker"], in: properties).joined(separator: ", ")
        let genres = resolvedList(for: ["genres", "genre", "tags"], in: properties)
        let status = resolvedString(for: ["status", "watch status", "state"], in: properties)
        let score = resolvedString(for: ["score", "rating", "personal score"], in: properties)
        let type = resolvedString(for: ["type", "format", "kind", "media type"], in: properties)
        let overview = resolvedString(for: ["overview", "summary", "description", "plot", "notes"], in: properties)

        return DragonMovie(
            id: movieID.isEmpty ? title : movieID,
            title: title,
            year: year,
            poster: poster,
            director: director,
            genres: genres,
            status: status,
            score: score,
            type: type,
            overview: overview,
            tmdb_id: tmdbID
        )
    }

    private func resolvedTitle(from properties: [String: Any]) -> String {
        if let property = propertyValue(for: ["title", "name", "movie", "movie title"], in: properties) {
            let stringValue = notionStringValue(from: property)
            if !stringValue.isEmpty {
                return stringValue
            }
        }

        for value in properties.values {
            guard let property = value as? [String: Any], trimmedString(property["type"]) == "title" else {
                continue
            }
            let stringValue = notionStringValue(from: property)
            if !stringValue.isEmpty {
                return stringValue
            }
        }

        return ""
    }

    private func resolvedPoster(from properties: [String: Any], page: [String: Any]) -> String {
        if let property = propertyValue(for: ["poster", "poster url", "poster_url", "image", "cover", "artwork"], in: properties) {
            let propertyPoster = notionPosterValue(from: property)
            if !propertyPoster.isEmpty {
                return propertyPoster
            }
        }

        if let cover = page["cover"] as? [String: Any] {
            let coverURL = notionFileURL(from: cover)
            if !coverURL.isEmpty {
                return coverURL
            }
        }

        return ""
    }

    private func resolvedYear(in properties: [String: Any]) -> String {
        if let property = propertyValue(for: ["year", "release year", "released", "release date"], in: properties) {
            return notionYearValue(from: property)
        }
        return ""
    }

    private func resolvedString(for aliases: [String], in properties: [String: Any]) -> String {
        guard let property = propertyValue(for: aliases, in: properties) else {
            return ""
        }
        return notionStringValue(from: property)
    }

    private func resolvedList(for aliases: [String], in properties: [String: Any]) -> [String] {
        guard let property = propertyValue(for: aliases, in: properties) else {
            return []
        }
        return notionStringList(from: property)
    }

    private func propertyValue(for aliases: [String], in properties: [String: Any]) -> [String: Any]? {
        let aliasSet = Set(aliases.map(normalizedPropertyName))
        for (key, value) in properties {
            guard aliasSet.contains(normalizedPropertyName(key)),
                  let property = value as? [String: Any] else {
                continue
            }
            return property
        }
        return nil
    }
}

private func notionRequestFailureMessage(for urlError: URLError) -> String {
    switch urlError.code {
    case .notConnectedToInternet,
         .cannotConnectToHost,
         .networkConnectionLost,
         .dnsLookupFailed,
         .internationalRoamingOff,
         .callIsActive,
         .dataNotAllowed,
         .secureConnectionFailed:
        return "Could not reach Notion."
    case .timedOut:
        return "Notion request timed out."
    default:
        return "Could not load Notion movies."
    }
}

private struct DragonResolvedNotionSource {
    let dataSourceID: String
    let displayLabel: String
}

private struct DragonNotionMoviesPage {
    let movies: [DragonMovie]
    let hasMore: Bool
    let nextCursor: String?
}

private func notionDisplayLabel(sourceName: String, sourceID: String) -> String {
    let trimmedName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty {
        return "Notion • \(trimmedName)"
    }
    return "Notion • \(sourceID)"
}

private func encodedPathComponent(_ value: String) -> String {
    var allowedCharacters = CharacterSet.urlPathAllowed
    allowedCharacters.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
}

private func normalizedPropertyName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

private func trimmedString(_ value: Any?) -> String {
    switch value {
    case let string as String:
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    case let number as NSNumber:
        return number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    default:
        return ""
    }
}

private func notionStringValue(from property: [String: Any]) -> String {
    let type = trimmedString(property["type"])

    switch type {
    case "title":
        return richTextString(from: property["title"]) ?? ""
    case "rich_text":
        return richTextString(from: property["rich_text"]) ?? ""
    case "select":
        return trimmedString((property["select"] as? [String: Any])?["name"])
    case "status":
        return trimmedString((property["status"] as? [String: Any])?["name"])
    case "number":
        return notionNumberString(from: property["number"])
    case "url":
        return trimmedString(property["url"])
    case "email":
        return trimmedString(property["email"])
    case "phone_number":
        return trimmedString(property["phone_number"])
    case "checkbox":
        if let checkboxValue = property["checkbox"] as? Bool {
            return checkboxValue ? "true" : "false"
        }
        return ""
    case "date":
        return trimmedString((property["date"] as? [String: Any])?["start"])
    case "files":
        return notionFileURL(from: property)
    case "people":
        return notionPeopleNames(from: property).joined(separator: ", ")
    case "multi_select":
        return notionMultiSelectNames(from: property).joined(separator: ", ")
    case "formula":
        return notionFormulaString(from: property["formula"] as? [String: Any] ?? [:])
    case "unique_id":
        return notionUniqueIDString(from: property["unique_id"] as? [String: Any] ?? [:])
    default:
        return ""
    }
}

private func notionStringList(from property: [String: Any]) -> [String] {
    let type = trimmedString(property["type"])

    switch type {
    case "multi_select":
        return notionMultiSelectNames(from: property)
    case "people":
        return notionPeopleNames(from: property)
    default:
        let stringValue = notionStringValue(from: property)
        guard !stringValue.isEmpty else {
            return []
        }

        let separators = CharacterSet(charactersIn: ",/\n|")
        return stringValue
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private func notionPosterValue(from property: [String: Any]) -> String {
    let fileURL = notionFileURL(from: property)
    if !fileURL.isEmpty {
        return fileURL
    }
    return notionStringValue(from: property)
}

private func notionYearValue(from property: [String: Any]) -> String {
    let rawValue = notionStringValue(from: property)
    if rawValue.count >= 4 {
        let prefix = String(rawValue.prefix(4))
        if prefix.allSatisfy(\.isNumber) {
            return prefix
        }
    }
    return rawValue
}

private func notionNumberString(from value: Any?) -> String {
    guard let value else {
        return ""
    }

    if let intValue = value as? Int {
        return String(intValue)
    }

    if let doubleValue = value as? Double {
        if doubleValue.rounded(.towardZero) == doubleValue {
            return String(Int(doubleValue))
        }
        return String(doubleValue)
    }

    if let numberValue = value as? NSNumber {
        let doubleValue = numberValue.doubleValue
        if doubleValue.rounded(.towardZero) == doubleValue {
            return String(Int(doubleValue))
        }
        return numberValue.stringValue
    }

    return ""
}

private func notionFormulaString(from formula: [String: Any]) -> String {
    let type = trimmedString(formula["type"])
    switch type {
    case "string":
        return trimmedString(formula["string"])
    case "number":
        return notionNumberString(from: formula["number"])
    case "boolean":
        if let booleanValue = formula["boolean"] as? Bool {
            return booleanValue ? "true" : "false"
        }
        return ""
    case "date":
        return trimmedString((formula["date"] as? [String: Any])?["start"])
    default:
        return ""
    }
}

private func notionUniqueIDString(from uniqueID: [String: Any]) -> String {
    let prefix = trimmedString(uniqueID["prefix"])
    let number = notionNumberString(from: uniqueID["number"])

    if prefix.isEmpty {
        return number
    }

    if number.isEmpty {
        return prefix
    }

    return "\(prefix)-\(number)"
}

private func notionMultiSelectNames(from property: [String: Any]) -> [String] {
    let values = property["multi_select"] as? [[String: Any]] ?? []
    return values.map { trimmedString($0["name"]) }.filter { !$0.isEmpty }
}

private func notionPeopleNames(from property: [String: Any]) -> [String] {
    let people = property["people"] as? [[String: Any]] ?? []
    return people.map { trimmedString($0["name"]) }.filter { !$0.isEmpty }
}

private func notionFileURL(from property: [String: Any]) -> String {
    let type = trimmedString(property["type"])

    if type == "external" || type == "file" {
        return notionSingleFileURL(from: property)
    }

    let files = property["files"] as? [[String: Any]] ?? []
    for file in files {
        let url = notionSingleFileURL(from: file)
        if !url.isEmpty {
            return url
        }
    }

    return ""
}

private func notionSingleFileURL(from fileObject: [String: Any]) -> String {
    let externalURL = trimmedString((fileObject["external"] as? [String: Any])?["url"])
    if !externalURL.isEmpty {
        return externalURL
    }

    let fileURL = trimmedString((fileObject["file"] as? [String: Any])?["url"])
    if !fileURL.isEmpty {
        return fileURL
    }

    return trimmedString(fileObject["url"])
}

private func richTextString(from value: Any?) -> String? {
    let items = value as? [[String: Any]] ?? []
    let text = items
        .compactMap { item -> String? in
            let plainText = trimmedString(item["plain_text"])
            if !plainText.isEmpty {
                return plainText
            }
            return trimmedString((item["text"] as? [String: Any])?["content"])
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return text.isEmpty ? nil : text
}
