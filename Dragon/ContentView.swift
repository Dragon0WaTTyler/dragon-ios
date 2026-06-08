import SwiftUI

private let dragonBackendBaseURLDefaultsKey = "dragon.backendBaseURL"
private let dragonDefaultBackendBaseURL = "http://127.0.0.1:5050"

private func normalizeDragonBackendBaseURL(_ rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    guard normalized.hasPrefix("http://") || normalized.hasPrefix("https://") else {
        return nil
    }
    guard URL(string: normalized) != nil else {
        return nil
    }

    return normalized
}

private func currentDragonBackendBaseURL() -> String {
    let storedValue = UserDefaults.standard.string(forKey: dragonBackendBaseURLDefaultsKey) ?? ""
    return normalizeDragonBackendBaseURL(storedValue) ?? dragonDefaultBackendBaseURL
}

@discardableResult
private func saveDragonBackendBaseURL(_ rawValue: String) -> String? {
    guard let normalized = normalizeDragonBackendBaseURL(rawValue) else {
        return nil
    }

    UserDefaults.standard.set(normalized, forKey: dragonBackendBaseURLDefaultsKey)
    return normalized
}

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

struct DragonHomeView: View {
    @State private var sections: [DragonSection] = []
    @State private var isLoading = false
    @State private var errorText = ""

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dragon")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Personal Knowledge & Media OS")
                                .font(.headline)
                                .foregroundStyle(.gray)
                        }

                        Spacer()

                        Button {
                            Task {
                                await loadHome()
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

                    if isLoading && sections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView()
                                .tint(DragonTheme.red)

                            Text("Loading Dragon home...")
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

                    VStack(spacing: 12) {
                        if sections.isEmpty && !isLoading {
                            HomeCard(
                                title: "No data yet",
                                subtitle: "Tap refresh to load Dragon API",
                                value: "—"
                            )
                        } else {
                            ForEach(sections) { section in
                                HomeCard(
                                    title: section.label,
                                    subtitle: section.status == "available" ? "Available in Dragon" : "Status unknown",
                                    value: section.displayCount
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
            await loadHome()
        }
    }

    @MainActor
    private func loadHome() async {
        isLoading = true
        errorText = ""

        do {
            let response = try await DragonAPIClient.shared.fetchHome()

            if response.ok {
                sections = response.sections
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/home: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Articles

struct DragonArticlesView: View {
    @State private var articles: [DragonArticle] = []
    @State private var isLoading = false
    @State private var errorText = ""

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
                                    await loadArticles()
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

                        if isLoading && articles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ProgressView()
                                    .tint(DragonTheme.red)

                                Text("Loading articles...")
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
                            ForEach(articles) { article in
                                NavigationLink {
                                    ArticleDetailView(article: article)
                                } label: {
                                    ArticleRow(article: article)
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
        .task {
            await loadArticles()
        }
    }

    @MainActor
    private func loadArticles() async {
        isLoading = true
        errorText = ""

        do {
            let response = try await DragonAPIClient.shared.fetchArticles(limit: 20)

            if response.ok {
                articles = response.items
            } else {
                errorText = "Dragon API responded but ok=false"
            }
        } catch {
            errorText = "Could not load /api/v1/articles: \(error.localizedDescription)"
        }

        isLoading = false
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

                if !article.published_at.isEmpty {
                    Text(article.published_at)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            if !article.excerpt.isEmpty {
                Text(article.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(3)
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
                        if !article.published_at.isEmpty {
                            Text("Published")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            Text(article.published_at)
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

    private var metadataText: String {
        [video.duration, video.published_at, video.saved_at].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private var tagsText: String {
        [video.section, video.group, video.playlist].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
                )

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

            VStack(alignment: .leading, spacing: 8) {
                Text(video.title.isEmpty ? "Untitled video" : video.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if !video.channel.isEmpty {
                    Text(video.channel)
                        .font(.subheadline)
                        .foregroundStyle(DragonTheme.red)
                        .lineLimit(1)
                }

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }

                if !tagsText.isEmpty {
                    Text(tagsText)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
            }

            HStack {
                Button {
                    if let videoURL {
                        openURL(videoURL)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text(videoURL == nil ? "Unavailable" : "Open in YouTube")
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                    .foregroundStyle(videoURL == nil ? .gray : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(videoURL == nil ? DragonTheme.card : DragonTheme.red)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DragonTheme.red.opacity(videoURL == nil ? 0.3 : 0.0), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(videoURL == nil)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var placeholderThumbnail: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "play.rectangle")
                .font(.title2)
                .foregroundStyle(DragonTheme.red)
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

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
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

                    TextField("http://127.0.0.1:5050", text: $backendURLDraft)
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

// MARK: - API Client

final class DragonAPIClient {
    static let shared = DragonAPIClient()

    var backendBaseURL: String {
        currentDragonBackendBaseURL()
    }

    private init() {}

    private func endpointURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: backendBaseURL) else {
            return nil
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    func fetchHome() async throws -> DragonHomeResponse {
        guard let url = endpointURL(path: "/api/v1/home") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonHomeResponse.self, from: data)
    }

    func fetchArticles(limit: Int = 20) async throws -> DragonArticlesResponse {
        guard let url = endpointURL(path: "/api/v1/articles?limit=\(limit)") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonArticlesResponse.self, from: data)
    }

    func fetchBooks(limit: Int = 20) async throws -> DragonBooksResponse {
        guard let url = endpointURL(path: "/api/v1/books?limit=\(limit)") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonBooksResponse.self, from: data)
    }

    func fetchMovies(limit: Int = 20) async throws -> DragonMoviesResponse {
        guard let url = endpointURL(path: "/api/v1/movies?limit=\(limit)") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonMoviesResponse.self, from: data)
    }

    func fetchYouTubeVideos(source: String = "all", section: String? = nil, limit: Int = 20) async throws -> DragonYouTubeResponse {
        var queryItems = [URLQueryItem(name: "source", value: source), URLQueryItem(name: "limit", value: String(limit))]
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "section", value: section))
        }

        guard let url = endpointURL(path: "/api/v1/youtube", queryItems: queryItems) else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonYouTubeResponse.self, from: data)
    }

    func fetchYouTubeSections() async throws -> DragonYouTubeSectionsResponse {
        guard let url = endpointURL(path: "/api/v1/youtube/sections") else {
            throw DragonAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DragonAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DragonAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DragonYouTubeSectionsResponse.self, from: data)
    }
}

enum DragonAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid backend response"
        case .httpStatus(let statusCode):
            return "HTTP \(statusCode)"
        }
    }
}

// MARK: - API Models

struct DragonHealthResponse: Decodable {
    let api_version: String
    let ok: Bool
    let service: String
}

struct DragonHomeResponse: Decodable {
    let api_version: String
    let ok: Bool
    let sections: [DragonSection]
    let service: String
}

struct DragonSection: Decodable, Identifiable {
    let key: String
    let label: String
    let status: String
    let count: Int?

    var id: String {
        key
    }

    var displayCount: String {
        guard let count else {
            return "—"
        }

        return String(count)
    }
}

struct DragonArticlesResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonArticle]
    let count: Int
}

struct DragonArticle: Decodable, Identifiable {
    let id: String
    let title: String
    let source: String
    let url: String
    let published_at: String
    let saved_at: String
    let excerpt: String
}

struct DragonBooksResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonBook]
    let count: Int
}

struct DragonBook: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let authors: [String]
    let cover: String
    let year: String
    let status: String
    let score: String
    let excerpt: String
}

struct DragonMoviesResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonMovie]
    let count: Int
}

struct DragonMovie: Decodable, Identifiable {
    let id: String
    let title: String
    let year: String
    let poster: String
    let status: String
    let score: String
    let type: String
    let overview: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case poster
        case status
        case score
        case type
        case overview
    }

    init(id: String, title: String, year: String, poster: String, status: String, score: String, type: String, overview: String) {
        self.id = id
        self.title = title
        self.year = year
        self.poster = poster
        self.status = status
        self.score = score
        self.type = type
        self.overview = overview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonMovie.decodeString(container, forKey: .id)
        self.title = DragonMovie.decodeString(container, forKey: .title)
        self.year = DragonMovie.decodeString(container, forKey: .year)
        self.poster = DragonMovie.decodeString(container, forKey: .poster)
        self.status = DragonMovie.decodeString(container, forKey: .status)
        self.score = DragonMovie.decodeString(container, forKey: .score)
        self.type = DragonMovie.decodeString(container, forKey: .type)
        self.overview = DragonMovie.decodeString(container, forKey: .overview)
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? container.decode(Double.self, forKey: key) {
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        }

        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return ""
    }
}

struct DragonYouTubeResponse: Decodable {
    let api_version: String
    let ok: Bool
    let items: [DragonYouTubeVideo]
    let count: Int
}

struct DragonYouTubeSectionsResponse: Decodable {
    let api_version: String
    let ok: Bool
    let sections: [DragonYouTubeSection]
}

struct DragonYouTubeSection: Decodable, Identifiable {
    let key: String
    let label: String
    let count: Int

    var id: String {
        key
    }
}

struct DragonYouTubeVideo: Decodable, Identifiable {
    let id: String
    let video_id: String
    let title: String
    let channel: String
    let thumbnail: String
    let url: String
    let published_at: String
    let saved_at: String
    let duration: String
    let section: String
    let group: String
    let playlist: String
    let source: String

    private enum CodingKeys: String, CodingKey {
        case id
        case video_id
        case videoId
        case title
        case channel
        case channel_title
        case thumbnail
        case thumbnail_url
        case url
        case published_at
        case publishedAt
        case saved_at
        case savedAt
        case duration
        case section
        case group
        case playlist
        case playlist_title
        case source
    }

    init(id: String, video_id: String, title: String, channel: String, thumbnail: String, url: String, published_at: String, saved_at: String, duration: String, section: String, group: String, playlist: String, source: String) {
        self.id = id
        self.video_id = video_id
        self.title = title
        self.channel = channel
        self.thumbnail = thumbnail
        self.url = url
        self.published_at = published_at
        self.saved_at = saved_at
        self.duration = duration
        self.section = section
        self.group = group
        self.playlist = playlist
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = DragonYouTubeVideo.decodeString(container, keys: [.id, .video_id, .videoId])
        self.video_id = DragonYouTubeVideo.decodeString(container, keys: [.video_id, .videoId, .id])
        self.title = DragonYouTubeVideo.decodeString(container, keys: [.title], default: "Untitled video")
        self.channel = DragonYouTubeVideo.decodeString(container, keys: [.channel, .channel_title])
        self.thumbnail = DragonYouTubeVideo.decodeString(container, keys: [.thumbnail, .thumbnail_url])
        self.url = DragonYouTubeVideo.decodeString(container, keys: [.url])
        self.published_at = DragonYouTubeVideo.decodeString(container, keys: [.published_at, .publishedAt])
        self.saved_at = DragonYouTubeVideo.decodeString(container, keys: [.saved_at, .savedAt])
        self.duration = DragonYouTubeVideo.decodeString(container, keys: [.duration])
        self.section = DragonYouTubeVideo.decodeString(container, keys: [.section])
        self.group = DragonYouTubeVideo.decodeString(container, keys: [.group])
        self.playlist = DragonYouTubeVideo.decodeString(container, keys: [.playlist, .playlist_title])
        self.source = DragonYouTubeVideo.decodeString(container, keys: [.source], default: "unknown")
    }

    private static func decodeString(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys], default defaultValue: String = "") -> String {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value {
                    return String(Int(value))
                }
                return String(value)
            }
        }

        return defaultValue
    }
}

// MARK: - Theme

enum DragonTheme {
    static let background = Color.black
    static let card = Color(red: 0.045, green: 0.045, blue: 0.05)
    static let red = Color(red: 0.75, green: 0.05, blue: 0.08)
}

#Preview {
    ContentView()
}
