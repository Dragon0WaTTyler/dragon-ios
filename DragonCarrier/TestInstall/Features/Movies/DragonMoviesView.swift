import Combine
import SwiftUI

struct DragonMoviesView: View {
    @StateObject private var viewModel: DragonMoviesViewModel
    @State private var searchText = ""

    init(dataSource _: DragonDataSource = DragonDataSourceFactory.defaultDataSource) {
        _viewModel = StateObject(
            wrappedValue: DragonMoviesViewModel(
                dataSource: DragonDefaultMoviesDataSource()
            )
        )
    }

    init(viewModel: DragonMoviesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

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

                                Text("Movie catalog diagnostics")
                                    .font(.headline)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await viewModel.loadMovies()
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

                        if viewModel.isLoading || viewModel.hasVisibleContent || viewModel.lastUpdatedAt != nil || !viewModel.errorText.isEmpty {
                            DragonRefreshStatusView(
                                lastUpdatedAt: viewModel.lastUpdatedAt,
                                isRefreshing: viewModel.isLoading,
                                errorText: viewModel.hasVisibleContent ? viewModel.errorText : nil,
                                statusText: viewModel.statusText
                            )
                        }

                        if viewModel.isLoading && viewModel.movies.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ProgressView()
                                    .tint(DragonTheme.red)

                                Text("Loading movies...")
                                    .foregroundStyle(.gray)
                                    .font(.footnote)
                            }
                        }

                        if !viewModel.errorText.isEmpty && viewModel.movies.isEmpty {
                            MoviesStateCard(
                                title: viewModel.emptyStateTitle,
                                message: viewModel.emptyStateMessage,
                                buttonTitle: viewModel.emptyStateButtonTitle
                            ) {
                                await viewModel.loadMovies()
                            }
                        } else if filteredMovies.isEmpty {
                            if viewModel.movies.isEmpty {
                                MoviesStateCard(
                                    title: viewModel.emptyStateTitle,
                                    message: viewModel.emptyStateMessage,
                                    buttonTitle: viewModel.emptyStateButtonTitle
                                ) {
                                    await viewModel.loadMovies()
                                }
                            } else {
                                NoMatchesView()
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredMovies) { movie in
                                    NavigationLink {
                                        MovieDetailView(movie: movie)
                                    } label: {
                                        MovieRow(movie: movie)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 90)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search movies")
        .refreshable {
            await viewModel.loadMovies()
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadMovies()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: dragonNotionMoviesConfigurationDidChangeNotification)) { _ in
            Task {
                await viewModel.loadMovies()
            }
        }
    }

    private var filteredMovies: [DragonMovie] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return viewModel.movies
        }

        return viewModel.movies.filter { movie in
            [
                movie.title,
                movie.year,
                movie.director,
                movie.genresText,
                movie.status,
                movie.score,
                movie.tmdb_id,
                movie.type,
                movie.overview
            ].contains { normalizedSearchText($0).contains(query) }
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let posterURL = movie.posterURL {
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
