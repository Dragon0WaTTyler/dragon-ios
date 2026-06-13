import SwiftUI

struct DragonArticlesView: View {
    @StateObject private var viewModel: ArticlesViewModel
    @State private var searchText = ""

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

                        if viewModel.response != nil {
                            DragonRefreshStatusView(
                                lastUpdatedAt: viewModel.lastUpdatedAt,
                                isRefreshing: viewModel.isLoading,
                                errorText: viewModel.refreshErrorText,
                                statusText: viewModel.statusText
                            )
                        }

                        switch viewModel.state {
                        case .idle:
                            ArticleProgressView()

                        case .loading where viewModel.articles.isEmpty:
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
                                title: "No articles available.",
                                message: "Pull to refresh to check again.",
                                buttonTitle: "Reload"
                            ) {
                                await viewModel.loadArticles()
                            }

                        case .loaded, .loading:
                            if filteredArticles.isEmpty {
                                if viewModel.articles.isEmpty {
                                    ArticleStateCard(
                                        title: "No articles available.",
                                        message: "Pull to refresh to check again.",
                                        buttonTitle: "Reload"
                                    ) {
                                        await viewModel.loadArticles()
                                    }
                                } else {
                                    NoMatchesView()
                                }
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(filteredArticles) { article in
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
                    }
                    .padding(24)
                    .padding(.bottom, 90)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search articles")
        .refreshable {
            await viewModel.loadArticles()
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadArticles()
            }
        }
    }

    private var filteredArticles: [DragonArticle] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return viewModel.articles
        }

        return viewModel.articles.filter { article in
            [
                article.title,
                article.source,
                article.excerpt,
                article.url
            ].contains { normalizedSearchText($0).contains(query) }
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct NoMatchesView: View {
    var body: some View {
        Text("No matches found.")
            .font(.footnote)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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
