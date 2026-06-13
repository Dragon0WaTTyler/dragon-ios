import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DragonHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            DragonArticlesView()
                .tabItem {
                    Label("Articles", systemImage: "newspaper.fill")
                }

            DragonBooksView()
                .tabItem {
                    Label("Books", systemImage: "book.closed.fill")
                }

            DragonYouTubeView()
                .tabItem {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                }

            DragonMoviesView()
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
