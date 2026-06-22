import Foundation

protocol DragonTVDataSource {
    func loadCachedChannels() async -> DragonTVCachedChannelsResult?
    func loadCachedHealthSnapshot() async -> DragonTVCachedHealthSnapshotResult?
    func refreshChannels() async throws -> DragonTVRefreshResult
    func runHealthCheck() async throws -> DragonTVHealthRefreshResult
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

    func loadCatalogReport() async -> IPTVLoadReport {
        await service.loadCatalogReport(from: sources)
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

    func loadCachedHealthSnapshot() async -> DragonTVCachedHealthSnapshotResult? {
        try? await cacheStore.loadCachedHealthSnapshot()
    }

    func refreshChannels() async throws -> DragonTVRefreshResult {
        let sources = sourceStore.enabledPlaylistSources()
        let report = await DragonRemoteM3UDataSource(service: service, sources: sources).loadCatalogReport()
        return await cacheStore.save(report)
    }

    func runHealthCheck() async throws -> DragonTVHealthRefreshResult {
        let catalogReport: IPTVLoadReport

        if let cachedCatalog = try? await cacheStore.loadCachedReport() {
            catalogReport = cachedCatalog.report
        } else {
            let sources = sourceStore.enabledPlaylistSources()
            let fetchedCatalog = await DragonRemoteM3UDataSource(service: service, sources: sources).loadCatalogReport()
            let cachedCatalog = await cacheStore.save(fetchedCatalog)
            catalogReport = cachedCatalog.report
        }

        let snapshot = await service.loadHealthSnapshot(
            for: catalogReport.channels,
            sourceDiagnostics: catalogReport.sourceDiagnostics
        )
        return await cacheStore.saveHealthSnapshot(snapshot)
    }
}

struct IPTVPlaylistService: Sendable {
    private let session: URLSession
    private let downloadTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let validationBatchSize: Int
    private let allowsRangeFallback: Bool
    private let interestingKeywords = [
        "arryadia",
        "al kass",
        "alkass",
        "ksa sports",
        "sharjah sports",
        "bahrain sports",
        "ktv sport",
        "oman sports",
        "iraqia sport",
        "sport",
        "sports",
        "bein"
    ]

    init(
        session: URLSession = IPTVPlaylistService.makeSession(),
        downloadTimeout: TimeInterval = 20,
        requestTimeout: TimeInterval = 5,
        validationBatchSize: Int = 16,
        allowsRangeFallback: Bool = true
    ) {
        self.session = session
        self.downloadTimeout = downloadTimeout
        self.requestTimeout = requestTimeout
        self.validationBatchSize = max(1, validationBatchSize)
        self.allowsRangeFallback = allowsRangeFallback
    }

    func loadWorkingChannels(from sources: [IPTVPlaylistSource]) async -> [IPTVChannel] {
        let report = await loadCatalogReport(from: sources)
        return report.channels
    }

    func loadCatalogReport(from sources: [IPTVPlaylistSource]) async -> IPTVLoadReport {
        let playlistResults = await fetchPlaylistResults(from: sources)
        let rawChannels = playlistResults.flatMap(\.channels)
        let dedupedChannels = deduplicate(rawChannels)
        let sourceDiagnostics = buildSourceDiagnostics(from: playlistResults)
        let sourceFailures: [IPTVSourceFailure] = sourceDiagnostics.compactMap { diagnostic in
            guard let errorMessage = diagnostic.errorMessage else {
                return nil
            }

            return IPTVSourceFailure(
                sourceID: diagnostic.sourceID,
                label: diagnostic.label,
                url: diagnostic.url,
                message: errorMessage
            )
        }

        return IPTVLoadReport(
            rawChannelCount: rawChannels.count,
            dedupedChannelCount: dedupedChannels.count,
            sourceFailures: sourceFailures,
            sourceDiagnostics: sourceDiagnostics,
            interestingChannelDiagnostics: [],
            channels: dedupedChannels
        )
    }

    func loadHealthSnapshot(
        for channels: [IPTVChannel],
        sourceDiagnostics: [IPTVSourceDiagnostic]
    ) async -> IPTVHealthSnapshot {
        let validationOutcomes = await validate(channels: channels)
        let workingChannelCount = validationOutcomes.filter(\.isReachable).count
        let checkedChannelCount = validationOutcomes.count

        return IPTVHealthSnapshot(
            checkedChannelCount: checkedChannelCount,
            workingChannelCount: workingChannelCount,
            failedChannelCount: checkedChannelCount - workingChannelCount,
            sourceDiagnostics: buildHealthSourceDiagnostics(
                from: sourceDiagnostics,
                validationOutcomes: validationOutcomes
            ),
            lastCheckedAt: Date()
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
                    downloadSucceeded: false,
                    errorMessage: "Invalid response"
                )
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return PlaylistFetchResult(
                    source: source,
                    channels: [],
                    downloadSucceeded: false,
                    errorMessage: "HTTP \(httpResponse.statusCode)"
                )
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            let parsedChannels = parseChannels(from: data, source: source)
            let channels: [IPTVChannel]

            if parsedChannels.isEmpty,
               let directChannel = makeDirectSourceChannelIfNeeded(source: source, contentType: contentType) {
                channels = [directChannel]
            } else {
                channels = parsedChannels
            }

            return PlaylistFetchResult(
                source: source,
                channels: channels,
                downloadSucceeded: true,
                errorMessage: nil
            )
        } catch {
            return PlaylistFetchResult(
                source: source,
                channels: [],
                downloadSucceeded: false,
                errorMessage: error.localizedDescription
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
                    httpUserAgent: pendingMetadata?.httpUserAgent?.dragonTrimmedOrNil,
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
            logoURL: logoURL,
            httpUserAgent: attributes["http-user-agent"]
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

    private func validate(channels: [IPTVChannel]) async -> [ChannelValidationOutcome] {
        var validationOutcomes: [ChannelValidationOutcome] = []

        for batch in channels.chunked(into: validationBatchSize) {
            let batchResults = await withTaskGroup(of: ChannelValidationOutcome.self, returning: [ChannelValidationOutcome].self) { group in
                for channel in batch {
                    group.addTask {
                        await validateReachability(of: channel)
                    }
                }

                var outcomes: [ChannelValidationOutcome] = []
                for await result in group {
                    outcomes.append(result)
                }
                return outcomes
            }

            let ordering = Dictionary(uniqueKeysWithValues: batch.enumerated().map { ($1.id, $0) })
            validationOutcomes.append(contentsOf: batchResults.sorted { left, right in
                (ordering[left.channel.id] ?? 0) < (ordering[right.channel.id] ?? 0)
            })
        }

        return validationOutcomes
    }

    private func validateReachability(of channel: IPTVChannel) async -> ChannelValidationOutcome {
        let url = channel.url

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return ChannelValidationOutcome(
                channel: channel,
                isReachable: false,
                statusCode: nil,
                errorMessage: "Unsupported stream scheme"
            )
        }

        let headResult = await makeValidationRequest(
            url: url,
            method: "HEAD",
            rangeValue: nil,
            userAgent: channel.httpUserAgent
        )
        if headResult.isAccepted {
            return ChannelValidationOutcome(
                channel: channel,
                isReachable: true,
                statusCode: headResult.statusCode,
                errorMessage: nil
            )
        }

        guard allowsRangeFallback,
              let statusCode = headResult.statusCode,
              [403, 405, 406, 501].contains(statusCode) else {
            return ChannelValidationOutcome(
                channel: channel,
                isReachable: false,
                statusCode: headResult.statusCode,
                errorMessage: headResult.failureDescription
            )
        }

        let fallbackResult = await makeValidationRequest(
            url: url,
            method: "GET",
            rangeValue: "bytes=0-1",
            userAgent: channel.httpUserAgent
        )
        if fallbackResult.isAccepted {
            return ChannelValidationOutcome(
                channel: channel,
                isReachable: true,
                statusCode: fallbackResult.statusCode,
                errorMessage: nil
            )
        }

        let fallbackMessage = fallbackResult.failureDescription ?? headResult.failureDescription
        return ChannelValidationOutcome(
            channel: channel,
            isReachable: false,
            statusCode: fallbackResult.statusCode ?? headResult.statusCode,
            errorMessage: fallbackMessage.map { "HEAD fallback failed: \($0)" } ?? "HEAD fallback failed"
        )
    }

    private func makeValidationRequest(
        url: URL,
        method: String,
        rangeValue: String?,
        userAgent: String?
    ) async -> ValidationResult {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = requestTimeout
            request.setValue(userAgent?.dragonTrimmedOrNil ?? "DragonTV/1.0", forHTTPHeaderField: "User-Agent")
            if let rangeValue {
                request.setValue(rangeValue, forHTTPHeaderField: "Range")
            }

            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ValidationResult(
                    method: method,
                    statusCode: nil,
                    contentType: nil,
                    isAccepted: false,
                    errorMessage: "Invalid response"
                )
            }

            return ValidationResult(
                method: method,
                statusCode: httpResponse.statusCode,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
                isAccepted: isAcceptableValidationResponse(httpResponse),
                errorMessage: nil
            )
        } catch {
            return ValidationResult(
                method: method,
                statusCode: nil,
                contentType: nil,
                isAccepted: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func makeDirectSourceChannelIfNeeded(source: IPTVPlaylistSource, contentType: String?) -> IPTVChannel? {
        guard isLikelyDirectStream(contentType: contentType, url: source.url) else {
            return nil
        }

        return IPTVChannel(
            id: Self.dedupeKey(name: source.label, url: source.url, tvgId: source.id),
            name: source.label,
            url: source.url,
            tvgId: source.id,
            group: "Direct Source",
            logo: nil,
            httpUserAgent: nil,
            sourceURLs: [source.url],
            isFavorite: false
        )
    }

    private func isLikelyDirectStream(contentType: String?, url _: URL) -> Bool {
        let normalizedContentType = contentType?.lowercased() ?? ""
        if normalizedContentType.hasPrefix("video/") || normalizedContentType.hasPrefix("audio/") {
            return true
        }

        if normalizedContentType.contains("mpegurl")
            || normalizedContentType.contains("m3u8")
            || normalizedContentType.contains("application/octet-stream") {
            return true
        }

        return false
    }

    private func buildSourceDiagnostics(
        from playlistResults: [PlaylistFetchResult]
    ) -> [IPTVSourceDiagnostic] {
        return playlistResults
            .sorted { $0.source.label.localizedCaseInsensitiveCompare($1.source.label) == .orderedAscending }
            .map { result in
                let interestingMatchCount = result.channels.filter { matchedKeywords(for: $0).isEmpty == false }.count
                return IPTVSourceDiagnostic(
                    sourceID: result.source.id,
                    label: result.source.label,
                    url: result.source.url,
                    downloadSucceeded: result.downloadSucceeded,
                    parsedChannelCount: result.channels.count,
                    validChannelCount: nil,
                    interestingMatchCount: interestingMatchCount,
                    errorMessage: result.errorMessage
                )
            }
    }

    private func buildHealthSourceDiagnostics(
        from sourceDiagnostics: [IPTVSourceDiagnostic],
        validationOutcomes: [ChannelValidationOutcome]
    ) -> [IPTVSourceDiagnostic] {
        let validationPairsBySourceURL = Dictionary(
            grouping: validationOutcomes.flatMap { outcome in
                outcome.channel.sourceURLs.map { (sourceURL: $0.absoluteString, channelID: outcome.channel.id, isReachable: outcome.isReachable) }
            },
            by: \.sourceURL
        )

        return sourceDiagnostics.map { diagnostic in
            let pairs = validationPairsBySourceURL[diagnostic.url.absoluteString] ?? []
            let workingChannelCount = Set(
                pairs.compactMap { pair in
                    pair.isReachable ? pair.channelID : nil
                }
            ).count

            return IPTVSourceDiagnostic(
                sourceID: diagnostic.sourceID,
                label: diagnostic.label,
                url: diagnostic.url,
                downloadSucceeded: diagnostic.downloadSucceeded,
                parsedChannelCount: diagnostic.parsedChannelCount,
                validChannelCount: workingChannelCount,
                interestingMatchCount: diagnostic.interestingMatchCount,
                errorMessage: diagnostic.errorMessage
            )
        }
    }

    private func buildInterestingChannelDiagnostics(
        from channels: [IPTVChannel],
        validationOutcomes: [ChannelValidationOutcome]
    ) -> [IPTVInterestingChannelDiagnostic] {
        let validationByChannelID = Dictionary(uniqueKeysWithValues: validationOutcomes.map { ($0.channel.id, $0) })

        return channels.compactMap { channel in
            let keywords = matchedKeywords(for: channel)
            guard !keywords.isEmpty, let validation = validationByChannelID[channel.id] else {
                return nil
            }

            return IPTVInterestingChannelDiagnostic(
                channelID: channel.id,
                name: channel.name,
                streamURL: channel.url,
                group: channel.group,
                logoURL: channel.logo,
                httpUserAgent: channel.httpUserAgent,
                matchedKeywords: keywords,
                sourceLabels: channel.sourceLabels(),
                sourceURLs: channel.sourceURLs,
                status: validation.isReachable ? .validatedWorking : .parsedButFailedValidation,
                statusCode: validation.statusCode,
                errorMessage: validation.errorMessage
            )
        }
        .sorted { left, right in
            if left.status != right.status {
                return left.status == .validatedWorking
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func matchedKeywords(for channel: IPTVChannel) -> [String] {
        let haystack = [
            channel.name,
            channel.group ?? "",
            channel.tvgId ?? "",
            channel.sourceSummary
        ]
        .joined(separator: " ")
        .lowercased()

        return interestingKeywords.filter { haystack.contains($0) }
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
    let downloadSucceeded: Bool
    let errorMessage: String?
}

private struct ChannelValidationOutcome: Sendable {
    let channel: IPTVChannel
    let isReachable: Bool
    let statusCode: Int?
    let errorMessage: String?

    var validatedChannel: IPTVChannel? {
        isReachable ? channel : nil
    }
}

private struct ParsedChannelMetadata: Sendable {
    let name: String
    let tvgId: String?
    let group: String?
    let logoURL: URL?
    let httpUserAgent: String?
}

private struct ValidationResult: Sendable {
    let method: String
    let statusCode: Int?
    let contentType: String?
    let isAccepted: Bool
    let errorMessage: String?

    var failureDescription: String? {
        if let errorMessage, !errorMessage.isEmpty {
            return "\(method) \(errorMessage)"
        }

        if let statusCode {
            if let contentType, !contentType.isEmpty {
                return "\(method) HTTP \(statusCode) (\(contentType))"
            }

            return "\(method) HTTP \(statusCode)"
        }

        return nil
    }
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
