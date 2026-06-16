import Foundation

struct DragonFetchedCoreSnapshot {
    let snapshot: DragonCoreSnapshot
    let data: Data
    let url: URL
}

enum DragonRemoteSnapshotClientError: LocalizedError {
    case invalidHTTPResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Remote Dragon snapshot returned an invalid response."
        case .httpStatus(let statusCode):
            return "Remote Dragon snapshot returned HTTP \(statusCode)."
        }
    }
}

final class DragonRemoteSnapshotClient {
    static let defaultSnapshotURL = URL(
        string: "https://raw.githubusercontent.com/Dragon0WaTTyler/dragon-dashboard/main/exports/dragon_core_snapshot.json"
    )!

    private let session: URLSession
    private let snapshotURL: URL

    init(
        session: URLSession = .shared,
        snapshotURL: URL = DragonRemoteSnapshotClient.defaultSnapshotURL
    ) {
        self.session = session
        self.snapshotURL = snapshotURL
    }

    func fetchSnapshot() async throws -> DragonFetchedCoreSnapshot {
        var request = URLRequest(
            url: snapshotURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.httpShouldHandleCookies = false

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonRemoteSnapshotClientError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonRemoteSnapshotClientError.httpStatus(httpResponse.statusCode)
        }

        let snapshot = try DragonCoreSnapshotValidator.validate(data: data, sourceURL: snapshotURL)
        return DragonFetchedCoreSnapshot(snapshot: snapshot, data: data, url: snapshotURL)
    }
}
