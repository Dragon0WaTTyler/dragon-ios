import SwiftUI

struct MovieDetailView: View {
    let movie: DragonMovie

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        MoviePosterView(url: movie.posterURL, size: CGSize(width: 108, height: 162))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(movie.title.isEmpty ? "Untitled movie" : movie.title)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)

                            if !movie.year.isEmpty {
                                Text(movie.year)
                                    .font(.headline)
                                    .foregroundStyle(DragonTheme.red)
                            }

                            let badges = [movie.status, movie.score, movie.type].filter { !$0.isEmpty }
                            if !badges.isEmpty {
                                Text(badges.joined(separator: " • "))
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }

                    InfoBlock(title: "Status", value: movie.status)
                    InfoBlock(title: "Score", value: movie.score)
                    if !movie.director.isEmpty {
                        InfoBlock(title: "Director", value: movie.director)
                    }
                    if !movie.genres.isEmpty {
                        InfoBlock(title: "Genres", value: movie.genresText)
                    }
                    if !movie.tmdb_id.isEmpty {
                        InfoBlock(title: "TMDB ID", value: movie.tmdb_id)
                    }
                    InfoBlock(title: "Overview", value: movie.overview.isEmpty ? "No overview available." : movie.overview)
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("Movie")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MoviePosterView: View {
    let url: URL?
    let size: CGSize

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(DragonTheme.red)
        }
    }
}
