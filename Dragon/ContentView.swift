import Foundation
import Combine
import SwiftUI

// MARK: - App Root

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

// MARK: - Home

@MainActor
final class HomeViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var response: DragonHomeResponse?

    private let client: DragonHomeFetching

    init(
        client: DragonHomeFetching = DragonAPIClient.shared,
        initialState: State = .idle,
        initialResponse: DragonHomeResponse? = nil
    ) {
        self.client = client
        self.state = initialState
        self.response = initialResponse
    }

    var sections: [DragonSection] {
        response?.sections ?? []
    }

    var appName: String {
        response?.app_name ?? "Dragon"
    }

    var serverTimeText: String {
        guard let serverTime = response?.server_time, !serverTime.isEmpty else {
            return "Waiting for backend"
        }

        return "Server time \(serverTime)"
    }

    var errorText: String {
        if case .failed(let message) = state {
            return message
        }
        return ""
    }

    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    func loadHome() async {
        state = .loading

        do {
            let response = try await client.fetchHome()
            guard response.ok else {
                state = .failed("Dragon API responded but ok=false")
                return
            }

            self.response = response
            state = .loaded
        } catch {
            state = .failed("Could not load /api/v1/home: \(error.localizedDescription)")
        }
    }
}

private extension DragonHomeResponse {
    static let preview = DragonHomeResponse(
        app_name: "Dragon",
        api_version: "v1",
        ok: true,
        server_time: "2026-06-12T12:00:00Z",
        sections: [
            DragonSection(
                api_path: "/api/v1/movies",
                key: "movies",
                label: "Movies",
                status: "available",
                count: 4,
                href: "/api/v1/movies"
            ),
            DragonSection(
                api_path: "/api/v1/youtube/sections",
                key: "youtube",
                label: "YouTube",
                status: "available",
                count: 3,
                href: "/api/v1/youtube/sections"
            ),
            DragonSection(
                api_path: "/api/v1/articles",
                key: "articles",
                label: "Articles",
                status: "available",
                count: 2,
                href: "/api/v1/articles"
            ),
            DragonSection(
                api_path: "/api/v1/books",
                key: "books",
                label: "Books",
                status: "unknown",
                count: nil,
                href: "/api/v1/books"
            ),
            DragonSection(
                api_path: "/api/v1/chess/home",
                key: "chess",
                label: "Chess",
                status: "available",
                count: 1,
                href: "/api/v1/chess/home"
            ),
        ],
        service: "dragon"
    )
}

struct DragonHomeView: View {
    @StateObject private var viewModel: HomeViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: HomeViewModel())
    }

    init(viewModel: HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.appName)
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Native home from /api/v1/home")
                                .font(.headline)
                                .foregroundStyle(.gray)

                            Text(viewModel.serverTimeText)
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Button {
                            Task {
                                await viewModel.loadHome()
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

                    if viewModel.isLoading && viewModel.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading Dragon home...")
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }

                    if !viewModel.errorText.isEmpty {
                        Text(viewModel.errorText)
                            .font(.footnote)
                            .foregroundStyle(DragonTheme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DragonTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(spacing: 12) {
                        if viewModel.sections.isEmpty && !viewModel.isLoading {
                            HomeCard(
                                title: "No data yet",
                                subtitle: "Tap refresh to load Dragon API",
                                value: "—",
                                detail: nil
                            )
                        } else {
                            ForEach(viewModel.sections) { section in
                                HomeCard(
                                    title: section.label,
                                    subtitle: "Status: \(section.statusDisplayText)",
                                    value: section.displayCount,
                                    detail: section.api_path
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadHome()
            }
        }
    }
}

// MARK: - Articles

struct DragonArticlesView: View {
    @StateObject private var viewModel: ArticlesViewModel

    init() {
        _viewModel = StateObject(wrappedValue: ArticlesViewModel())
    }

    init(viewModel: ArticlesViewModel) {
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
                                Text("Articles")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("Latest lightweight reading snapshot")
                                    .font(.headline)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await viewModel.loadArticles()
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

                        switch viewModel.state {
                        case .idle, .loading where viewModel.articles.isEmpty:
                            ArticleProgressView()

                        case .failed(let message):
                            ArticleStateCard(
                                title: "Could not load articles",
                                message: message,
                                buttonTitle: "Try Again"
                            ) {
                                await viewModel.loadArticles()
                            }

                        case .empty:
                            ArticleStateCard(
                                title: "No articles yet",
                                message: "The backend responded successfully, but there are no articles to show right now.",
                                buttonTitle: "Reload"
                            ) {
                                await viewModel.loadArticles()
                            }

                        case .loaded, .loading:
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.articles) { article in
                                    NavigationLink {
                                        ArticleDetailView(article: article)
                                    } label: {
                                        ArticleRow(article: article)
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
        .refreshable {
            await viewModel.loadArticles()
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadArticles()
            }
        }
    }
}

struct ArticleRow: View {
    let article: DragonArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title.isEmpty ? "Untitled article" : article.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 8) {
                if !article.source.isEmpty {
                    Text(article.source)
                        .font(.caption)
                        .foregroundStyle(DragonTheme.red)
                        .lineLimit(1)
                }

                if let publishedDateText = article.publishedDisplayText {
                    Text(publishedDateText)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            if !article.excerpt.isEmpty {
                Text(article.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
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
}

struct ArticleProgressView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .tint(DragonTheme.red)

            Text("Loading articles...")
                .foregroundStyle(.gray)
                .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ArticleStateCard: View {
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

struct ArticleDetailView: View {
    let article: DragonArticle
    @Environment(\.openURL) private var openURL

    private var articleURL: URL? {
        let text = article.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(article.title.isEmpty ? "Untitled article" : article.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    if !article.source.isEmpty {
                        Text(article.source)
                            .font(.headline)
                            .foregroundStyle(DragonTheme.red)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let publishedDateText = article.publishedDisplayText {
                            Text("Published")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            Text(publishedDateText)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.white)
                        }

                        if !article.saved_at.isEmpty {
                            Text("Saved")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            Text(article.saved_at)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DragonTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 10) {
                        if !article.status.isEmpty || !article.read_state.isEmpty {
                            Text("State")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            Text([article.status, article.read_state]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.white)
                        }

                        Text("Excerpt")
                            .font(.caption)
                            .foregroundStyle(.gray)

                        Text(article.excerpt.isEmpty ? "No excerpt available." : article.excerpt)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DragonTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Original URL")
                            .font(.caption)
                            .foregroundStyle(.gray)

                        Text(article.url.isEmpty ? "Unavailable" : article.url)
                            .font(.footnote.monospaced())
                            .foregroundStyle(articleURL == nil ? .gray : .white)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DragonTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    Button {
                        if let articleURL {
                            openURL(articleURL)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                            Text(articleURL == nil ? "Original Unavailable" : "Open Original")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(articleURL == nil ? DragonTheme.card : DragonTheme.red)
                        .foregroundStyle(articleURL == nil ? .gray : .white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(DragonTheme.red.opacity(articleURL == nil ? 0.3 : 0.0), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(articleURL == nil)
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension DragonArticle {
    var publishedDisplayText: String? {
        let rawValue = published_at.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return nil
        }

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: rawValue) {
            return DragonArticle.displayFormatter.string(from: date)
        }

        parser.formatOptions = [.withInternetDateTime]
        if let date = parser.date(from: rawValue) {
            return DragonArticle.displayFormatter.string(from: date)
        }

        return rawValue
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

// MARK: - Books

struct DragonBooksView: View {
    @State private var books: [DragonBook] = []
    @State private var isLoading = false
    @State private var errorText = ""

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Books")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Lightweight reading snapshot")
                                .font(.headline)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Button {
                            Task {
                                await loadBooks()
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

                    if isLoading && books.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading books...")
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(DragonTheme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DragonTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(books) { book in
                            BookRow(book: book)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .task {
            await loadBooks()
        }
    }

    @MainActor
    private func loadBooks() async {
        isLoading = true
        errorText = ""

        do {
            let response = try await DragonAPIClient.shared.fetchBooks(limit: 20)

            if response.ok {
                books = response.items
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/books: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

struct BookRow: View {
    let book: DragonBook

    private var authorsText: String {
        let joined = book.authors.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            return joined
        }
        return book.author.isEmpty ? "Unknown author" : book.author
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let coverURL = URL(string: book.cover.trimmingCharacters(in: .whitespacesAndNewlines)), !book.cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_):
                            placeholderCover
                        case .empty:
                            placeholderCover
                        @unknown default:
                            placeholderCover
                        }
                    }
                } else {
                    placeholderCover
                }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title.isEmpty ? "Untitled book" : book.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(authorsText)
                    .font(.subheadline)
                    .foregroundStyle(DragonTheme.red)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !book.year.isEmpty {
                        Text(book.year)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !book.status.isEmpty {
                        Text(book.status)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if !book.score.isEmpty {
                        Text(book.score)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                if !book.excerpt.isEmpty {
                    Text(book.excerpt)
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

    private var placeholderCover: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

// MARK: - Movies

struct DragonMoviesView: View {
    @State private var movies: [DragonMovie] = []
    @State private var isLoading = false
    @State private var errorText = ""

    var body: some View {
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

                    if isLoading && movies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading movies...")
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(DragonTheme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DragonTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(movies) { movie in
                            MovieRow(movie: movie)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .task {
            await loadMovies()
        }
    }

    @MainActor
    private func loadMovies() async {
        isLoading = true
        errorText = ""

        do {
            let response = try await DragonAPIClient.shared.fetchMovies(limit: 20)

            if response.ok {
                movies = response.items
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/movies: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - YouTube

struct DragonYouTubeView: View {
    @State private var videos: [DragonYouTubeVideo] = []
    @State private var sections: [DragonYouTubeSection] = []
    @State private var selectedMode: DragonYouTubeMode = .watchLater
    @State private var selectedSectionKey: String?
    @State private var isLoading = false
    @State private var isLoadingSections = false
    @State private var errorText = ""
    @State private var didLoadSections = false

    private let limit = 20

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YouTube")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Lightweight video snapshot")
                                .font(.headline)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Button {
                            Task {
                                await refreshCurrentBrowser()
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

                    Picker("YouTube Mode", selection: $selectedMode) {
                        Text("Watch Later").tag(DragonYouTubeMode.watchLater)
                        Text("PocketTube").tag(DragonYouTubeMode.pocketTube)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMode) { _, newValue in
                        Task {
                            await handleModeChange(newValue)
                        }
                    }

                    if selectedMode == .pocketTube {
                        if isLoadingSections && sections.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(DragonTheme.red)
                                Text("Loading sections...")
                                    .foregroundStyle(.gray)
                                    .font(.footnote)
                            }
                        } else if !pocketTubeSections.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(pocketTubeSections) { section in
                                        Button {
                                            selectedSectionKey = section.key
                                            Task {
                                                await loadVideos()
                                            }
                                        } label: {
                                            Text(section.label)
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(isSelectedSection(section) ? .white : .gray)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(isSelectedSection(section) ? DragonTheme.red : DragonTheme.card)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 999)
                                                        .stroke(DragonTheme.red.opacity(isSelectedSection(section) ? 0.0 : 0.35), lineWidth: 1)
                                                )
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if isLoading && videos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading videos...")
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(DragonTheme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DragonTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if videos.isEmpty && !isLoading && errorText.isEmpty {
                        Text(emptyStateText)
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DragonTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(videos) { video in
                            YouTubeVideoRow(video: video)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .task {
            await initializeYouTubeBrowser()
        }
    }

    @MainActor
    private func refreshCurrentBrowser() async {
        if selectedMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: true)
        }
        await loadVideos()
    }

    private var emptyStateText: String {
        switch selectedMode {
        case .watchLater:
            return "Watch Later has no videos right now."
        case .pocketTube:
            let sectionName = currentSectionLabel ?? "this section"
            return "\(sectionName) has no videos right now."
        }
    }

    private var currentSectionLabel: String? {
        guard let selectedSectionKey else {
            return nil
        }
        return sections.first(where: { $0.key == selectedSectionKey })?.label
    }

    private func isSelectedSection(_ section: DragonYouTubeSection) -> Bool {
        selectedSectionKey == section.key
    }

    private var pocketTubeSections: [DragonYouTubeSection] {
        sections.filter { $0.key.lowercased() != "watchlater" }
    }

    private var preferredPocketTubeSectionKey: String? {
        pocketTubeSections.first?.key
    }

    @MainActor
    private func initializeYouTubeBrowser() async {
        if selectedMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
        }
        await loadVideos()
    }

    @MainActor
    private func handleModeChange(_ newMode: DragonYouTubeMode) async {
        if newMode == .pocketTube {
            await loadSectionsIfNeeded(forceReload: false)
            if selectedSectionKey == nil {
                selectedSectionKey = preferredPocketTubeSectionKey
            }
        }
        await loadVideos()
    }

    @MainActor
    private func loadSectionsIfNeeded(forceReload: Bool) async {
        if isLoadingSections && !forceReload {
            return
        }

        if didLoadSections && !forceReload && !sections.isEmpty {
            return
        }

        isLoadingSections = true
        errorText = ""

        do {
            let response = try await DragonAPIClient.shared.fetchYouTubeSections()
            if response.ok {
                sections = response.sections.sorted { left, right in
                    if left.key == "watchlater" {
                        return true
                    }
                    if right.key == "watchlater" {
                        return false
                    }
                    return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
                }
                didLoadSections = true
                let selectedKey = selectedSectionKey ?? ""
                if selectedKey.isEmpty || !sections.contains(where: { $0.key == selectedKey }) || selectedKey.lowercased() == "watchlater" {
                    selectedSectionKey = preferredPocketTubeSectionKey
                }
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/youtube/sections: \(error.localizedDescription)"
        }

        isLoadingSections = false
    }

    @MainActor
    private func loadVideos() async {
        isLoading = true
        errorText = ""

        do {
            let response: DragonYouTubeResponse
            switch selectedMode {
            case .watchLater:
                response = try await DragonAPIClient.shared.fetchYouTubeVideos(source: "watchlater", limit: limit)
            case .pocketTube:
                if sections.isEmpty {
                    await loadSectionsIfNeeded(forceReload: false)
                }
                response = try await DragonAPIClient.shared.fetchYouTubeVideos(
                    source: "pockettube",
                    section: selectedSectionKey,
                    limit: limit
                )
            }

            if response.ok {
                videos = response.items
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/youtube: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

enum DragonYouTubeMode: String, CaseIterable, Identifiable {
    case watchLater
    case pocketTube

    var id: String { rawValue }
}

struct YouTubeVideoRow: View {
    let video: DragonYouTubeVideo
    @Environment(\.openURL) private var openURL

    private var thumbnailURL: URL? {
        let trimmed = video.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: trimmed)
    }

    private var videoURL: URL? {
        let trimmed = video.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private var tagsText: String {
        [video.section, video.group, video.playlist].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private var channelInitial: String? {
        let trimmed = video.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return nil
        }
        return String(first).uppercased()
    }

    private var subtitleText: String {
        let channel = video.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadataParts = [video.published_at, video.saved_at].filter { !$0.isEmpty }
        let metadata = metadataParts.isEmpty ? video.duration.trimmingCharacters(in: .whitespacesAndNewlines) : metadataParts.joined(separator: " • ")

        switch (channel.isEmpty, metadata.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return channel
        case (true, false):
            return metadata
        case (false, false):
            return "\(channel) • \(metadata)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure(_):
                                placeholderThumbnail
                            case .empty:
                                placeholderThumbnail
                            @unknown default:
                                placeholderThumbnail
                            }
                        }
                    } else {
                        placeholderThumbnail
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !video.duration.isEmpty {
                    Text(video.duration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                channelAvatar

                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title.isEmpty ? "Untitled video" : video.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                    }

                    if !tagsText.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tagsText.split(separator: "•").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DragonTheme.red.opacity(0.92))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DragonTheme.red.opacity(0.09))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let videoURL {
                                openURL(videoURL)
                            }
                        } label: {
                            Label(videoURL == nil ? "Unavailable" : "Open in YouTube", systemImage: "safari")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(videoURL == nil ? .gray : .white)
                        }
                        .disabled(videoURL == nil)

                        if videoURL != nil {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.gray.opacity(0.7))
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "ellipsis.vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray.opacity(0.8))
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var channelAvatar: some View {
        ZStack {
            Circle()
                .fill(DragonTheme.red.opacity(0.18))

            if let channelInitial {
                Text(channelInitial)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var placeholderThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.55))
            Image(systemName: "play.rectangle")
                .font(.title3)
                .foregroundStyle(DragonTheme.red.opacity(0.9))
        }
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

// MARK: - Placeholder Sections

struct PlaceholderSectionView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.gray)

                Text("V0 placeholder. API connection comes next.")
                    .font(.caption)
                    .foregroundStyle(DragonTheme.red)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Cards

struct HomeCard: View {
    let title: String
    let subtitle: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(DragonTheme.red.opacity(0.9))
                }
            }

            Spacer()

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DragonTheme.red)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Settings

struct DragonSettingsView: View {
    @State private var backendURLDraft = currentDragonBackendBaseURL()
    @State private var statusText = "Not checked yet"
    @State private var detailText = "No API response yet"
    @State private var backendURLError = ""
    @State private var isChecking = false

    private var backendBaseURL: String {
        DragonAPIClient.shared.backendBaseURL
    }

    private var healthURL: String {
        "\(backendBaseURL)/api/v1/health"
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text("Dragon connection")
                    .font(.headline)
                    .foregroundStyle(.gray)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Backend URL")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    TextField("http://127.0.0.1:5000", text: $backendURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if !backendURLError.isEmpty {
                        Text(backendURLError)
                            .font(.caption)
                            .foregroundStyle(DragonTheme.red)
                    }

                    Text("Health endpoint")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    Text(healthURL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)

                    Text("Saved backend")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    Text(backendBaseURL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)

                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(statusText.contains("Online") ? .green : DragonTheme.red)

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DragonTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    saveBackendURL()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Backend URL")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DragonTheme.card)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DragonTheme.red, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    checkBackend()
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isChecking ? "Checking..." : "Check Dragon API")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DragonTheme.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(isChecking)

                Spacer()
            }
            .padding(24)
            .task {
                backendURLDraft = backendBaseURL
            }
        }
    }

    private func saveBackendURL() {
        guard let normalized = saveDragonBackendBaseURL(backendURLDraft) else {
            backendURLError = "Enter a valid http:// or https:// URL"
            return
        }

        backendURLError = ""
        backendURLDraft = normalized
        statusText = "Saved"
        detailText = "Backend URL updated"
    }

    private func checkBackend() {
        guard let url = URL(string: healthURL) else {
            statusText = "Invalid backend URL"
            detailText = healthURL
            return
        }

        isChecking = true
        statusText = "Checking..."
        detailText = "Calling \(healthURL)"

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isChecking = false

                if let error = error {
                    statusText = "Offline"
                    detailText = error.localizedDescription
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    statusText = "Unknown response"
                    detailText = "No HTTP response received"
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    statusText = "API error: HTTP \(httpResponse.statusCode)"
                    detailText = "Health endpoint returned a non-success status"
                    return
                }

                guard let data = data else {
                    statusText = "Online"
                    detailText = "HTTP \(httpResponse.statusCode), empty body"
                    return
                }

                do {
                    let payload = try JSONDecoder().decode(DragonHealthResponse.self, from: data)

                    if payload.ok {
                        statusText = "Online: \(payload.service)"
                        detailText = "API \(payload.api_version) · HTTP \(httpResponse.statusCode)"
                    } else {
                        statusText = "API responded but not OK"
                        detailText = "HTTP \(httpResponse.statusCode)"
                    }
                } catch {
                    statusText = "Online: HTTP \(httpResponse.statusCode)"
                    detailText = "Response was not decoded as health JSON"
                }
            }
        }.resume()
    }
}
#Preview {
    DragonHomeView(
        viewModel: HomeViewModel(
            initialState: .loaded,
            initialResponse: .preview
        )
    )
}

#Preview("Articles") {
    DragonArticlesView(
        viewModel: ArticlesViewModel(
            initialState: .loaded,
            initialResponse: .preview
        )
    )
}

#Preview("Article Detail") {
    NavigationStack {
        ArticleDetailView(article: DragonArticlesResponse.preview.items[0])
    }
}
