import AVFoundation

/// App-wide background media session.
///
/// v1.4 adds a native silent AVAudioPlayer loop. This is deliberately native,
/// not HTML audio: iOS can freeze WKWebView's WebContent process even while the
/// app's PiP continues. The native silent player keeps the app process eligible
/// for background audio execution so ServerMonitor can continue polling.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private(set) var webKeepAliveRequested = false
    private var nativeKeepAlivePlayer: AVAudioPlayer?

    @discardableResult
    func prepareMixedBackgroundPlayback(markWebKeepAlive: Bool = false) -> Bool {
        if markWebKeepAlive {
            webKeepAliveRequested = true
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            return true
        } catch {
            print("[NativePiP] audio session configuration failed: \(error)")
            return false
        }
    }

    /// Starts an endless, actually silent bundled MP3 in the native process.
    /// The session mixes with other apps, so it should not pause the video/audio
    /// the user is listening to in another app.
    @discardableResult
    func startNativeKeepAlive() -> Bool {
        guard prepareMixedBackgroundPlayback() else { return false }

        if let player = nativeKeepAlivePlayer {
            if !player.isPlaying { player.play() }
            return player.isPlaying
        }

        guard let url = Bundle.main.url(forResource: "native-silent-keepalive", withExtension: "mp3") else {
            print("[NativePiP] native silent keep-alive resource missing")
            return false
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0 // The file itself contains silence.
            player.prepareToPlay()
            player.play()
            nativeKeepAlivePlayer = player
            return player.isPlaying
        } catch {
            print("[NativePiP] native keep-alive player failed: \(error)")
            return false
        }
    }

    func releaseWebKeepAliveRequest() {
        webKeepAliveRequested = false
        // Do not deactivate the shared session. Native PiP and the native
        // background monitor keep-alive may still be active.
    }

    func reassertIfNeeded() {
        _ = prepareMixedBackgroundPlayback(markWebKeepAlive: webKeepAliveRequested)
        _ = startNativeKeepAlive()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                _ = self?.startNativeKeepAlive()
            }
        }
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            _ = self?.startNativeKeepAlive()
        }
    }
}
