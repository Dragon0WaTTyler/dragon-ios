import Foundation
import SwiftUI
import UIKit
import WebKit

struct DragonArticlesView: View {
    @StateObject private var viewModel: ArticlesViewModel
    @State private var searchText = ""

    init(dataSource: DragonDataSource = DragonDataSourceFactory.defaultDataSource) {
        _ = dataSource
        _viewModel = StateObject(
            wrappedValue: ArticlesViewModel(
                dataSource: DragonDefaultArticlesDataSource()
            )
        )
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
                        headerView

                        if viewModel.response != nil || viewModel.isLoading || viewModel.refreshErrorText != nil {
                            DragonRefreshStatusView(
                                lastUpdatedAt: viewModel.lastUpdatedAt,
                                isRefreshing: viewModel.isLoading,
                                errorText: viewModel.refreshErrorText,
                                statusText: viewModel.statusText
                            )
                        }

                        contentStateView
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await viewModel.refreshOnForegroundIfNeeded()
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Articles")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                Text(headerSubtitleText)
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
    }

    private var headerSubtitleText: String {
        guard viewModel.response != nil || viewModel.refreshErrorText != nil || viewModel.isLoading else {
            return "Last 24 hours, cache-first, native reader"
        }

        let count = viewModel.articles.count
        let articleLabel = count == 1 ? "recent article" : "recent articles"
        return "\(count) \(articleLabel) • Last 24h"
    }

    @ViewBuilder
    private var contentStateView: some View {
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
                title: "No articles in the last 24 hours",
                message: viewModel.refreshErrorText ?? "Pull to refresh and check again when new stories arrive.",
                buttonTitle: "Reload"
            ) {
                await viewModel.loadArticles()
            }

        case .loaded, .loading:
            if filteredArticles.isEmpty {
                if viewModel.articles.isEmpty {
                    ArticleStateCard(
                        title: "No articles in the last 24 hours",
                        message: viewModel.refreshErrorText ?? "Pull to refresh and check again when new stories arrive.",
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

    private var filteredArticles: [DragonArticle] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return viewModel.articles
        }

        return viewModel.articles.filter { article in
            [
                article.displayTitle,
                article.displaySource,
                article.displayExcerpt,
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
        Text("No matches found in the last 24 hours.")
            .font(.footnote)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

struct ArticleRow: View {
    let article: DragonArticle

    private var rowDirection: DragonTextDirection {
        DragonTextDirection.forText([article.displayTitle, article.displaySource, article.displayExcerpt].joined(separator: " "))
    }

    private var indicatorLabels: [String] {
        [article.readIndicatorLabel, article.savedIndicatorLabel].compactMap { $0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ArticleThumbnailView(url: article.resolvedImageURL)

            VStack(alignment: rowDirection.horizontalAlignment, spacing: 10) {
                Text(article.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: rowDirection.frameAlignment)
                    .environment(\.layoutDirection, DragonTextDirection.forText(article.displayTitle).layoutDirection)
                    .multilineTextAlignment(DragonTextDirection.forText(article.displayTitle).alignment)

                HStack(spacing: 8) {
                    if !article.displaySource.isEmpty {
                        Text(article.displaySource)
                            .font(.caption)
                            .foregroundStyle(DragonTheme.red)
                            .lineLimit(1)
                            .environment(\.layoutDirection, DragonTextDirection.forText(article.displaySource).layoutDirection)
                            .multilineTextAlignment(DragonTextDirection.forText(article.displaySource).alignment)
                    }

                    if let publishedDateText = article.publishedRelativeDisplayText {
                        Text(publishedDateText)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: rowDirection.frameAlignment)

                if !article.displayExcerpt.isEmpty {
                    Text(article.displayExcerpt)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: rowDirection.frameAlignment)
                        .environment(\.layoutDirection, DragonTextDirection.forText(article.displayExcerpt).layoutDirection)
                        .multilineTextAlignment(DragonTextDirection.forText(article.displayExcerpt).alignment)
                }

                if !indicatorLabels.isEmpty {
                    ArticleIndicatorRow(labels: indicatorLabels, accentColor: DragonTheme.red)
                        .frame(maxWidth: .infinity, alignment: rowDirection.frameAlignment)
                }
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
    @StateObject private var viewModel: ArticleDetailViewModel
    @Environment(\.openURL) private var openURL

    @AppStorage("dragon.articles.reader.fontSize") private var readerFontSize = 18.0
    @AppStorage("dragon.articles.reader.background") private var readerBackgroundRawValue = DragonReaderBackgroundStyle.dragon.rawValue
    @AppStorage("dragon.articles.reader.direction") private var readerDirectionRawValue = DragonReaderDirectionMode.auto.rawValue
    @State private var isSettingsPresented = false

    init(article: DragonArticle) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(article: article))
    }

    private var articleURL: URL? {
        viewModel.articleURL
    }

    private var readerBackgroundStyle: DragonReaderBackgroundStyle {
        DragonReaderBackgroundStyle(rawValue: readerBackgroundRawValue) ?? .dragon
    }

    private var readerDirectionMode: DragonReaderDirectionMode {
        DragonReaderDirectionMode(rawValue: readerDirectionRawValue) ?? .auto
    }

    private var readerPalette: DragonReaderPalette {
        readerBackgroundStyle.palette
    }

    private var detailTextProbe: String {
        [viewModel.title, viewModel.source, viewModel.displayBodyText].joined(separator: " ")
    }

    private var detailDirection: DragonTextDirection {
        readerDirectionMode.resolvedDirection(for: detailTextProbe)
    }

    private var bodyDirection: DragonTextDirection {
        readerDirectionMode.resolvedDirection(for: detailTextProbe)
    }

    private var titleDirection: DragonTextDirection {
        readerDirectionMode.resolvedDirection(for: viewModel.title)
    }

    private var sourceDirection: DragonTextDirection {
        readerDirectionMode.resolvedDirection(for: viewModel.source)
    }

    private var detailNoticeText: String? {
        viewModel.readerNotice
    }

    var body: some View {
        contentView
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "textformat.size")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                ArticleReaderSettingsView(
                    fontSize: $readerFontSize,
                    backgroundStyleRawValue: $readerBackgroundRawValue,
                    directionModeRawValue: $readerDirectionRawValue
                )
                .presentationDetents([.medium, .large])
            }
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    private var contentView: some View {
        ZStack {
            readerPalette.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: detailDirection.horizontalAlignment, spacing: 18) {
                    articleImageView
                    articleHeaderView
                    articleDatesView
                    articleLoadingView
                    articleVideoView
                    articleNoticeView
                    articleBodyView
                    loadFullArticleButton
                    openOriginalButton
                }
                .padding(24)
                .padding(.bottom, 90)
                .environment(\.layoutDirection, detailDirection.layoutDirection)
                .multilineTextAlignment(detailDirection.alignment)
            }
        }
    }

    private var articleImageView: some View {
        ArticleHeroImageView(url: viewModel.imageURL, palette: readerPalette)
    }

    private var articleHeaderView: some View {
        VStack(alignment: detailDirection.horizontalAlignment, spacing: 10) {
            Text(viewModel.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(readerPalette.primaryText)
                .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
                .environment(\.layoutDirection, titleDirection.layoutDirection)
                .multilineTextAlignment(titleDirection.alignment)

            if !viewModel.source.isEmpty {
                Text(viewModel.source)
                    .font(.headline)
                    .foregroundStyle(DragonTheme.red)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
                    .environment(\.layoutDirection, sourceDirection.layoutDirection)
                    .multilineTextAlignment(sourceDirection.alignment)
            }

            if !viewModel.stateLabels.isEmpty {
                ArticleIndicatorRow(labels: viewModel.stateLabels, accentColor: DragonTheme.red)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
            }
        }
    }

    private var articleDatesView: some View {
        VStack(alignment: detailDirection.horizontalAlignment, spacing: 8) {
            if let publishedDateText = viewModel.article.publishedDisplayText {
                Text("Published")
                    .font(.caption)
                    .foregroundStyle(readerPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)

                Text(publishedDateText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(readerPalette.primaryText)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
            }

            if !viewModel.savedAt.isEmpty {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(readerPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)

                Text(viewModel.savedAt)
                    .font(.footnote.monospaced())
                    .foregroundStyle(readerPalette.primaryText)
                    .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
        .environment(\.layoutDirection, detailDirection.layoutDirection)
        .multilineTextAlignment(detailDirection.alignment)
        .background(readerPalette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(readerPalette.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var articleLoadingView: some View {
        if viewModel.isLoading {
            ArticleDetailLoadingCard(palette: readerPalette)
        }
    }

    @ViewBuilder
    private var articleVideoView: some View {
        if let detectedVideo = viewModel.detectedVideo {
            ArticleDetectedVideoCard(video: detectedVideo, palette: readerPalette)
        }
    }

    @ViewBuilder
    private var articleNoticeView: some View {
        if let detailNoticeText {
            Text(detailNoticeText)
                .font(.footnote)
                .foregroundStyle(readerPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: detailDirection.frameAlignment)
                .environment(\.layoutDirection, detailDirection.layoutDirection)
                .multilineTextAlignment(detailDirection.alignment)
        }
    }

    @ViewBuilder
    private var articleBodyView: some View {
        if viewModel.hasDisplayBody {
            ArticleTextCard(
                title: "Reader",
                paragraphs: viewModel.bodyParagraphs,
                fontSize: readerFontSize,
                direction: bodyDirection,
                palette: readerPalette
            )
        }
    }

    @ViewBuilder
    private var loadFullArticleButton: some View {
        if viewModel.canLoadFullArticle {
            Button {
                Task {
                    await viewModel.loadFullArticle()
                }
            } label: {
                HStack {
                    if viewModel.isFetchingFullArticle {
                        ProgressView()
                            .tint(Color.white)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }

                    Text(viewModel.loadFullArticleButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(readerPalette.cardBackground)
                .foregroundStyle(readerPalette.primaryText)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(readerPalette.borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isFetchingFullArticle)
        }
    }

    private var openOriginalButton: some View {
        Button {
            if let articleURL {
                openURL(articleURL)
            }
        } label: {
            HStack {
                Image(systemName: "safari")
                Text("Open Original")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(articleURL == nil ? readerPalette.cardBackground : DragonTheme.red)
            .foregroundStyle(articleURL == nil ? readerPalette.secondaryText : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(readerPalette.borderColor.opacity(articleURL == nil ? 1 : 0), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(articleURL == nil)
    }
}

private struct ArticleIndicatorRow: View {
    let labels: [String]
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.18))
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
    }
}

private struct ArticleDetailLoadingCard: View {
    let palette: DragonReaderPalette

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(DragonTheme.red)

            Text("Loading article details...")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ArticleDetectedVideoCard: View {
    let video: ArticleEmbeddedVideo
    let palette: DragonReaderPalette

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Video found in article")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)

            ArticleInlineYouTubePlayerWebView(url: video.embedURL)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                openURL(video.watchURL)
            } label: {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                    Text("Open YouTube")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DragonTheme.red)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ArticleTextCard: View {
    let title: String
    let paragraphs: [String]
    let fontSize: Double
    let direction: DragonTextDirection
    let palette: DragonReaderPalette

    var body: some View {
        VStack(alignment: direction.horizontalAlignment, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: direction.frameAlignment)
                .environment(\.layoutDirection, direction.layoutDirection)
                .multilineTextAlignment(direction.alignment)

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontSize))
                        .foregroundStyle(palette.primaryText)
                        .lineSpacing(max(fontSize * 0.2, 4))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: direction.frameAlignment)
                        .environment(\.layoutDirection, direction.layoutDirection)
                        .multilineTextAlignment(direction.alignment)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: direction.frameAlignment)
        .environment(\.layoutDirection, direction.layoutDirection)
        .multilineTextAlignment(direction.alignment)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct ArticleInlineYouTubePlayerWebView: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        var lastLoadedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = Self.embedHTML(for: url)
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        }
    }

    private static func embedHTML(for url: URL) -> String {
        let escapedURL = url.absoluteString
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: #000;
              width: 100%;
              height: 100%;
              overflow: hidden;
            }
            iframe {
              border: 0;
              width: 100%;
              height: 100%;
              background: #000;
            }
          </style>
        </head>
        <body>
          <iframe
            src="\(escapedURL)"
            title="YouTube video player"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen
            playsinline
            referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body>
        </html>
        """
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
    let palette: DragonReaderPalette

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
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.borderColor, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            palette.cardBackground
            VStack(spacing: 10) {
                Image(systemName: "newspaper.fill")
                    .font(.title)
                    .foregroundStyle(DragonTheme.red)

                Text("No image available")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }
}

private struct ArticleReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var backgroundStyleRawValue: String
    @Binding var directionModeRawValue: String
    @Environment(\.dismiss) private var dismiss

    private var selectedBackgroundStyle: DragonReaderBackgroundStyle {
        DragonReaderBackgroundStyle(rawValue: backgroundStyleRawValue) ?? .dragon
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DragonTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsCard(title: "Font Size") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Reader size")
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Text("\(Int(fontSize)) pt")
                                        .foregroundStyle(.gray)
                                }

                                Slider(value: $fontSize, in: 15...28, step: 1)
                                    .tint(DragonTheme.red)
                            }
                        }

                        settingsCard(title: "Background") {
                            VStack(spacing: 10) {
                                ForEach(DragonReaderBackgroundStyle.allCases) { style in
                                    ArticleSettingsChoiceButton(
                                        title: style.title,
                                        subtitle: style.subtitle,
                                        isSelected: selectedBackgroundStyle == style,
                                        swatchColor: style.palette.pageBackground
                                    ) {
                                        backgroundStyleRawValue = style.rawValue
                                    }
                                }
                            }
                        }

                        settingsCard(title: "Direction") {
                            VStack(spacing: 10) {
                                ForEach(DragonReaderDirectionMode.allCases) { mode in
                                    ArticleSettingsChoiceButton(
                                        title: mode.title,
                                        subtitle: mode.subtitle,
                                        isSelected: directionModeRawValue == mode.rawValue,
                                        swatchColor: DragonTheme.red.opacity(mode == .auto ? 0.75 : 0.45)
                                    ) {
                                        directionModeRawValue = mode.rawValue
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            content()
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

private struct ArticleSettingsChoiceButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let swatchColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.semibold))

                    Text(subtitle)
                        .foregroundStyle(.gray)
                        .font(.caption)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DragonTheme.red : .gray)
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DragonTheme.red.opacity(isSelected ? 0.45 : 0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct DragonReaderPalette {
    let pageBackground: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let borderColor: Color
}

private enum DragonReaderBackgroundStyle: String, CaseIterable, Identifiable {
    case dragon
    case graphite
    case paper

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dragon:
            return "Dragon Black"
        case .graphite:
            return "Graphite"
        case .paper:
            return "Paper"
        }
    }

    var subtitle: String {
        switch self {
        case .dragon:
            return "Classic Dragon black and red."
        case .graphite:
            return "Soft dark gray for longer reading."
        case .paper:
            return "Warm light paper for contrast."
        }
    }

    var palette: DragonReaderPalette {
        switch self {
        case .dragon:
            return DragonReaderPalette(
                pageBackground: DragonTheme.background,
                cardBackground: DragonTheme.card,
                primaryText: .white,
                secondaryText: .gray,
                borderColor: DragonTheme.red.opacity(0.25)
            )
        case .graphite:
            return DragonReaderPalette(
                pageBackground: Color(red: 0.08, green: 0.09, blue: 0.11),
                cardBackground: Color(red: 0.12, green: 0.13, blue: 0.16),
                primaryText: .white,
                secondaryText: Color(red: 0.68, green: 0.70, blue: 0.74),
                borderColor: DragonTheme.red.opacity(0.22)
            )
        case .paper:
            return DragonReaderPalette(
                pageBackground: Color(red: 0.95, green: 0.93, blue: 0.88),
                cardBackground: Color(red: 0.98, green: 0.97, blue: 0.94),
                primaryText: Color.black.opacity(0.88),
                secondaryText: Color.black.opacity(0.56),
                borderColor: DragonTheme.red.opacity(0.22)
            )
        }
    }
}

private enum DragonReaderDirectionMode: String, CaseIterable, Identifiable {
    case auto
    case rtl
    case ltr

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .rtl:
            return "Force RTL"
        case .ltr:
            return "Force LTR"
        }
    }

    var subtitle: String {
        switch self {
        case .auto:
            return "Detect Arabic and align it automatically."
        case .rtl:
            return "Always right-align and use RTL layout."
        case .ltr:
            return "Always left-align and use LTR layout."
        }
    }

    func resolvedDirection(for text: String) -> DragonTextDirection {
        switch self {
        case .auto:
            return DragonTextDirection.forText(text)
        case .rtl:
            return .rightToLeft
        case .ltr:
            return .leftToRight
        }
    }

    func resolvedBodyDirection(for text: String) -> DragonTextDirection {
        switch self {
        case .auto:
            return DragonTextDirection.forBodyText(text)
        case .rtl:
            return .rightToLeft
        case .ltr:
            return .leftToRight
        }
    }
}

private enum DragonTextDirection {
    case leftToRight
    case rightToLeft

    static func forText(_ value: String) -> DragonTextDirection {
        isProbablyRTL(value) ? .rightToLeft : .leftToRight
    }

    static func forBodyText(_ value: String) -> DragonTextDirection {
        isProbablyRTL(value) ? .rightToLeft : .leftToRight
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
}

private func isProbablyRTL(_ text: String) -> Bool {
    text.unicodeScalars.contains { $0.isArabicScript }
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
