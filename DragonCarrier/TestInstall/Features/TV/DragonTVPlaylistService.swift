import Foundation

protocol DragonTVDataSource {
    func loadCachedChannels() async -> DragonTVCachedChannelsResult?
    func refreshChannels() async throws -> DragonTVRefreshResult
}

struct DragonRemoteM3UDataSource: Sendable {
    private let service: IPTVPlaylistService
    private let sources: [IPTVPlaylistSource]

    init(
        service: IPTVPlaylistService = IPTVPlaylistService(),
        sources: [IPTVPlaylistSource] = IPTVPlaylistSource.defaultSources
    ) {
        self.service = service
        self.sources = sources
    }

    func loadWorkingChannelsReport() async -> IPTVLoadReport {
        await service.loadWorkingChannelsReport(from: sources)
    }
}

final class DragonDefaultTVDataSource: DragonTVDataSource {
    private let service: IPTVPlaylistService
    private let cacheStore: DragonTVCacheStore
    private let sourceStore: DragonTVSourceStore

    init(
        service: IPTVPlaylistService = IPTVPlaylistService(),
        cacheStore: DragonTVCacheStore = DragonTVCacheStore(),
        sourceStore: DragonTVSourceStore = DragonTVSourceStore()
    ) {
        self.service = service
        self.cacheStore = cacheStore
        self.sourceStore = sourceStore
    }

    func loadCachedChannels() async -> DragonTVCachedChannelsResult? {
        try? await cacheStore.loadCachedReport()
    }

    func refreshChannels() async throws -> DragonTVRefreshResult {
        let sources = sourceStore.enabledPlaylistSources()
        let report = await DragonRemoteM3UDataSource(service: service, sources: sources).loadWorkingChannelsReport()
        return await cacheStore.save(report)
    }
}

struct IPTVPlaylistService: Sendable {
    private let session: URLSession
    private let downloadTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let validationBatchSize: Int
    private let allowsRangeFallback: Bool

    init(
        session: URLSession = IPTVPlaylistService.makeSession(),
        downloadTimeout: TimeInterval = 20,
        requestTimeout: TimeInterval = 5,
        validationBatchSize: Int = 40,
        allowsRangeFallback: Bool = true
    ) {
        self.session = session
        self.downloadTimeout = downloadTimeout
        self.requestTimeout = requestTimeout
        self.validationBatchSize = max(1, validationBatchSize)
        self.allowsRangeFallback = allowsRangeFallback
    }

    func loadWorkingChannels(from sources: [IPTVPlaylistSource]) async -> [IPTVChannel] {
        let report = await loadWorkingChannelsReport(from: sources)
        return report.channels
    }

    func loadWorkingChannelsReport(from sources: [IPTVPlaylistSource]) async -> IPTVLoadReport {
        let playlistResults = await fetchPlaylistResults(from: sources)
        let rawChannels = playlistResults.flatMap(\.channels)
        let dedupedChannels = deduplicate(rawChannels)
        let validatedChannels = await validate(channels: dedupedChannels)
        let sourceFailures = playlistResults.compactMap(\.failure)

        return IPTVLoadReport(
            rawChannelCount: rawChannels.count,
            dedupedChannelCount: dedupedChannels.count,
            validChannelCount: validatedChannels.count,
            sourceFailures: sourceFailures,
            channels: validatedChannels
        )
    }

    private func fetchPlaylistResults(from sources: [IPTVPlaylistSource]) async -> [PlaylistFetchResult] {
        await withTaskGroup(of: PlaylistFetchResult.self, returning: [PlaylistFetchResult].self) { group in
            for source in sources {
                group.addTask {
                    await fetchPlaylist(from: source)
                }
            }

            var results: [PlaylistFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func fetchPlaylist(from source: IPTVPlaylistSource) async -> PlaylistFetchResult {
        do {
            var request = URLRequest(url: source.url)
            request.timeoutInterval = downloadTimeout
            request.setValue("DragonTV/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return PlaylistFetchResult(
                    source: source,
                    channels: [],
                    failure: IPTVSourceFailure(
                        sourceID: source.id,
                        label: source.label,
                        url: source.url,
                        message: "Invalid response"
                    )
                )
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return PlaylistFetchResult(
                    source: source,
                    channels: [],
                    failure: IPTVSourceFailure(
                        sourceID: source.id,
                        label: source.label,
                        url: source.url,
                        message: "HTTP \(httpResponse.statusCode)"
                    )
                )
            }

            return PlaylistFetchResult(
                source: source,
                channels: parseChannels(from: data, source: source),
                failure: nil
            )
        } catch {
            return PlaylistFetchResult(
                source: source,
                channels: [],
                failure: IPTVSourceFailure(
                    sourceID: source.id,
                    label: source.label,
                    url: source.url,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func parseChannels(from data: Data, source: IPTVPlaylistSource) -> [IPTVChannel] {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines)

        var channels: [IPTVChannel] = []
        var pendingMetadata: ParsedChannelMetadata?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("#EXTINF") {
                pendingMetadata = parseEXTINF(line)
                continue
            }

            if line.hasPrefix("#") {
                continue
            }

            guard let streamURL = URL(string: line), streamURL.scheme?.dragonTrimmedOrNil != nil else {
                pendingMetadata = nil
                continue
            }

            let fallbackName = streamURL.lastPathComponent.dragonTrimmedOrNil
                ?? streamURL.host?.dragonTrimmedOrNil
                ?? "Unnamed Channel"
            let name = pendingMetadata?.name.dragonTrimmedOrNil ?? fallbackName
            let normalizedTvgID = pendingMetadata?.tvgId?.dragonTrimmedOrNil
            let dedupeID = Self.dedupeKey(
                name: name,
                url: streamURL,
                tvgId: normalizedTvgID
            )

            channels.append(
                IPTVChannel(
                    id: dedupeID,
                    name: name,
                    url: streamURL,
                    tvgId: normalizedTvgID,
                    group: pendingMetadata?.group?.dragonTrimmedOrNil,
                    logo: pendingMetadata?.logoURL,
                    sourceURLs: [source.url],
                    isFavorite: false
                )
            )

            pendingMetadata = nil
        }

        return channels
    }

    private func parseEXTINF(_ line: String) -> ParsedChannelMetadata {
        let payload = line
            .replacingOccurrences(of: "#EXTINF:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dividerIndex = firstUnquotedCommaIndex(in: payload)
        let metadataSegment = dividerIndex.map { String(payload[..<$0]) } ?? payload
        let nameSegment = dividerIndex.map { String(payload[payload.index(after: $0)...]) } ?? ""
        let attributes = parseAttributes(in: metadataSegment)

        let logoURL: URL?
        if let logoString = attributes["tvg-logo"]?.dragonTrimmedOrNil {
            logoURL = URL(string: logoString)
        } else {
            logoURL = nil
        }

        return ParsedChannelMetadata(
            name: nameSegment.trimmingCharacters(in: .whitespacesAndNewlines),
            tvgId: attributes["tvg-id"],
            group: attributes["group-title"],
            logoURL: logoURL
        )
    }

    private func parseAttributes(in segment: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(pattern: #"([A-Za-z0-9\-]+)="([^"]*)""#) else {
            return [:]
        }

        let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        let matches = expression.matches(in: segment, range: range)

        var attributes: [String: String] = [:]
        for match in matches {
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: segment),
                  let valueRange = Range(match.range(at: 2), in: segment) else {
                continue
            }

            attributes[String(segment[keyRange])] = String(segment[valueRange])
        }

        return attributes
    }

    private func deduplicate(_ channels: [IPTVChannel]) -> [IPTVChannel] {
        var deduped: [IPTVChannel] = []
        var seenIndices: [String: Int] = [:]

        for channel in channels {
            let key = Self.dedupeKey(name: channel.name, url: channel.url, tvgId: channel.tvgId)

            if let index = seenIndices[key] {
                deduped[index] = deduped[index].merged(with: channel)
            } else {
                seenIndices[key] = deduped.count
                deduped.append(channel)
            }
        }

        return deduped
    }

    private func validate(channels: [IPTVChannel]) async -> [IPTVChannel] {
        var validChannels: [IPTVChannel] = []

        for batch in channels.chunked(into: validationBatchSize) {
            let batchResults = await withTaskGroup(of: IPTVChannel?.self, returning: [IPTVChannel].self) { group in
                for channel in batch {
                    group.addTask {
                        let isReachable = await validateReachability(of: channel.url)
                        return isReachable ? channel : nil
                    }
                }

                var workingChannels: [IPTVChannel] = []
                for await result in group {
                    if let result {
                        workingChannels.append(result)
                    }
                }
                return workingChannels
            }

            let ordering = Dictionary(uniqueKeysWithValues: batch.enumerated().map { ($1.id, $0) })
            validChannels.append(contentsOf: batchResults.sorted { left, right in
                (ordering[left.id] ?? 0) < (ordering[right.id] ?? 0)
            })
        }

        return validChannels
    }

    private func validateReachability(of url: URL) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let headResult = await makeValidationRequest(url: url, method: "HEAD", rangeValue: nil)
        if headResult.isAccepted {
            return true
        }

        guard allowsRangeFallback,
              let statusCode = headResult.statusCode,
              [403, 405, 501].contains(statusCode) else {
            return false
        }

        let fallbackResult = await makeValidationRequest(url: url, method: "GET", rangeValue: "bytes=0-1")
        return fallbackResult.isAccepted
    }

    private func makeValidationRequest(url: URL, method: String, rangeValue: String?) async -> ValidationResult {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = requestTimeout
            request.setValue("DragonTV/1.0", forHTTPHeaderField: "User-Agent")
            if let rangeValue {
                request.setValue(rangeValue, forHTTPHeaderField: "Range")
            }

            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ValidationResult(statusCode: nil, contentType: nil, isAccepted: false)
            }

            return ValidationResult(
                statusCode: httpResponse.statusCode,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
                isAccepted: isAcceptableValidationResponse(httpResponse)
            )
        } catch {
            return ValidationResult(statusCode: nil, contentType: nil, isAccepted: false)
        }
    }

    private func isAcceptableValidationResponse(_ response: HTTPURLResponse) -> Bool {
        let statusCode = response.statusCode
        guard statusCode == 206 || (200...299).contains(statusCode) else {
            return false
        }

        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              !contentType.isEmpty else {
            return true
        }

        if contentType.contains("text/html") || contentType.contains("application/json") || contentType.contains("xml") {
            return false
        }

        if contentType.contains("application/vnd.apple.mpegurl")
            || contentType.contains("application/x-mpegurl")
            || contentType.contains("application/octet-stream")
            || contentType.contains("mpegurl")
            || contentType.contains("m3u8")
            || contentType.hasPrefix("video/")
            || contentType.hasPrefix("audio/") {
            return true
        }

        return !contentType.hasPrefix("text/")
    }

    private func firstUnquotedCommaIndex(in string: String) -> String.Index? {
        var isInsideQuotes = false

        for index in string.indices {
            let character = string[index]

            if character == "\"" {
                isInsideQuotes.toggle()
            } else if character == "," && !isInsideQuotes {
                return index
            }
        }

        return nil
    }

    private static func dedupeKey(name: String, url: URL, tvgId: String?) -> String {
        if let tvgId = tvgId?.dragonTrimmedOrNil {
            return normalizeDeduplicationComponent(tvgId)
        }

        return "\(normalizeDeduplicationComponent(name))|\(url.absoluteString.lowercased())"
    }

    private static func normalizeDeduplicationComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }
}

private struct PlaylistFetchResult: Sendable {
    let source: IPTVPlaylistSource
    let channels: [IPTVChannel]
    let failure: IPTVSourceFailure?
}

private struct ParsedChannelMetadata: Sendable {
    let name: String
    let tvgId: String?
    let group: String?
    let logoURL: URL?
}

private struct ValidationResult: Sendable {
    let statusCode: Int?
    let contentType: String?
    let isAccepted: Bool
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)

        var startIndex = 0
        while startIndex < count {
            let endIndex = Swift.min(startIndex + size, count)
            chunks.append(Array(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }
}
