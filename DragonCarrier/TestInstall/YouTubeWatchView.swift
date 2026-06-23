import Foundation
import SwiftUI

struct YouTubeWatchView: View {
    @State private var currentVideo: DragonYouTubeVideo
    let videos: [DragonYouTubeVideo]

    init(video: DragonYouTubeVideo, videos: [DragonYouTubeVideo]) {
        _currentVideo = State(initialValue: video)
        self.videos = videos
    }

    private var videoID: String? {
        currentVideo.resolvedYouTubeVideoID
    }

    private var sectionLabel: String {
        [currentVideo.section, currentVideo.group, currentVideo.playlist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var nearbyPlaylistVideos: [DragonYouTubeVideo] {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideo.id || $0.video_id == currentVideo.video_id }) else {
            return recommendedVideos { _ in true }
        }

        let lowerBound = max(currentIndex - 4, 0)
        let upperBound = min(currentIndex + 4, videos.count - 1)

        return Array(videos[lowerBound...upperBound])
            .filter { $0.id != currentVideo.id }
            .prefix(8)
            .map { $0 }
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
                    playbackHeader

                    YouTubeRecommendationSection(
                        title: "More From This List",
                        emptyMessage: "No nearby videos are available in the current list.",
                        videos: nearbyPlaylistVideos,
                        selectedVideoID: currentVideo.id
                    ) { video in
                        currentVideo = video
                    }

                    YouTubeRecommendationSection(
                        title: "Same Section or Group",
                        emptyMessage: "No matching section or group videos are available in the current list.",
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

    private var playbackHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            DragonYouTubeInlinePlayerView(videoID: videoID)
                .id(currentVideo.id)

            VStack(alignment: .leading, spacing: 12) {
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

                    let duration = currentVideo.duration.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !duration.isEmpty {
                        MetadataLine(label: "Duration", value: duration)
                    }
                }

                if let videoID {
                    Button {
                        DragonYouTubePlaybackHelper.open(videoID: videoID)
                    } label: {
                        Label("Open in YouTube", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DragonTheme.red)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if videoID != nil {
                        Text("The in-app player is visible by default. If YouTube blocks embedded playback for this video, Open in YouTube remains available below.")
                    } else {
                        Text("The in-app player is visible by default, but this item does not expose a usable YouTube ID yet.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.gray)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DragonTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DragonTheme.red.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendedVideos(matching predicate: (DragonYouTubeVideo) -> Bool) -> [DragonYouTubeVideo] {
        videos
            .filter { $0.id != currentVideo.id }
            .filter(predicate)
            .prefix(8)
            .map { $0 }
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

    static func extractYouTubeVideoID(from rawURL: String) -> String? {
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

    static func isValidYouTubeVideoID(_ value: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.count == 11 && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }
}
