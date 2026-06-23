import Foundation
import UIKit
import SwiftUI
import YouTubePlayerKit

enum DragonYouTubePlaybackHelper {
    static func watchURL(videoID: String) -> URL? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: "https://www.youtube.com/watch?v=\(trimmed)")
    }

    static func appURL(videoID: String) -> URL? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: "youtube://www.youtube.com/watch?v=\(trimmed)")
    }

    static func inlinePlayer(videoID: String?) -> YouTubePlayer? {
        let trimmed = videoID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return nil
        }

        return YouTubePlayer(
            source: .video(id: trimmed),
            parameters: .init(
                showControls: true,
                showFullscreenButton: true,
                captionLanguage: preferredCaptionLanguageCode,
                showCaptions: true
            ),
            configuration: .init(allowsInlineMediaPlayback: true)
        )
    }

    @MainActor
    static func open(videoID: String) {
        guard let appURL = appURL(videoID: videoID),
              let webURL = watchURL(videoID: videoID) else {
            return
        }

        let application = UIApplication.shared
        application.open(appURL, options: [:]) { success in
            guard !success else {
                return
            }

            DispatchQueue.main.async {
                application.open(webURL, options: [:], completionHandler: nil)
            }
        }
    }

    private static var preferredCaptionLanguageCode: String {
        if let languageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier,
           !languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return languageCode
        }

        if let preferredLanguage = Locale.preferredLanguages.first,
           let languageCode = Locale(identifier: preferredLanguage).language.languageCode?.identifier,
           !languageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return languageCode
        }

        return "en"
    }
}

struct DragonYouTubeInlinePlayerView: View {
    let videoID: String?
    @State private var player: YouTubePlayer?

    init(videoID: String?) {
        self.videoID = videoID

        _player = State(initialValue: DragonYouTubePlaybackHelper.inlinePlayer(videoID: videoID))
    }

    var body: some View {
        Group {
            if let player {
                YouTubePlayerView(player) { state in
                    switch state {
                    case .idle:
                        DragonYouTubePlayerStatusView(
                            title: "Loading player",
                            message: "Preparing the in-app YouTube player."
                        )
                    case .ready:
                        EmptyView()
                    case .error(_):
                        YouTubePlayerUnavailableView(
                            message: "YouTube blocked embedded playback for this video. Open in YouTube remains available below."
                        )
                    }
                }
            } else {
                YouTubePlayerUnavailableView(
                    message: "This video does not have a usable YouTube ID yet."
                )
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DragonYouTubePlayerStatusView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(DragonTheme.red)

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }
}

struct YouTubePlayerUnavailableView: View {
    let title: String
    let message: String

    init(
        title: String = "Embedded playback unavailable",
        message: String
    ) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.play")
                .font(.title2)
                .foregroundStyle(DragonTheme.red)

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }
}
