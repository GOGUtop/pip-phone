import AVFoundation

/// Keeps the app-wide audio session in a background-capable, non-exclusive mode.
///
/// The paired SillyTavern extension plays a silent HTML audio track only while a
/// generation is active. WKWebView owns that media playback, which helps prevent
/// the WebContent process from being frozen in the background. This native layer
/// configures the shared AVAudioSession with mixWithOthers so other apps' audio is
/// not intentionally interrupted.
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private init() {}

    private(set) var webKeepAliveRequested = false

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

    func releaseWebKeepAliveRequest() {
        webKeepAliveRequested = false
        // Do not deactivate the shared session here: PiP may still be active.
    }

    func reassertIfNeeded() {
        guard webKeepAliveRequested else { return }
        _ = prepareMixedBackgroundPlayback(markWebKeepAlive: true)
    }
}
