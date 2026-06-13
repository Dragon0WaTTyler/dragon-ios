import Foundation
import SwiftUI
import WebKit

struct YouTubeWatchView: View {
    @Environment(\.openURL) private var openURL
    @State private var currentVideo: DragonYouTubeVideo
    let videos: [DragonYouTubeVideo]

    init(video: DragonYouTubeVideo, videos: [DragonYouTubeVideo]) {
        _currentVideo = State(initialValue: video)
        self.videos = videos
    }

    private var videoID: String? {
        currentVideo.resolvedYouTubeVideoID
    }

    private var watchURL: URL? {
        guard let videoID else {
            return nil
        }

        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    private var embedURL: URL? {
        guard let videoID = currentVideo.resolvedYouTubeVideoID else {
            return nil
        }

        let queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://dragon99.pythonanywhere.com"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1")
        ]

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/embed/\(videoID)"
        components.queryItems = queryItems
        return components.url
    }

    private var sectionLabel: String {
        [currentVideo.section, currentVideo.group, currentVideo.playlist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var latestWatchLater: [DragonYouTubeVideo] {
        recommendedVideos { video in
            video.source.localizedCaseInsensitiveContains("watch")
                || video.section.localizedCaseInsensitiveContains("watchlater")
                || video.group.localizedCaseInsensitiveContains("watchlater")
        }
    }

    private var sameSectionOrGroup: [DragonYouTubeVideo] {
        let group = currentVideo.group.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = currentVideo.section.trimmingCharacters(in: .whitespacesAndNewlines)

        return recommendedVideos { video in
            if !group.isEmpty {
                return video.group.caseInsensitiveCompare(group) == .orderedSame
            }
            if !section.isEmpty {
                return video.section.caseInsensitiveCompare(section) == .orderedSame
            }
            return false
        }
    }

    private var sameChannel: [DragonYouTubeVideo] {
        let channel = currentVideo.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else {
            return []
        }

        return recommendedVideos { video in
            video.channel.caseInsensitiveCompare(channel) == .orderedSame
        }
    }

    var body: some View {
        ZStack {
            DragonTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Group {
                        if let embedURL {
                            YouTubePlayerWebView(url: embedURL)
                        } else {
                            YouTubePlayerUnavailableView()
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(DragonTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        if let watchURL {
                            Button {
                                openURL(watchURL)
                            } label: {
                                Label("Open in YouTube", systemImage: "arrow.up.right.square")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(DragonTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(DragonTheme.red.opacity(0.35), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("If YouTube blocks embedded playback on iPhone, open the video in YouTube.")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(currentVideo.title.isEmpty ? "Untitled video" : currentVideo.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(nil)

                        if !currentVideo.channel.isEmpty {
                            Text(currentVideo.channel)
                                .font(.headline)
                                .foregroundStyle(DragonTheme.red)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            if let publishedDateText = currentVideo.publishedDisplayText {
                                MetadataLine(label: "Published", value: publishedDateText)
                            }

                            if !sectionLabel.isEmpty {
                                MetadataLine(label: "Section", value: sectionLabel)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    YouTubeRecommendationSection(
                        title: "Latest Watch Later",
                        emptyMessage: "No Watch Later videos are available in the current data.",
                        videos: latestWatchLater,
                        selectedVideoID: currentVideo.id
                    ) { video in
                        currentVideo = video
                    }

                    YouTubeRecommendationSection(
                        title: "Same PocketTube Section",
                        emptyMessage: "No matching PocketTube section or group videos are available in the current data.",
                        videos: sameSectionOrGroup,
                        selectedVideoID: currentVideo.id
                    ) { video in
                        currentVideo = video
                    }

                    YouTubeRecommendationSection(
                        title: "More From This Channel",
                        emptyMessage: "No other videos from this channel are available in the current data.",
                        videos: sameChannel,
                        selectedVideoID: currentVideo.id
                    ) { video in
                        currentVideo = video
                    }
                }
                .padding(24)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("Watch")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recommendedVideos(matching predicate: (DragonYouTubeVideo) -> Bool) -> [DragonYouTubeVideo] {
        videos
            .filter { $0.id != currentVideo.id }
            .filter(predicate)
            .prefix(8)
            .map { $0 }
    }
}

struct YouTubePlayerWebView: UIViewRepresentable {
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
            webView.loadHTMLString(html, baseURL: URL(string: "https://dragon99.pythonanywhere.com"))
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

struct YouTubePlayerUnavailableView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)

            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.play")
                    .font(.title2)
                    .foregroundStyle(DragonTheme.red)

                Text("Video ID unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Dragon could not build an embedded player for this item. YouTube may also block embedded playback on iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct MetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)

            Text(value)
                .font(.footnote)
                .foregroundStyle(.white)
        }
    }
}

struct YouTubeRecommendationSection: View {
    let title: String
    let emptyMessage: String
    let videos: [DragonYouTubeVideo]
    let selectedVideoID: String
    let selectVideo: (DragonYouTubeVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            if videos.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DragonTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(videos) { video in
                        Button {
                            selectVideo(video)
                        } label: {
                            YouTubeRecommendationRow(video: video, isSelected: video.id == selectedVideoID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct YouTubeRecommendationRow: View {
    let video: DragonYouTubeVideo
    let isSelected: Bool

    private var thumbnailURL: URL? {
        let trimmed = video.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            placeholderThumbnail
                        @unknown default:
                            placeholderThumbnail
                        }
                    }
                } else {
                    placeholderThumbnail
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(video.title.isEmpty ? "Untitled video" : video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !video.channel.isEmpty {
                    Text(video.channel)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                if let publishedDateText = video.publishedDisplayText {
                    Text(publishedDateText)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? DragonTheme.red.opacity(0.14) : DragonTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DragonTheme.red.opacity(isSelected ? 0.55 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var placeholderThumbnail: some View {
        ZStack {
            Color.black.opacity(0.55)
            Image(systemName: "play.rectangle")
                .font(.headline)
                .foregroundStyle(DragonTheme.red)
        }
    }
}

extension DragonYouTubeVideo {
    var resolvedYouTubeVideoID: String? {
        let directID = video_id.trimmingCharacters(in: .whitespacesAndNewlines)
        if DragonYouTubeVideo.isValidYouTubeVideoID(directID) {
            return directID
        }

        let fallbackID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if DragonYouTubeVideo.isValidYouTubeVideoID(fallbackID) {
            return fallbackID
        }

        return DragonYouTubeVideo.extractYouTubeVideoID(from: url)
    }

    var publishedDisplayText: String? {
        let rawValue = published_at.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return nil
        }

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: rawValue) {
            return DragonYouTubeVideo.displayFormatter.string(from: date)
        }

        parser.formatOptions = [.withInternetDateTime]
        if let date = parser.date(from: rawValue) {
            return DragonYouTubeVideo.displayFormatter.string(from: date)
        }

        return rawValue
    }

    private static func extractYouTubeVideoID(from rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return nil
        }

        if host.contains("youtu.be") {
            let candidate = url.pathComponents.dropFirst().first ?? ""
            return isValidYouTubeVideoID(candidate) ? candidate : nil
        }

        if host.contains("youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let candidate = components.queryItems?.first(where: { $0.name == "v" })?.value,
               isValidYouTubeVideoID(candidate) {
                return candidate
            }

            let pathComponents = url.pathComponents
            for marker in ["embed", "shorts", "live"] {
                if let markerIndex = pathComponents.firstIndex(of: marker),
                   pathComponents.indices.contains(markerIndex + 1) {
                    let candidate = pathComponents[markerIndex + 1]
                    if isValidYouTubeVideoID(candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private static func isValidYouTubeVideoID(_ value: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.count == 11 && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
