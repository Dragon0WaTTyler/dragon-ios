import SwiftUI

struct DragonMoviesView: View {
    @State private var movies: [DragonMovie] = []
    @State private var isLoading = false
    @State private var errorText = ""
    @State private var lastUpdatedAt: Date?

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Movies")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("Lightweight cinema snapshot")
                                    .font(.headline)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await loadMovies()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(DragonTheme.card)
                                    .clipShape(Circle())
                            }
                        }

                        if isLoading || !movies.isEmpty || lastUpdatedAt != nil {
                            DragonRefreshStatusView(
                                lastUpdatedAt: lastUpdatedAt,
                                isRefreshing: isLoading,
                                errorText: movies.isEmpty ? nil : errorText
                            )
                        }

                        if isLoading && movies.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ProgressView()
                                    .tint(DragonTheme.red)

                                Text("Loading movies...")
                                    .foregroundStyle(.gray)
                                    .font(.footnote)
                            }
                        }

                        if movies.isEmpty && !isLoading && errorText.isEmpty {
                            MoviesStateCard(
                                title: "No movies found.",
                                message: "Pull to refresh to check again.",
                                buttonTitle: "Reload"
                            ) {
                                await loadMovies()
                            }
                        }

                        if !errorText.isEmpty && movies.isEmpty {
                            MoviesStateCard(
                                title: "Could not load movies",
                                message: errorText,
                                buttonTitle: "Try Again"
                            ) {
                                await loadMovies()
                            }
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(movies) { movie in
                                NavigationLink {
                                    MovieDetailView(movie: movie)
                                } label: {
                                    MovieRow(movie: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 90)
                }
            }
        }
        .refreshable {
            await loadMovies()
        }
        .task {
            await loadMovies()
        }
    }

    @MainActor
    private func loadMovies() async {
        isLoading = true

        do {
            let response = try await DragonAPIClient.shared.fetchMovies(limit: 20)

            if response.ok {
                movies = response.items
                lastUpdatedAt = Date()
                errorText = ""
            } else {
                handleFailure("Backend returned an error.")
            }
        } catch {
            handleFailure(dragonUserFacingMessage(for: error))
        }

        isLoading = false
    }

    private func handleFailure(_ message: String) {
        errorText = message
    }
}

struct MoviesStateCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)

            Button {
                Task {
                    await action()
                }
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DragonTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct MovieRow: View {
    let movie: DragonMovie

    private var posterURL: URL? {
        let trimmed = movie.poster.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: trimmed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let posterURL {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_):
                            placeholderPoster
                        case .empty:
                            placeholderPoster
                        @unknown default:
                            placeholderPoster
                        }
                    }
                } else {
                    placeholderPoster
                }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(movie.title.isEmpty ? "Untitled movie" : movie.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !movie.year.isEmpty {
                        Text(movie.year)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !movie.status.isEmpty {
                        Text(movie.status)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !movie.score.isEmpty {
                        Text(movie.score)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !movie.type.isEmpty {
                        Text(movie.type)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                if !movie.overview.isEmpty {
                    Text(movie.overview)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var placeholderPoster: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(DragonTheme.red)
        }
    }
}
