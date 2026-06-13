import SwiftUI

struct DragonYouTubeView: View {
    var body: some View {
        DragonYouTubeBrowserView()
    }
}

struct YouTubeVideoRow: View {
    let video: DragonYouTubeVideo

    private var thumbnailURL: URL? {
        let trimmed = video.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: trimmed)
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
