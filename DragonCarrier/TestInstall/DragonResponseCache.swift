import CryptoKit
import Foundation

struct DragonCachedResponseMetadata: Codable, Sendable {
    let url: String
    let cachedAt: Date
    let cacheVersion: Int

    private enum CodingKeys: String, CodingKey {
        case url
        case cachedAt = "cached_at"
        case cacheVersion = "cache_version"
    }
}

struct DragonCachedResponseRecord: Codable, Sendable {
    let metadata: DragonCachedResponseMetadata
    let payloadBase64: String

    private enum CodingKeys: String, CodingKey {
        case metadata
        case payloadBase64 = "payload_base64"
    }
}

struct DragonCachedResponse: Sendable {
    let data: Data
    let metadata: DragonCachedResponseMetadata
}

enum DragonResponseSource: Sendable {
    case network
    case cache(DragonCachedResponseMetadata)
    case snapshot
    case remoteSnapshot
    case cachedSnapshot(DragonCachedResponseMetadata)
    case bundledSnapshot

    var cachedMetadata: DragonCachedResponseMetadata? {
        switch self {
        case .cache(let metadata), .cachedSnapshot(let metadata):
            return metadata
        case .network, .snapshot, .remoteSnapshot, .bundledSnapshot:
            return nil
        }
    }

    var statusMessage: String? {
        switch self {
        case .network:
            return nil
        case .cache:
            return "Showing cached data."
        case .snapshot:
            return "Loaded from snapshot."
        case .remoteSnapshot:
            return "Loaded from remote Dragon snapshot."
        case .cachedSnapshot:
            return "Loaded from cached Dragon snapshot."
        case .bundledSnapshot:
            return "Loaded from bundled Dragon snapshot."
        }
    }
}

struct DragonAPIFetchResult<Response> {
    let value: Response
    let source: DragonResponseSource
    let resolvedURL: URL
}

actor DragonResponseCache {
    static let shared = DragonResponseCache()

    private let cacheVersion = 1
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(data: Data, for url: URL) {
        do {
            let metadata = DragonCachedResponseMetadata(
                url: url.absoluteString,
                cachedAt: Date(),
                cacheVersion: cacheVersion
            )
            let record = DragonCachedResponseRecord(
                metadata: metadata,
                payloadBase64: data.base64EncodedString()
            )
            let encodedRecord = try encoder.encode(record)

            let directoryURL = try cacheDirectoryURL()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try encodedRecord.write(to: cacheFileURL(for: url, directoryURL: directoryURL), options: [.atomic])
        } catch {
            return
        }
    }

    func load(for url: URL) -> DragonCachedResponse? {
        do {
            let recordData = try Data(contentsOf: cacheFileURL(for: url))
            let record = try decoder.decode(DragonCachedResponseRecord.self, from: recordData)
            guard let payloadData = Data(base64Encoded: record.payloadBase64) else {
                return nil
            }
            return DragonCachedResponse(data: payloadData, metadata: record.metadata)
        } catch {
            return nil
        }
    }

    func cacheItemCount() throws -> Int {
        let directoryURL = try cacheDirectoryURL(createIfNeeded: false)
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.filter { $0.pathExtension.lowercased() == "json" }.count
    }

    func cacheSizeBytes() throws -> Int64 {
        let directoryURL = try cacheDirectoryURL(createIfNeeded: false)
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0
        for url in urls where url.pathExtension.lowercased() == "json" {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func clearAll() throws {
        let directoryURL = try cacheDirectoryURL(createIfNeeded: false)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension.lowercased() == "json" {
            try fileManager.removeItem(at: url)
        }
    }

    private func cacheDirectoryURL(createIfNeeded: Bool = true) throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        return baseDirectory.appendingPathComponent("DragonResponseCache", isDirectory: true)
    }

    private func cacheFileURL(for url: URL, directoryURL: URL? = nil) throws -> URL {
        let baseDirectory = try directoryURL ?? cacheDirectoryURL(createIfNeeded: true)
        return baseDirectory.appendingPathComponent(cacheFileName(for: url), isDirectory: false)
    }

    private func cacheFileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).json"
    }
}
