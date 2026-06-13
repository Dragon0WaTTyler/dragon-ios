import Foundation

enum DragonDataSourceFactory {
    #if DEBUG
    static let useMockDataSource = false
    #endif

    static let remoteDataSource: DragonDataSource = DragonRemoteDataSource.shared
    static let mockDataSource: DragonDataSource = MockDragonDataSource()

    static var defaultDataSource: DragonDataSource {
        #if DEBUG
        if useMockDataSource {
            return mockDataSource
        }
        #endif

        return remoteDataSource
    }
}
