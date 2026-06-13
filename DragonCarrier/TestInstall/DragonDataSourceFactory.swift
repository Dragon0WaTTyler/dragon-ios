import Foundation

enum DragonDataSourceFactory {
    #if DEBUG
    static let useMockDataSource = false
    static let simulateRemoteFailure = false
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
        #endif

        return cachedRemoteDataSource
    }
}
