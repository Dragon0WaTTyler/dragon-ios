import SwiftUI

struct ContentView: View {
    private let dataSource: DragonDataSource

    init(dataSource: DragonDataSource = DragonRemoteDataSource.shared) {
        self.dataSource = dataSource
    }

    var body: some View {
        TabView {
            DragonHomeView(dataSource: dataSource)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            DragonArticlesView(dataSource: dataSource)
                .tabItem {
                    Label("Articles", systemImage: "newspaper.fill")
                }

            DragonBooksView(dataSource: dataSource)
                .tabItem {
                    Label("Books", systemImage: "book.closed.fill")
                }

            DragonYouTubeView(dataSource: dataSource)
                .tabItem {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                }

            DragonMoviesView(dataSource: dataSource)
                .tabItem {
                    Label("Movies", systemImage: "film.fill")
                }

            DragonSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(DragonTheme.red)
        .preferredColorScheme(.dark)
    }
}
