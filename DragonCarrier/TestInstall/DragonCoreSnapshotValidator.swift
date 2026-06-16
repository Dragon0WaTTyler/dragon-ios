import Foundation

enum DragonCoreSnapshotValidationError: LocalizedError {
    case fileTooSmall(Int)
    case invalidJSON
    case invalidRootObject
    case invalidSchemaVersion(String)
    case missingTopLevelKey(String)
    case missingContainer(String)
    case forbiddenKey(String)
    case suspiciousValue(String)
    case undecodableSnapshot

    var errorDescription: String? {
        switch self {
        case .fileTooSmall(let size):
            return "Dragon snapshot is suspiciously small (\(size) bytes)."
        case .invalidJSON:
            return "Dragon snapshot is not valid JSON."
        case .invalidRootObject:
            return "Dragon snapshot root object is invalid."
        case .invalidSchemaVersion(let version):
            return "Dragon snapshot schema version \(version) is not supported."
        case .missingTopLevelKey(let key):
            return "Dragon snapshot is missing \(key)."
        case .missingContainer(let path):
            return "Dragon snapshot is missing \(path)."
        case .forbiddenKey(let keyPath):
            return "Dragon snapshot contains a forbidden key at \(keyPath)."
        case .suspiciousValue(let keyPath):
            return "Dragon snapshot contains a suspicious value at \(keyPath)."
        case .undecodableSnapshot:
            return "Dragon snapshot could not be decoded."
        }
    }
}

enum DragonCoreSnapshotValidator {
    static let schemaVersion = "dragon-core-snapshot.v1"
    static let minimumFileSizeBytes = 5 * 1024

    private static let requiredTopLevelKeys = [
        "schema_version",
        "generated_at",
        "producer",
        "status",
        "home",
        "books",
        "articles",
        "movies",
        "youtube"
    ]

    private static let forbiddenKeyIndicators = [
        "token",
        "secret",
        "oauth",
        "notion_payload",
        "cache_path",
        "local_path",
        "runtime_path",
        "magnet",
        "torrent",
        "session_id",
        "stream_url",
        "playback_url",
        "traceback",
        ".env"
    ]

    private static let suspiciousValueIndicators = [
        "notion_payload",
        "cache_path",
        "local_path",
        "runtime_path",
        "stream_url",
        "playback_url",
        "session_id",
        "x-amz-security-token",
        "x-amz-signature",
        "access_token=",
        "client_secret=",
        "oauth=",
        "token=",
        ".env"
    ]

    static func validate(data: Data, sourceURL: URL? = nil) throws -> DragonCoreSnapshot {
        guard data.count >= minimumFileSizeBytes else {
            throw DragonCoreSnapshotValidationError.fileTooSmall(data.count)
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DragonCoreSnapshotValidationError.invalidJSON
        }

        guard let root = jsonObject as? [String: Any] else {
            throw DragonCoreSnapshotValidationError.invalidRootObject
        }

        for key in requiredTopLevelKeys where root[key] == nil {
            throw DragonCoreSnapshotValidationError.missingTopLevelKey(key)
        }

        let schemaVersionValue = (root["schema_version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard schemaVersionValue == schemaVersion else {
            throw DragonCoreSnapshotValidationError.invalidSchemaVersion(schemaVersionValue)
        }

        try requireListContainer(path: "books.items", root: root, parentKey: "books", childKey: "items")
        try requireListContainer(path: "articles.items", root: root, parentKey: "articles", childKey: "items")
        try requireListContainer(path: "movies.items", root: root, parentKey: "movies", childKey: "items")
        try requireListContainer(path: "youtube.sections", root: root, parentKey: "youtube", childKey: "sections")
        try requireListContainer(path: "youtube.videos", root: root, parentKey: "youtube", childKey: "videos")

        try audit(node: root, path: "snapshot")

        do {
            return try JSONDecoder().decode(DragonCoreSnapshot.self, from: data)
        } catch {
            throw DragonCoreSnapshotValidationError.undecodableSnapshot
        }
    }

    private static func requireListContainer(path: String, root: [String: Any], parentKey: String, childKey: String) throws {
        guard let parent = root[parentKey] as? [String: Any], parent[childKey] is [Any] else {
            throw DragonCoreSnapshotValidationError.missingContainer(path)
        }
    }

    private static func audit(node: Any, path: String) throws {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                let keyPath = "\(path).\(key)"
                let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if forbiddenKeyIndicators.contains(where: { normalizedKey.contains($0) }) {
                    throw DragonCoreSnapshotValidationError.forbiddenKey(keyPath)
                }
                try audit(node: value, path: keyPath)
            }
            return
        }

        if let array = node as? [Any] {
            for (index, value) in array.enumerated() {
                try audit(node: value, path: "\(path)[\(index)]")
            }
            return
        }

        guard let textValue = node as? String else {
            return
        }

        let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if trimmed.isEmpty {
            return
        }

        if lowercased.contains("magnet:?") || lowercased.contains(".torrent") {
            throw DragonCoreSnapshotValidationError.suspiciousValue(path)
        }

        if suspiciousValueIndicators.contains(where: { lowercased.contains($0) }) {
            throw DragonCoreSnapshotValidationError.suspiciousValue(path)
        }

        if lowercased.contains("http://") || lowercased.contains("https://") {
            let tokenizedQueryMarkers = [
                "access_token=",
                "token=",
                "secret=",
                "oauth=",
                "session_id=",
                "client_secret=",
                "x-amz-security-token",
                "x-amz-signature"
            ]
            if tokenizedQueryMarkers.contains(where: { lowercased.contains($0) }) {
                throw DragonCoreSnapshotValidationError.suspiciousValue(path)
            }
        }

        let pathLikePrefixes = [
            "/users/",
            "/home/",
            "/tmp/",
            "/var/",
            "/private/",
            "/etc/",
            "~/"
        ]
        if pathLikePrefixes.contains(where: { lowercased.contains($0) }) || trimmed.hasPrefix("../") || trimmed.hasPrefix("./") {
            throw DragonCoreSnapshotValidationError.suspiciousValue(path)
        }

        if lowercased.contains("traceback (most recent call last):")
            || (trimmed.contains("File \"") && trimmed.contains(", line ")) {
            throw DragonCoreSnapshotValidationError.suspiciousValue(path)
        }

        let credentialPrefixes = ["ghp_", "github_pat_", "ya29.", "AIza"]
        if credentialPrefixes.contains(where: { trimmed.contains($0) }) {
            throw DragonCoreSnapshotValidationError.suspiciousValue(path)
        }
    }
}
