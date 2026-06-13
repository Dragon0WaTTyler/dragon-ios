import Foundation

enum DragonDataSourceFactory {
    #if DEBUG
    static let useMockDataSource = false
    static let simulateRemoteFailure = false
    static let useNativeBooksDataSource = false
    #endif

    static let cachedRemoteDataSource: DragonDataSource = DragonCachedDataSource(remote: DragonRemoteDataSource.shared)
    static let mockDataSource: DragonDataSource = MockDragonDataSource()

    static var defaultDataSource: DragonDataSource {
        #if DEBUG
        if useMockDataSource {
            return mockDataSource
        }
        if simulateRemoteFailure {
            return DragonCachedDataSource(remote: DragonDebugFailingDataSource())
        }
        if useNativeBooksDataSource {
            return DragonNativeBooksDataSource(
                fallback: DragonCachedDataSource(remote: DragonRemoteDataSource.shared)
            )
        }
        #endif

        return cachedRemoteDataSource
    }
}
