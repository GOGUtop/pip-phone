import UIKit
import AVFoundation
import AVKit

final class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    enum PiPError: LocalizedError {
        case unsupported
        case noVideo
        case controllerUnavailable
        case notPossible

        var errorDescription: String? {
            switch self {
            case .unsupported: return "当前设备不支持系统画中画。"
            case .noVideo: return "没有可用的 PiP 视频。"
            case .controllerUnavailable: return "无法创建系统 PiP 控制器。"
            case .notPossible: return "系统暂时没有允许进入 PiP，请稍后重试。"
            }
        }
    }

    var onStateChanged: ((Bool, String?) -> Void)?

    private weak var hostView: UIView?
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var stopTimer: Timer?
    private var startRetryWorkItem: DispatchWorkItem?
    private var startAttempts = 0

    init(hostView: UIView) {
        self.hostView = hostView
        super.init()
    }

    func start(videoURL: URL?, maxDuration: TimeInterval = 300) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            onStateChanged?(false, PiPError.unsupported.localizedDescription)
            return
        }

        stopPlayerOnly()

        let sourceURL: URL?
        if let videoURL {
            sourceURL = videoURL
        } else {
            sourceURL = Bundle.main.url(forResource: "pip-loop", withExtension: "mp4")
        }
        guard let sourceURL else {
            onStateChanged?(false, PiPError.noVideo.localizedDescription)
            return
        }

        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()

        let item = AVPlayerItem(url: sourceURL)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = hostView?.bounds ?? CGRect(x: 0, y: 0, width: 4, height: 4)
        hostView?.layer.addSublayer(layer)

        let looper = AVPlayerLooper(player: queue, templateItem: item)
        guard let pip = AVPictureInPictureController(playerLayer: layer) else {
            layer.removeFromSuperlayer()
            onStateChanged?(false, PiPError.controllerUnavailable.localizedDescription)
            return
        }
        pip.delegate = self
        pip.requiresLinearPlayback = true
        if #available(iOS 14.2, *) {
            pip.canStartPictureInPictureAutomaticallyFromInline = false
        }

        player = queue
        playerLayer = layer
        playerLooper = looper
        pipController = pip
        queue.play()

        startAttempts = 0
        tryStartWhenPossible(maxDuration: maxDuration)
    }

    private func tryStartWhenPossible(maxDuration: TimeInterval) {
        startRetryWorkItem?.cancel()
        guard let pip = pipController else { return }

        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            armStopTimer(seconds: maxDuration)
            return
        }

        startAttempts += 1
        if startAttempts >= 30 {
            onStateChanged?(false, PiPError.notPossible.localizedDescription)
            stopPlayerOnly()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.tryStartWhenPossible(maxDuration: maxDuration)
        }
        startRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil

        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        } else {
            stopPlayerOnly()
            onStateChanged?(false, nil)
        }
    }

    private func armStopTimer(seconds: TimeInterval) {
        stopTimer?.invalidate()
        guard seconds > 0 else { return }
        stopTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    private func stopPlayerOnly() {
        stopTimer?.invalidate()
        stopTimer = nil
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil
        player?.pause()
        player = nil
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipController?.delegate = nil
        pipController = nil
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChanged?(true, nil)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChanged?(true, nil)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onStateChanged?(false, error.localizedDescription)
        stopPlayerOnly()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopPlayerOnly()
        onStateChanged?(false, nil)
    }
}
