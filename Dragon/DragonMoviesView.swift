import SwiftUI

struct DragonMoviesView: View {
    @StateObject private var viewModel: DragonMoviesViewModel
    @State private var selectedMovie: DragonMovie?

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: DragonMoviesViewModel())
    }

    init(viewModel: DragonMoviesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        DragonMoviesHomeHeader(
                            countLabel: viewModel.catalogCountLabel,
                            isRefreshing: viewModel.isLoading,
                            onRefresh: loadMovies
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        if viewModel.isLoading || viewModel.lastUpdatedAt != nil || !viewModel.errorText.isEmpty {
                            DragonMoviesStatusStrip(viewModel: viewModel)
                                .padding(.horizontal, 20)
                        }

                        content

                        if viewModel.isLoadingMore && viewModel.hasVisibleContent {
                            DragonLoadingMoreFooter(progressLabel: viewModel.progressLabel)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 96)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedMovie) { movie in
            NavigationStack {
                MovieDetailView(movie: movie)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        .refreshable {
            await viewModel.loadMovies()
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadMovies()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = viewModel.state, !viewModel.hasVisibleContent {
            DragonMoviesStateCard(
                title: "Could not load movies",
                message: message,
                buttonTitle: "Try Again",
                action: loadMovies
            )
            .padding(.horizontal, 20)
        } else if case .empty = viewModel.state {
            DragonMoviesStateCard(
                title: "No movies found",
                message: "Dragon returned an empty movie library for now.",
                buttonTitle: "Refresh",
                action: loadMovies
            )
            .padding(.horizontal, 20)
        } else if !viewModel.hasVisibleContent && isIdleOrLoading {
            DragonMoviesLoadingView()
        } else {
            if let featuredMovie = viewModel.featuredMovie {
                DragonStreamingHero(
                    movie: featuredMovie,
                    progressLabel: viewModel.progressLabel,
                    onDetails: { selectedMovie = featuredMovie },
                    onRefresh: loadMovies
                )
                .padding(.horizontal, 12)
            }

            ForEach(viewModel.rails) { rail in
                DragonMovieRail(
                    rail: rail,
                    onSelectMovie: { movie in
                        selectedMovie = movie
                    }
                )
            }
        }
    }

    private var isIdleOrLoading: Bool {
        switch viewModel.state {
        case .idle, .loading:
            return true
        case .loadingMore, .loaded, .empty, .failed, .partialLoaded:
            return false
        }
    }

    private func loadMovies() {
        Task {
            await viewModel.loadMovies()
        }
    }
}

private struct DragonMoviesHomeHeader: View {
    let countLabel: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("DRAGON")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(DragonTheme.red)
                    .tracking(1.4)

                Spacer()

                Text(countLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DragonTheme.card)
                    .clipShape(Capsule())

                Button(action: onRefresh) {
                    ZStack {
                        Circle()
                            .fill(DragonTheme.card)
                            .frame(width: 42, height: 42)

                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Movies")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("A native streaming home for your Dragon catalog.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 18) {
                DragonHeaderNavLabel(title: "Home", isSelected: true)
                DragonHeaderNavLabel(title: "Movies", isSelected: true)
                DragonHeaderNavLabel(title: "Library", isSelected: false)
            }
        }
    }
}

private struct DragonHeaderNavLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.52))

            Capsule()
                .fill(isSelected ? Color.white : Color.clear)
                .frame(width: isSelected ? 28 : 0, height: 2)
        }
    }
}

private struct DragonMoviesStatusStrip: View {
    @ObservedObject var viewModel: DragonMoviesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(viewModel.progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(DragonTheme.red)
                }

                Spacer()

                if viewModel.fetchedPageCount > 0 {
                    Text("\(viewModel.fetchedPageCount) page\(viewModel.fetchedPageCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Text(lastUpdatedLabel)
                .font(.caption)
                .foregroundStyle(.gray)

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(3)
            }

            if !viewModel.errorText.isEmpty {
                Text(viewModel.errorText)
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt = viewModel.lastUpdatedAt else {
            return "Last updated: Never"
        }

        return "Last updated: \(Self.formatter.string(from: lastUpdatedAt))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

private struct DragonStreamingHero: View {
    let movie: DragonMovie
    let progressLabel: String
    let onDetails: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            DragonStreamingHeroArtwork(movie: movie)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Featured")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.42))
                        .clipShape(Capsule())

                    Spacer()

                    Text(progressLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.42))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text(movie.displayTitle)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    DragonHeroMetadataRow(movie: movie)

                    if !movie.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(movie.overview)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(4)
                            .lineSpacing(4)
                    }

                    HStack(spacing: 12) {
                        Button(action: onDetails) {
                            Label("Details", systemImage: "info.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DragonHeroPrimaryButtonStyle())

                        Button(action: onRefresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DragonHeroSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct DragonStreamingHeroArtwork: View {
    let movie: DragonMovie

    var body: some View {
        Group {
            if let url = movie.primaryArtworkURL {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.02, blue: 0.03),
                    Color(red: 0.03, green: 0.03, blue: 0.04),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DragonTheme.red.opacity(0.42),
                    Color(red: 0.03, green: 0.03, blue: 0.04),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "film.stack.fill")
                .font(.system(size: 58))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct DragonHeroMetadataRow: View {
    let movie: DragonMovie

    private var metadata: [String] {
        var items = [
            movie.year,
            movie.score,
            movie.status,
            movie.type
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !movie.genres.isEmpty {
            items.append(movie.genres.prefix(2).joined(separator: ", "))
        }

        if let runtime = movie.runtime?.trimmingCharacters(in: .whitespacesAndNewlines), !runtime.isEmpty {
            items.append(runtime)
        }

        return items
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(metadata, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct DragonMovieRail: View {
    let rail: DragonMoviesViewModel.Rail
    let onSelectMovie: (DragonMovie) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rail.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    if let subtitle = rail.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(rail.movies.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(rail.movies) { movie in
                        DragonMoviePosterCard(movie: movie) {
                            onSelectMovie(movie)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct DragonMoviePosterCard: View {
    let movie: DragonMovie
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    MoviePosterView(url: movie.posterURL ?? movie.primaryArtworkURL, size: CGSize(width: 148, height: 222))
                        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 8)

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let badge = badgeText {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.76))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var badgeText: String? {
        if let progressText = movie.progressDisplayText {
            return progressText
        }

        let trimmedStatus = movie.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedStatus.isEmpty ? nil : trimmedStatus
    }

    private var secondaryText: String {
        let values = [
            movie.year,
            movie.score,
            movie.type
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.isEmpty ? "Dragon library" : values.joined(separator: " • ")
    }
}

private struct DragonMoviesLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(DragonTheme.card)
                .frame(height: 540)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 120, height: 28)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.14))
                            .frame(maxWidth: 260, minHeight: 44, maxHeight: 44)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 58)
                    }
                    .padding(22)
                }
                .padding(.horizontal, 12)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 180, height: 22)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(DragonTheme.card)
                                    .frame(width: 148, height: 268)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .shimmeringIfAvailable()
    }
}

private struct DragonMoviesStateCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)

            Button(action: action) {
                Label(buttonTitle, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DragonHeroPrimaryButtonStyle())
        }
        .padding(20)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct DragonLoadingMoreFooter: View {
    let progressLabel: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(DragonTheme.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Loading more movies")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DragonHeroPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private struct DragonHeroSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.black.opacity(configuration.isPressed ? 0.46 : 0.32))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func shimmeringIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self
                .phaseAnimator([false, true]) { view, isBright in
                    view.opacity(isBright ? 0.94 : 0.72)
                } animation: { _ in
                    .easeInOut(duration: 1.0)
                }
        } else {
            self
        }
    }
}
