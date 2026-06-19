import Foundation

enum DragonBundledSnapshotError: LocalizedError {
    case missingSnapshotFile(String)
    case unreadableSnapshot(URL)
    case invalidSnapshot(URL)

    var errorDescription: String? {
        switch self {
        case .missingSnapshotFile(let name):
            return "Bundled snapshot \(name) is missing."
        case .unreadableSnapshot(let url):
            return "Bundled snapshot could not be read from \(url.lastPathComponent)."
        case .invalidSnapshot(let url):
            return "Bundled snapshot \(url.lastPathComponent) is invalid."
        }
    }
}

final class DragonBundledSnapshotDataSource: DragonDataSource {
    static let shared = DragonBundledSnapshotDataSource()

    struct LoadedSnapshot {
        let snapshot: DragonCoreSnapshot
        let url: URL
    }

    private let responseSource: DragonResponseSource
    private let serviceName: String
    private let snapshotReader: () throws -> LoadedSnapshot
    private let lock = NSLock()
    private var cachedSnapshotResult: Result<LoadedSnapshot, Error>?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        snapshotFileName: String = "dragon_core_snapshot.json"
    ) {
        self.responseSource = .bundledSnapshot
        self.serviceName = "dragon-bundled-snapshot"
        self.snapshotReader = {
            try Self.loadBundledSnapshot(
                bundle: bundle,
                fileManager: fileManager,
                snapshotFileName: snapshotFileName
            )
        }
    }

    init(
        preloadedSnapshot: DragonCoreSnapshot,
        resolvedURL: URL,
        responseSource: DragonResponseSource,
        serviceName: String
    ) {
        self.responseSource = responseSource
        self.serviceName = serviceName
        self.snapshotReader = {
            LoadedSnapshot(snapshot: preloadedSnapshot, url: resolvedURL)
        }
        self.cachedSnapshotResult = .success(LoadedSnapshot(snapshot: preloadedSnapshot, url: resolvedURL))
    }

    func fetchHome() async throws -> DragonAPIFetchResult<DragonHomeResponse> {
        let loadedSnapshot = try loadSnapshot()
        return result(makeHomeResponse(from: loadedSnapshot.snapshot), url: loadedSnapshot.url)
    }

    func fetchArticles(limit: Int) async throws -> DragonAPIFetchResult<DragonArticlesResponse> {
        let loadedSnapshot = try loadSnapshot()
        let items = Array(articleItems(from: loadedSnapshot.snapshot).prefix(max(0, limit)))
        let response = DragonArticlesResponse(
            api_version: "v1",
            ok: true,
            items: items,
            count: items.count
        )
        return result(response, url: loadedSnapshot.url)
    }

    func fetchArticleDetail(id: String) async throws -> DragonAPIFetchResult<DragonArticle> {
        let loadedSnapshot = try loadSnapshot()
        guard let article = articleItems(from: loadedSnapshot.snapshot).first(where: { $0.id == id }) else {
            throw DragonAPIError.httpStatus(404)
        }
        return result(makeSafeArticleDetail(from: article), url: loadedSnapshot.url)
    }

    func fetchBooks(limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonBooksResponse> {
        let loadedSnapshot = try loadSnapshot()
        let filteredBooks = filter(bookItems(from: loadedSnapshot.snapshot), query: query) { book in
            [book.id, book.title, book.author, book.authors.joined(separator: " "), book.year, book.status, book.score, book.excerpt]
        }
        let page = page(filteredBooks, limit: limit, offset: offset)
        let response = DragonBooksResponse(
            api_version: "v1",
            ok: true,
            items: page.items,
            count: page.items.count,
            total: filteredBooks.count,
            limit: max(1, limit),
            offset: max(0, offset),
            has_more: page.hasMore,
            next_offset: page.nextOffset
        )
        return result(response, url: loadedSnapshot.url)
    }

    func fetchMovies(limit: Int) async throws -> DragonAPIFetchResult<DragonMoviesResponse> {
        let loadedSnapshot = try loadSnapshot()
        let items = movieItems(from: loadedSnapshot.snapshot)
        let response = DragonMoviesResponse(api_version: "v1", ok: true, items: items, count: items.count)
        return result(response, url: loadedSnapshot.url)
    }

    func fetchYouTubeVideos(source: String, section: String?, limit: Int, offset: Int, query: String?) async throws -> DragonAPIFetchResult<DragonYouTubeResponse> {
        let loadedSnapshot = try loadSnapshot()
        let filteredBySource = youTubeVideos(from: loadedSnapshot.snapshot).filter { video in
            videoMatchesSource(video, source: source)
        }
        let filteredBySection = filteredBySource.filter { video in
            guard let section = normalizedValue(section) else {
                return true
            }
            return videoMatchesSection(video, section: section)
        }
        let filteredVideos = filter(filteredBySection, query: query) { video in
            [video.title, video.channel, video.section, video.group, video.playlist, video.source]
        }
        return result(makeYouTubeResponse(items: filteredVideos, section: section ?? source, limit: limit, offset: offset), url: loadedSnapshot.url)
    }

    func fetchYouTubeVideos(section: String, limit: Int, offset: Int) async throws -> DragonAPIFetchResult<DragonYouTubeVideosResponse> {
        let loadedSnapshot = try loadSnapshot()
        let filteredVideos = youTubeVideos(from: loadedSnapshot.snapshot).filter { video in
            videoMatchesSection(video, section: section)
        }
        return result(makeYouTubeResponse(items: filteredVideos, section: section, limit: limit, offset: offset), url: loadedSnapshot.url)
    }

    func fetchYouTubeSections() async throws -> DragonAPIFetchResult<DragonYouTubeSectionsResponse> {
        let loadedSnapshot = try loadSnapshot()
        let response = DragonYouTubeSectionsResponse(
            api_version: "v1",
            ok: true,
            sections: makeYouTubeSections(from: loadedSnapshot.snapshot)
        )
        return result(response, url: loadedSnapshot.url)
    }

    private func loadSnapshot() throws -> LoadedSnapshot {
        lock.lock()
        defer { lock.unlock() }

        if let cachedSnapshotResult {
            return try cachedSnapshotResult.get()
        }

        let loadedResult = Result { try readSnapshot() }
        self.cachedSnapshotResult = loadedResult
        return try loadedResult.get()
    }

    private func readSnapshot() throws -> LoadedSnapshot {
        try snapshotReader()
    }

    static func loadBundledSnapshot(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        snapshotFileName: String = "dragon_core_snapshot.json"
    ) throws -> LoadedSnapshot {
        let snapshotURL = try resolveSnapshotURL(
            bundle: bundle,
            fileManager: fileManager,
            snapshotFileName: snapshotFileName
        )

        let data: Data
        do {
            data = try Data(contentsOf: snapshotURL)
        } catch {
            throw DragonBundledSnapshotError.unreadableSnapshot(snapshotURL)
        }

        do {
            let snapshot = try DragonCoreSnapshotValidator.validate(data: data, sourceURL: snapshotURL)
            return LoadedSnapshot(snapshot: snapshot, url: snapshotURL)
        } catch {
            throw DragonBundledSnapshotError.invalidSnapshot(snapshotURL)
        }
    }

    private static func resolveSnapshotURL(
        bundle: Bundle,
        fileManager: FileManager,
        snapshotFileName: String
    ) throws -> URL {
        let snapshotBaseName = URL(fileURLWithPath: snapshotFileName).deletingPathExtension().lastPathComponent
        let snapshotExtension = URL(fileURLWithPath: snapshotFileName).pathExtension
        let directMatches = [
            bundle.url(forResource: snapshotBaseName, withExtension: snapshotExtension),
            bundle.url(forResource: snapshotBaseName, withExtension: snapshotExtension, subdirectory: "Resources")
        ].compactMap { $0 }

        if let snapshotURL = directMatches.first {
            return snapshotURL
        }

        if let resourceURL = bundle.resourceURL,
           let enumerator = fileManager.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent == snapshotFileName {
                return fileURL
            }
        }

        throw DragonBundledSnapshotError.missingSnapshotFile(snapshotFileName)
    }

    private func makeHomeResponse(from snapshot: DragonCoreSnapshot) -> DragonHomeResponse {
        let home = snapshot.home
        let sections = makeHomeSections(from: snapshot, seededSections: home?.sections ?? [])

        return DragonHomeResponse(
            app_name: home?.app_name.nonEmptyValue ?? snapshot.producer?.name.nonEmptyValue ?? "Dragon",
            api_version: home?.api_version.nonEmptyValue ?? "v1",
            ok: home?.ok ?? true,
            server_time: home?.server_time.nonEmptyValue ?? snapshot.generated_at,
            sections: sections,
            service: serviceName
        )
    }

    private func makeHomeSections(from snapshot: DragonCoreSnapshot, seededSections: [DragonSection]) -> [DragonSection] {
        let defaultSections = defaultHomeSections(from: snapshot)
        guard !seededSections.isEmpty else {
            return defaultSections
        }

        var mergedSections: [DragonSection] = []
        var seenKeys = Set<String>()

        for section in seededSections {
            mergedSections.append(mergedHomeSection(section, snapshot: snapshot))
            seenKeys.insert(section.key.lowercased())
        }

        for section in defaultSections where !seenKeys.contains(section.key.lowercased()) {
            mergedSections.append(section)
        }

        return mergedSections
    }

    private func mergedHomeSection(_ section: DragonSection, snapshot: DragonCoreSnapshot) -> DragonSection {
        let defaultSection = defaultHomeSections(from: snapshot).first { $0.key.caseInsensitiveCompare(section.key) == .orderedSame }

        return DragonSection(
            api_path: section.api_path.nonEmptyValue ?? defaultSection?.api_path ?? "/api/v1/\(section.key)",
            key: section.key,
            label: section.label.nonEmptyValue ?? defaultSection?.label ?? section.key.capitalized,
            status: section.status.nonEmptyValue ?? defaultSection?.status ?? "unknown",
            count: section.count ?? defaultSection?.count,
            href: section.href.nonEmptyValue ?? defaultSection?.href ?? "/api/v1/\(section.key)"
        )
    }

    private func defaultHomeSections(from snapshot: DragonCoreSnapshot) -> [DragonSection] {
        [
            DragonSection(
                api_path: "/api/v1/books",
                key: "books",
                label: "Books",
                status: domainStatus(snapshot: snapshot, key: "books", hasData: !(snapshot.books?.items.isEmpty ?? true)),
                count: snapshot.books?.total ?? bookItems(from: snapshot).count,
                href: "/api/v1/books"
            ),
            DragonSection(
                api_path: "/api/v1/articles",
                key: "articles",
                label: "Articles",
                status: domainStatus(snapshot: snapshot, key: "articles", hasData: !(snapshot.articles?.items.isEmpty ?? true)),
                count: snapshot.articles?.total ?? articleItems(from: snapshot).count,
                href: "/api/v1/articles"
            ),
            DragonSection(
                api_path: "/api/v1/movies",
                key: "movies",
                label: "Movies",
                status: domainStatus(snapshot: snapshot, key: "movies", hasData: !(snapshot.movies?.items.isEmpty ?? true)),
                count: snapshot.movies?.total ?? movieItems(from: snapshot).count,
                href: "/api/v1/movies"
            ),
            DragonSection(
                api_path: "/api/v1/youtube/sections",
                key: "youtube",
                label: "YouTube",
                status: domainStatus(snapshot: snapshot, key: "youtube", hasData: !(snapshot.youtube?.videos.isEmpty ?? true) || !(snapshot.youtube?.sections.isEmpty ?? true)),
                count: snapshot.youtube?.videos.count ?? makeYouTubeSections(from: snapshot).count,
                href: "/api/v1/youtube/sections"
            )
        ]
    }

    private func domainStatus(snapshot: DragonCoreSnapshot, key: String, hasData: Bool) -> String {
        if let status = snapshot.status?.status(forDomainKey: key) {
            return status
        }
        return hasData ? "available" : "missing"
    }

    private func makeSafeArticleDetail(from article: DragonArticle) -> DragonArticle {
        DragonArticle(
            id: article.id,
            title: article.title,
            source: article.source,
            url: article.url,
            published_at: article.published_at,
            saved_at: article.saved_at,
            excerpt: article.excerpt,
            image: article.image,
            thumbnail: article.thumbnail,
            status: article.status,
            read_state: article.read_state,
            fulltext_status: DragonArticleFulltextStatus(
                status: "snapshot_preview",
                display_label: "Snapshot preview only",
                display_message: "Full article body is not included in this bundled snapshot. Open original source.",
                next_action: "open_original",
                safe_error: ""
            ),
            content_text: "",
            content_html: ""
        )
    }

    private func makeYouTubeSections(from snapshot: DragonCoreSnapshot) -> [DragonYouTubeSection] {
        let videos = youTubeVideos(from: snapshot)
        let derivedCounts = Dictionary(grouping: videos) { primarySectionKey(for: $0).compactedSnapshotKey }
            .mapValues { $0.count }

        if let seededSections = snapshot.youtube?.sections, !seededSections.isEmpty {
            return seededSections.map { section in
                let key = section.key.nonEmptyValue ?? section.label.nonEmptyValue ?? "unknown"
                let count = derivedCounts[key.compactedSnapshotKey] ?? section.count
                return DragonYouTubeSection(
                    key: key,
                    label: section.label.nonEmptyValue ?? key,
                    count: count
                )
            }
        }

        var seenKeys = Set<String>()
        var sections: [DragonYouTubeSection] = []

        for video in videos {
            let key = primarySectionKey(for: video)
            guard !key.isEmpty else {
                continue
            }

            let normalizedKey = key.compactedSnapshotKey
            guard !seenKeys.contains(normalizedKey) else {
                continue
            }
            seenKeys.insert(normalizedKey)

            sections.append(
                DragonYouTubeSection(
                    key: key,
                    label: video.section.nonEmptyValue ?? video.group.nonEmptyValue ?? video.playlist.nonEmptyValue ?? key,
                    count: derivedCounts[normalizedKey] ?? 0
                )
            )
        }

        return sections
    }

    private func makeYouTubeResponse(items: [DragonYouTubeVideo], section: String, limit: Int, offset: Int) -> DragonYouTubeVideosResponse {
        let page = page(items, limit: limit, offset: offset)
        return DragonYouTubeVideosResponse(
            api_version: "v1",
            ok: true,
            section: section,
            items: page.items,
            count: page.items.count,
            total: items.count,
            limit: max(1, limit),
            offset: max(0, offset),
            has_more: page.hasMore,
            next_offset: page.nextOffset
        )
    }

    private func result<Response>(_ value: Response, url: URL) -> DragonAPIFetchResult<Response> {
        DragonAPIFetchResult(value: value, source: responseSource, resolvedURL: url)
    }

    private func page<Item>(_ items: [Item], limit: Int, offset: Int) -> (items: [Item], hasMore: Bool, nextOffset: Int?) {
        let safeLimit = max(1, limit)
        let safeOffset = min(max(0, offset), items.count)
        let endIndex = min(safeOffset + safeLimit, items.count)
        let pageItems = Array(items[safeOffset..<endIndex])
        let hasMore = endIndex < items.count
        return (pageItems, hasMore, hasMore ? endIndex : nil)
    }

    private func filter<Item>(_ items: [Item], query: String?, fields: (Item) -> [String]) -> [Item] {
        guard let normalizedQuery = normalizedValue(query) else {
            return items
        }

        return items.filter { item in
            fields(item).contains { field in
                field.lowercased().contains(normalizedQuery)
            }
        }
    }

    private func bookItems(from snapshot: DragonCoreSnapshot) -> [DragonBook] {
        snapshot.books?.items ?? []
    }

    private func articleItems(from snapshot: DragonCoreSnapshot) -> [DragonArticle] {
        snapshot.articles?.items ?? []
    }

    private func movieItems(from snapshot: DragonCoreSnapshot) -> [DragonMovie] {
        snapshot.movies?.items ?? []
    }

    private func youTubeVideos(from snapshot: DragonCoreSnapshot) -> [DragonYouTubeVideo] {
        snapshot.youtube?.videos ?? []
    }

    private func videoMatchesSource(_ video: DragonYouTubeVideo, source: String) -> Bool {
        let normalizedSource = normalizedValue(source) ?? "all"
        guard normalizedSource != "all" else {
            return true
        }

        switch videoSourceKind(for: video) {
        case .watchLater:
            return normalizedSource == "watchlater"
        case .pocketTube:
            return normalizedSource == "pockettube"
        case .unknown:
            let videoSource = normalizedValue(video.source)
            return videoSource == normalizedSource
        }
    }

    private func videoMatchesSection(_ video: DragonYouTubeVideo, section: String) -> Bool {
        let normalizedSection = section.compactedSnapshotKey
        if normalizedSection == "watchlater" {
            return videoSourceKind(for: video) == .watchLater
        }

        return candidateSectionTerms(for: video).contains(normalizedSection)
    }

    private func primarySectionKey(for video: DragonYouTubeVideo) -> String {
        video.section.nonEmptyValue
            ?? video.group.nonEmptyValue
            ?? video.playlist.nonEmptyValue
            ?? video.source.nonEmptyValue
            ?? "unknown"
    }

    private func candidateSectionTerms(for video: DragonYouTubeVideo) -> Set<String> {
        Set(
            [video.source, video.section, video.group, video.playlist]
                .compactMap { $0.nonEmptyValue?.compactedSnapshotKey }
        )
    }

    private func candidateVideoSourceTerms(for video: DragonYouTubeVideo) -> Set<String> {
        Set(
            [video.source, video.section, video.group, video.playlist]
                .compactMap { $0.nonEmptyValue?.compactedSnapshotKey }
        )
    }

    private func hasWatchLaterSignal(_ video: DragonYouTubeVideo) -> Bool {
        let terms = candidateVideoSourceTerms(for: video)
        return terms.contains(where: { $0.contains("watchlater") })
    }

    private func hasPocketTubeSignal(_ video: DragonYouTubeVideo) -> Bool {
        let terms = candidateVideoSourceTerms(for: video)
        return terms.contains("pockettube")
            || !candidateSectionTerms(for: video).isEmpty
    }

    private enum YouTubeSnapshotSourceKind {
        case watchLater
        case pocketTube
        case unknown
    }

    private func videoSourceKind(for video: DragonYouTubeVideo) -> YouTubeSnapshotSourceKind {
        if hasWatchLaterSignal(video) {
            return .watchLater
        }

        if hasPocketTubeSignal(video) {
            return .pocketTube
        }

        let hasAnySourceLikeData = [video.source, video.section, video.group, video.playlist]
            .contains { !$0.nonEmptyValue.isNilOrEmpty }
        if !hasAnySourceLikeData {
            return .watchLater
        }

        return .unknown
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var compactedSnapshotKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .some(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none:
            return true
        }
    }
}
