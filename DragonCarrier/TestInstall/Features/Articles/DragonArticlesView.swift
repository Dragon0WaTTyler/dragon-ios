import Foundation
import SwiftUI

struct DragonArticlesView: View {
    @StateObject private var viewModel: ArticlesViewModel
    @State private var searchText = ""
    private let detailDataSource: DragonDataSource

    init(dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource) {
        self.detailDataSource = dataSource
        _viewModel = StateObject(
            wrappedValue: ArticlesViewModel(
                dataSource: DragonDefaultArticlesDataSource(),
                detailDataSource: dataSource
            )
        )
    }

    init(viewModel: ArticlesViewModel) {
        self.detailDataSource = viewModel.detailDataSource
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

                        if viewModel.response != nil || viewModel.isLoading || viewModel.refreshErrorText != nil {
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
                                            ArticleDetailView(article: article, dataSource: detailDataSource)
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
        let rowDirection = DragonTextDirection.forText([article.title, article.source, article.excerpt].joined(separator: " "))

        HStack(alignment: .top, spacing: 14) {
            ArticleThumbnailView(url: article.displayImageURL)

            VStack(alignment: rowDirection.horizontalAlignment, spacing: 8) {
                Text(article.title.isEmpty ? "Untitled article" : article.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .environment(\.layoutDirection, DragonTextDirection.forText(article.title).layoutDirection)
                    .multilineTextAlignment(DragonTextDirection.forText(article.title).alignment)

                HStack(spacing: 8) {
                    if !article.source.isEmpty {
                        Text(article.source)
                            .font(.caption)
                            .foregroundStyle(DragonTheme.red)
                            .lineLimit(1)
                            .environment(\.layoutDirection, DragonTextDirection.forText(article.source).layoutDirection)
                            .multilineTextAlignment(DragonTextDirection.forText(article.source).alignment)
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
                        .environment(\.layoutDirection, DragonTextDirection.forText(article.excerpt).layoutDirection)
                        .multilineTextAlignment(DragonTextDirection.forText(article.excerpt).alignment)
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
    @StateObject private var viewModel: ArticleDetailViewModel
    @Environment(\.openURL) private var openURL

    init(article: DragonArticle, dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(article: article, dataSource: dataSource))
    }

    private var articleURL: URL? {
        let text = viewModel.originalURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var detailDirection: DragonTextDirection {
        DragonTextDirection.forText([viewModel.title, viewModel.source, viewModel.displayBodyText].joined(separator: " "))
    }

    private var titleDirection: DragonTextDirection {
        DragonTextDirection.forText(viewModel.title)
    }

    private var sourceDirection: DragonTextDirection {
        DragonTextDirection.forText(viewModel.source)
    }

    var body: some View {
        contentView
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var contentView: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: detailDirection.horizontalAlignment, spacing: 18) {
                    articleImageView
                    articleHeaderView
                    articleDatesView
                    articleLoadingView
                    articleErrorView
                    articleBodyView
                    articleStatusView
                    articleURLView
                    openOriginalButton
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
    }

    @ViewBuilder
    private var articleImageView: some View {
        if let articleImageURL = viewModel.imageURL {
            ArticleHeroImageView(url: articleImageURL)
        }
    }

    private var articleHeaderView: some View {
        VStack(alignment: detailDirection.horizontalAlignment, spacing: 8) {
            Text(viewModel.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .environment(\.layoutDirection, titleDirection.layoutDirection)
                .multilineTextAlignment(titleDirection.alignment)

            if !viewModel.source.isEmpty {
                Text(viewModel.source)
                    .font(.headline)
                    .foregroundStyle(DragonTheme.red)
                    .environment(\.layoutDirection, sourceDirection.layoutDirection)
                    .multilineTextAlignment(sourceDirection.alignment)
            }
        }
    }

    private var articleDatesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let publishedDateText = viewModel.article.publishedDisplayText {
                Text("Published")
                    .font(.caption)
                    .foregroundStyle(.gray)

                Text(publishedDateText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white)
            }

            if !viewModel.savedAt.isEmpty {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.gray)

                Text(viewModel.savedAt)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var articleLoadingView: some View {
        if viewModel.isLoading {
            ArticleDetailLoadingCard()
        }
    }

    @ViewBuilder
    private var articleErrorView: some View {
        if let errorMessage = viewModel.errorMessage {
            ArticleDetailMessageCard(
                title: "Showing saved article preview",
                message: errorMessage
            )
        }
    }

    private var articleBodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.article.status.isEmpty || !viewModel.article.read_state.isEmpty {
                Text("State")
                    .font(.caption)
                    .foregroundStyle(.gray)

                Text([viewModel.article.status, viewModel.article.read_state]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.white)
            }

            Text(viewModel.hasCachedBody ? "Reader" : "Excerpt")
                .font(.caption)
                .foregroundStyle(.gray)

            ForEach(Array(viewModel.displayParagraphs.enumerated()), id: \.offset) { _, paragraph in
                let paragraphDirection = DragonTextDirection.forText(paragraph)
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: paragraphDirection.frameAlignment)
                    .environment(\.layoutDirection, paragraphDirection.layoutDirection)
                    .multilineTextAlignment(paragraphDirection.alignment)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var articleStatusView: some View {
        if !viewModel.fulltextStatusLabel.isEmpty || !viewModel.fulltextStatusMessage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.fulltextStatusLabel.isEmpty {
                    Text(viewModel.fulltextStatusLabel)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                if !viewModel.fulltextStatusMessage.isEmpty {
                    Text(viewModel.fulltextStatusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineSpacing(4)
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

    private var articleURLView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original URL")
                .font(.caption)
                .foregroundStyle(.gray)

            Text(viewModel.originalURL.isEmpty ? "Unavailable" : viewModel.originalURL)
                .font(.footnote.monospaced())
                .foregroundStyle(articleURL == nil ? .gray : .white)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var openOriginalButton: some View {
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
}

private struct ArticleDetailLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(DragonTheme.red)

            Text("Loading cached article details...")
                .font(.footnote)
                .foregroundStyle(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ArticleDetailMessageCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ArticleThumbnailView: View {
    let url: URL?

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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "newspaper.fill")
                .font(.title3)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

private struct ArticleHeroImageView: View {
    let url: URL?

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
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.45)
            Image(systemName: "newspaper.fill")
                .font(.title)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

private extension DragonArticle {
    var displayImageURL: URL? {
        DragonArticle.sanitizedURL(thumbnail) ?? DragonArticle.sanitizedURL(image)
    }

    private static func sanitizedURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum DragonTextDirection {
    case leftToRight
    case rightToLeft

    static func forText(_ value: String) -> DragonTextDirection {
        value.isLikelyRTL ? .rightToLeft : .leftToRight
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .leftToRight:
            return .leftToRight
        case .rightToLeft:
            return .rightToLeft
        }
    }

    var alignment: TextAlignment {
        switch self {
        case .leftToRight:
            return .leading
        case .rightToLeft:
            return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leftToRight:
            return .leading
        case .rightToLeft:
            return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leftToRight:
            return .leading
        case .rightToLeft:
            return .trailing
        }
    }
}

private extension String {
    var isLikelyRTL: Bool {
        let scalars = unicodeScalars
        var rtlCount = 0
        var latinCount = 0
        var letterCount = 0

        for scalar in scalars {
            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
            }

            if scalar.isArabicScript {
                rtlCount += 1
                continue
            }

            if scalar.isLatinScript {
                latinCount += 1
            }
        }

        guard rtlCount > 0, letterCount > 0 else {
            return false
        }

        if latinCount == 0 {
            return rtlCount >= max(2, letterCount / 4)
        }

        return rtlCount >= latinCount || rtlCount >= max(2, letterCount / 3)
    }
}

private extension UnicodeScalar {
    var isArabicScript: Bool {
        switch value {
        case 0x0600...0x06FF,
             0x0750...0x077F,
             0x08A0...0x08FF,
             0xFB50...0xFDFF,
             0xFE70...0xFEFF:
            return true
        default:
            return false
        }
    }

    var isLatinScript: Bool {
        switch value {
        case 0x0041...0x005A,
             0x0061...0x007A,
             0x00C0...0x00D6,
             0x00D8...0x00F6,
             0x00F8...0x00FF:
            return true
        default:
            return false
        }
    }
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
        ArticleDetailView(
            article: DragonArticlesResponse.preview.items[0],
            dataSource: MockDragonDataSource()
        )
    }
}
