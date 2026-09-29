import UIKit
import AVFoundation
import AVKit

/// Owns the native PiP session for the entire lifetime of the app.
///
/// v1.3 removes the old five-minute stop timer. Once persistent mode is enabled,
/// the player stays prepared and the manager keeps PiP armed. If iOS stops PiP
/// unexpectedly, the manager retries when the app is active again and keeps
/// automatic-from-inline enabled for the next background transition.
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
            case .notPossible: return "系统暂时没有允许进入 PiP；已保持待命，会在下一次可用时自动重试。"
            }
        }
    }

    var onStateChanged: ((Bool, String?) -> Void)?

    private weak var hostView: UIView?
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var startRetryWorkItem: DispatchWorkItem?
    private var startAttempts = 0
    private var currentVideoURL: URL?
    private(set) var persistentEnabled = true

    init(hostView: UIView) {
        self.hostView = hostView
        super.init()
    }

    /// Enables always-on PiP. Passing nil uses the bundled pip-loop.mp4.
    func enablePersistent(videoURL: URL? = nil) {
        persistentEnabled = true

        let sourceURL = videoURL ?? Bundle.main.url(forResource: "pip-loop", withExtension: "mp4")
        guard let sourceURL else {
            onStateChanged?(false, PiPError.noVideo.localizedDescription)
            return
        }

        if pipController == nil || currentVideoURL != sourceURL {
            preparePipeline(sourceURL: sourceURL)
        }

        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()
        player?.play()
        ensureRunning(reason: "enablePersistent")
    }

    /// Backwards-compatible entry point for older SillyTavern bridge versions.
    /// maxDuration is intentionally ignored in v1.3: PiP no longer expires after 5 minutes.
    func start(videoURL: URL?, maxDuration: TimeInterval = 0) {
        enablePersistent(videoURL: videoURL)
    }

    /// Explicitly disables persistent PiP until the app is relaunched or it is enabled again.
    func disablePersistent() {
        persistentEnabled = false
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil

        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        teardownPipeline()
        onStateChanged?(false, nil)
    }

    /// Backwards-compatible stop action.
    func stop() {
        disablePersistent()
    }

    func sceneDidBecomeActive() {
        guard persistentEnabled else { return }
        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()
        player?.play()
        // Give UIKit/AVKit a brief moment to settle after activation.
        scheduleEnsureRunning(after: 0.45, reason: "sceneDidBecomeActive")
    }

    func sceneWillResignActive() {
        guard persistentEnabled else { return }
        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()
        player?.play()
        // canStartPictureInPictureAutomaticallyFromInline handles the transition.
        // We also keep the controller/player alive so the system has a valid source.
    }

    func sceneDidEnterBackground() {
        guard persistentEnabled else { return }
        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()
        player?.play()
        // If automatic transition did not fire, try once while background execution
        // is still available through the active media session.
        scheduleEnsureRunning(after: 0.25, reason: "sceneDidEnterBackground")
    }

    func currentState() -> (active: Bool, persistent: Bool) {
        (pipController?.isPictureInPictureActive == true, persistentEnabled)
    }

    private func preparePipeline(sourceURL: URL) {
        teardownPipeline()
        currentVideoURL = sourceURL

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            onStateChanged?(false, PiPError.unsupported.localizedDescription)
            return
        }

        _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()

        let item = AVPlayerItem(url: sourceURL)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        queue.automaticallyWaitsToMinimizeStalling = false

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
            pip.canStartPictureInPictureAutomaticallyFromInline = true
        }

        player = queue
        playerLayer = layer
        playerLooper = looper
        pipController = pip
        queue.play()
    }

    private func ensureRunning(reason: String) {
        guard persistentEnabled else { return }
        guard let pip = pipController else {
            enablePersistent(videoURL: currentVideoURL)
            return
        }

        player?.play()

        if pip.isPictureInPictureActive {
            onStateChanged?(true, nil)
            startAttempts = 0
            return
        }

        guard pip.isPictureInPicturePossible else {
            retryStart(reason: reason)
            return
        }

        // AVKit allows a foreground app to call startPictureInPicture().
        // If iOS rejects a particular moment/transition, the delegate callback and
        // lifecycle hooks keep the session armed for a later retry.
        pip.startPictureInPicture()
    }

    private func retryStart(reason: String) {
        guard persistentEnabled else { return }
        startRetryWorkItem?.cancel()

        startAttempts += 1
        if startAttempts > 40 {
            startAttempts = 0
            onStateChanged?(false, PiPError.notPossible.localizedDescription)
            return
        }

        let delay = min(0.20 + Double(startAttempts) * 0.04, 1.0)
        let work = DispatchWorkItem { [weak self] in
            self?.ensureRunning(reason: "retry:\(reason)")
        }
        startRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleEnsureRunning(after delay: TimeInterval, reason: String) {
        guard persistentEnabled else { return }
        startRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.ensureRunning(reason: reason)
        }
        startRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func teardownPipeline() {
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil
        startAttempts = 0
        player?.pause()
        player = nil
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipController?.delegate = nil
        pipController = nil
        currentVideoURL = nil
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        startAttempts = 0
        onStateChanged?(true, nil)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        startAttempts = 0
        onStateChanged?(true, nil)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onStateChanged?(false, error.localizedDescription)
        if persistentEnabled {
            scheduleEnsureRunning(after: 0.8, reason: "failedToStart")
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChanged?(false, nil)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChanged?(false, nil)
        // Do NOT destroy the player/controller here. In persistent mode a system
        // interruption or return-to-app animation should only pause the visible PiP;
        // the source stays alive and is re-armed automatically.
        if persistentEnabled {
            player?.play()
            scheduleEnsureRunning(after: 0.9, reason: "didStop")
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
