import Foundation

struct DragonSnapshotRecord<Response: Codable>: Codable {
    let metadata: DragonCachedResponseMetadata
    let value: Response
}

enum DragonSnapshotCacheKey {
    case home
    case articles(limit: Int)
    case articleDetail(id: String)
    case books(limit: Int, offset: Int, query: String?)
    case movies(limit: Int)
    case youTube(source: String, section: String?, limit: Int, offset: Int, query: String?)
    case youTubeVideos(section: String, limit: Int, offset: Int)
    case youTubeSections

    var identifier: String {
        switch self {
        case .home:
            return "home"
        case .articles(let limit):
            return "articles_limit_\(limit)"
        case .articleDetail(let id):
            return "article_detail_\(id)"
        case .books(let limit, let offset, let query):
            return "books_limit_\(limit)_offset_\(offset)_query_\(queryIdentifier(query))"
        case .movies(let limit):
            return "movies_limit_\(limit)"
        case .youTube(let source, let section, let limit, let offset, let query):
            return "youtube_source_\(source)_section_\(sectionIdentifier(section))_limit_\(limit)_offset_\(offset)_query_\(queryIdentifier(query))"
        case .youTubeVideos(let section, let limit, let offset):
            return "youtube_videos_section_\(section)_limit_\(limit)_offset_\(offset)"
        case .youTubeSections:
            return "youtube_sections"
        }
    }

    var fileName: String {
        "\(sanitizedIdentifier).json"
    }

    var metadataURL: URL {
        URL(string: "dragon://snapshot-cache/\(sanitizedIdentifier)")!
    }

    private var sanitizedIdentifier: String {
        identifier
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .reduce(into: "") { result, character in
                if character == "_" && result.last == "_" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func queryIdentifier(_ query: String?) -> String {
        normalizedIdentifier(query) ?? "none"
    }

    private func sectionIdentifier(_ section: String?) -> String {
        normalizedIdentifier(section) ?? "all"
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

actor DragonSnapshotStore {
    static let shared = DragonSnapshotStore()

    private let storeVersion = 1
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save<Response: Codable>(_ value: Response, for key: DragonSnapshotCacheKey) {
        do {
            let metadata = DragonCachedResponseMetadata(
                url: key.metadataURL.absoluteString,
                cachedAt: Date(),
                cacheVersion: storeVersion
            )
            let record = DragonSnapshotRecord(metadata: metadata, value: value)
            let data = try encoder.encode(record)
            let directoryURL = try storeDirectoryURL()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: directoryURL.appendingPathComponent(key.fileName), options: [.atomic])
        } catch {
#if DEBUG
            print("Dragon snapshot store save failed for \(key.identifier): \(error)")
#endif
        }
    }

    func load<Response: Codable>(_ responseType: Response.Type, for key: DragonSnapshotCacheKey) -> DragonAPIFetchResult<Response>? {
        do {
            let data = try Data(contentsOf: try storeDirectoryURL(createIfNeeded: false).appendingPathComponent(key.fileName))
            let record = try decoder.decode(DragonSnapshotRecord<Response>.self, from: data)
            return DragonAPIFetchResult(value: record.value, source: .cache(record.metadata), resolvedURL: key.metadataURL)
        } catch {
            return nil
        }
    }

    private func storeDirectoryURL(createIfNeeded: Bool = true) throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        return baseDirectory.appendingPathComponent("DragonSnapshotStore", isDirectory: true)
    }
}
