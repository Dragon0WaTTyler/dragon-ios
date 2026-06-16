import Foundation

struct DragonCoreSnapshotCacheMetadata {
    let fileURL: URL
    let fileExists: Bool
    let fileSize: Int64
    let modifiedDate: Date?

    var cachedResponseMetadata: DragonCachedResponseMetadata {
        DragonCachedResponseMetadata(
            url: fileURL.absoluteString,
            cachedAt: modifiedDate ?? Date(),
            cacheVersion: 1
        )
    }
}

struct DragonStoredCoreSnapshot {
    let snapshot: DragonCoreSnapshot
    let data: Data
    let metadata: DragonCoreSnapshotCacheMetadata
}

final class DragonCoreSnapshotStore {
    static let shared = DragonCoreSnapshotStore()

    private let fileManager: FileManager
    private let snapshotFileName: String
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        snapshotFileName: String = "dragon_core_snapshot.json"
    ) {
        self.fileManager = fileManager
        self.snapshotFileName = snapshotFileName
    }

    func saveSnapshotData(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try DragonCoreSnapshotValidator.validate(data: data)
        let fileURL = try snapshotFileURL(createIfNeeded: true)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    func loadSnapshot() -> DragonStoredCoreSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        do {
            let fileURL = try snapshotFileURL(createIfNeeded: false)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            let snapshot: DragonCoreSnapshot
            do {
                snapshot = try DragonCoreSnapshotValidator.validate(data: data, sourceURL: fileURL)
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }

            let metadata = try metadataForExistingFile(at: fileURL)
            return DragonStoredCoreSnapshot(snapshot: snapshot, data: data, metadata: metadata)
        } catch {
            return nil
        }
    }

    func metadata() -> DragonCoreSnapshotCacheMetadata? {
        lock.lock()
        defer { lock.unlock() }

        do {
            let fileURL = try snapshotFileURL(createIfNeeded: false)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }
            return try metadataForExistingFile(at: fileURL)
        } catch {
            return nil
        }
    }

    func deleteCachedSnapshot() {
        lock.lock()
        defer { lock.unlock() }

        guard let fileURL = try? snapshotFileURL(createIfNeeded: false),
              fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
    }

    private func snapshotFileURL(createIfNeeded: Bool) throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        return baseDirectory
            .appendingPathComponent("DragonCoreSnapshotStore", isDirectory: true)
            .appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    private func metadataForExistingFile(at fileURL: URL) throws -> DragonCoreSnapshotCacheMetadata {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return DragonCoreSnapshotCacheMetadata(
            fileURL: fileURL,
            fileExists: true,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedDate: values.contentModificationDate
        )
    }
}
