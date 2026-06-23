import Foundation

enum DragonDataSourceFactory {
    #if DEBUG
    static let useMockDataSource = false
    static let simulateRemoteFailure = false
    static let useBundledSnapshotDataSource = false
    static let useRemoteSnapshotDataSource = false
    static let useNativeBooksDataSource = false
    #endif

    static let cachedRemoteDataSource: DragonDataSource = DragonCachedDataSource(remote: DragonRemoteDataSource.shared)
    static let nativeYouTubeDataSource: DragonDataSource = DragonNativeYouTubeDataSource(
        fallback: cachedRemoteDataSource
    )
    static let bundledSnapshotDataSource: DragonDataSource = DragonBundledSnapshotDataSource.shared
    static let remoteSnapshotDataSource: DragonDataSource = DragonRemoteSnapshotDataSource.shared
    static let mockDataSource: DragonDataSource = MockDragonDataSource()

    static var defaultDataSource: DragonDataSource {
        #if DEBUG
        if useMockDataSource {
            return mockDataSource
        }
        if simulateRemoteFailure {
            return DragonCachedDataSource(remote: DragonDebugFailingDataSource())
        }
        if useRemoteSnapshotDataSource {
            return remoteSnapshotDataSource
        }
        if useBundledSnapshotDataSource {
            return bundledSnapshotDataSource
        }
        if useNativeBooksDataSource {
            return DragonNativeBooksDataSource(
                fallback: DragonCachedDataSource(remote: DragonRemoteDataSource.shared)
            )
        }
        #endif

        return nativeYouTubeDataSource
    }
}
