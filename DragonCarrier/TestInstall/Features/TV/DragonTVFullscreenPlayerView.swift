import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct DragonTVFullscreenPlayerPresenter: UIViewControllerRepresentable {
    @Binding var selectedChannel: IPTVChannel?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedChannel: $selectedChannel)
    }

    func makeUIViewController(context: Context) -> DragonTVFullscreenPlayerHostViewController {
        let controller = DragonTVFullscreenPlayerHostViewController()
        controller.onDismiss = {
            context.coordinator.clearSelection()
        }
        return controller
    }

    func updateUIViewController(_ controller: DragonTVFullscreenPlayerHostViewController, context: Context) {
        controller.onDismiss = {
            context.coordinator.clearSelection()
        }

        if let selectedChannel {
            controller.present(channel: selectedChannel)
        } else {
            controller.dismissPlayerIfNeeded()
        }
    }

    final class Coordinator {
        private var selectedChannel: Binding<IPTVChannel?>

        init(selectedChannel: Binding<IPTVChannel?>) {
            self.selectedChannel = selectedChannel
        }

        func clearSelection() {
            selectedChannel.wrappedValue = nil
        }
    }
}

final class DragonTVFullscreenPlayerHostViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var onDismiss: (() -> Void)?

    private var activeChannelID: String?
    private var activePlayer: AVPlayer?
    private weak var playerController: AVPlayerViewController?
    private var isProgrammaticDismissal = false

    override func loadView() {
        view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    func present(channel: IPTVChannel) {
        guard activeChannelID != channel.id || playerController == nil else {
            return
        }

        if playerController != nil {
            dismissPlayerIfNeeded(animated: false)
        }

        let player = makePlayer(for: channel)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.view.backgroundColor = .black
        controller.presentationController?.delegate = self

        activeChannelID = channel.id
        activePlayer = player
        playerController = controller

        guard presentedViewController == nil else {
            return
        }

        present(controller, animated: true) {
            player.play()
        }
    }

    func dismissPlayerIfNeeded(animated: Bool = true) {
        guard let playerController else {
            resetPlayerState()
            return
        }

        isProgrammaticDismissal = true
        playerController.dismiss(animated: animated) { [weak self] in
            guard let self else {
                return
            }

            self.resetPlayerState()
            self.isProgrammaticDismissal = false
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        resetPlayerState()

        guard !isProgrammaticDismissal else {
            return
        }

        onDismiss?()
    }

    private func makePlayer(for channel: IPTVChannel) -> AVPlayer {
        if let httpUserAgent = channel.httpUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !httpUserAgent.isEmpty {
            let asset = AVURLAsset(url: channel.url, options: [AVURLAssetHTTPUserAgentKey: httpUserAgent])
            return AVPlayer(playerItem: AVPlayerItem(asset: asset))
        }

        return AVPlayer(url: channel.url)
    }

    private func resetPlayerState() {
        activePlayer?.pause()
        activePlayer?.replaceCurrentItem(with: nil)
        activePlayer = nil
        activeChannelID = nil
        playerController = nil
    }
}
