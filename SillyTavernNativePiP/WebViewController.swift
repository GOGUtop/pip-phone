import UIKit
import WebKit

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let pipHostView = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
    private lazy var pipManager = PiPManager(hostView: pipHostView)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePiPHost()
        configureWebView()
        configureBridgeCallbacks()
        loadStartPage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // PiP is a native app feature in v1.3. It is armed automatically and no
        // longer depends on a SillyTavern front-end button or a five-minute timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pipManager.enablePersistent()
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: AppConfig.bridgeName)
    }

    private func configurePiPHost() {
        pipHostView.translatesAutoresizingMaskIntoConstraints = false
        pipHostView.alpha = 0.01
        pipHostView.isUserInteractionEnabled = false
        pipHostView.backgroundColor = .black
        view.addSubview(pipHostView)
        NSLayoutConstraint.activate([
            pipHostView.widthAnchor.constraint(equalToConstant: 4),
            pipHostView.heightAnchor.constraint(equalToConstant: 4),
            pipHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 1),
            pipHostView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 1),
        ])
    }

    private func configureWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = WKUserContentController()
        contentController.add(self, name: AppConfig.bridgeName)

        let bootstrap = """
        (() => {
          window.__ST_NATIVE_SHELL__ = {
            platform: 'ios',
            bridgeVersion: '\(AppConfig.bridgeVersion)',
            available: true,
            persistentPiP: true
          };
          window.dispatchEvent(new CustomEvent('st-native-ready', { detail: window.__ST_NATIVE_SHELL__ }));
        })();
        """
        contentController.addUserScript(WKUserScript(
            source: bootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        view.insertSubview(webView, belowSubview: pipHostView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureBridgeCallbacks() {
        pipManager.onStateChanged = { [weak self] active, error in
            DispatchQueue.main.async {
                self?.sendEvent("st-native-pip-state", detail: [
                    "active": active,
                    "persistent": self?.pipManager.currentState().persistent ?? true,
                    "error": error ?? NSNull(),
                ])
            }
        }
    }

    private func loadStartPage() {
        webView.load(URLRequest(url: AppConfig.startURL, cachePolicy: .reloadRevalidatingCacheData))
    }

    // MARK: - App lifecycle → native PiP

    func handleSceneDidBecomeActive() {
        pipManager.sceneDidBecomeActive()
    }

    func handleSceneWillResignActive() {
        pipManager.sceneWillResignActive()
    }

    func handleSceneDidEnterBackground() {
        pipManager.sceneDidEnterBackground()
    }

    // MARK: - JS bridge

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == AppConfig.bridgeName,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "ping":
            sendEvent("st-native-ready", detail: [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion,
                "available": true,
                "persistentPiP": true,
            ])

        case "startPiP":
            _ = AudioSessionManager.shared.prepareMixedBackgroundPlayback()
            let url = (body["videoURL"] as? String).flatMap(URL.init(string:))
            pipManager.enablePersistent(videoURL: url)

        case "stopPiP":
            pipManager.stop()

        case "prepareBackgroundAudio":
            let ok = AudioSessionManager.shared.prepareMixedBackgroundPlayback(markWebKeepAlive: true)
            sendEvent("st-native-background-audio-state", detail: ["active": ok])

        case "releaseBackgroundAudio":
            AudioSessionManager.shared.releaseWebKeepAliveRequest()
            sendEvent("st-native-background-audio-state", detail: ["active": false])

        case "requestNotifications":
            NotificationManager.shared.requestAuthorization { [weak self] granted, status in
                DispatchQueue.main.async {
                    self?.sendEvent("st-native-notification-state", detail: [
                        "granted": granted,
                        "status": status,
                    ])
                }
            }

        case "notificationStatus":
            NotificationManager.shared.currentAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.sendEvent("st-native-notification-state", detail: [
                        "granted": status == "granted" || status == "provisional" || status == "ephemeral",
                        "status": status,
                    ])
                }
            }

        case "notifyDone", "testNotification":
            let title = body["title"] as? String ?? "SillyTavern"
            let text = body["body"] as? String ?? "回复已经生成完毕。"
            NotificationManager.shared.notify(title: title, body: text) { [weak self] ok, status in
                DispatchQueue.main.async {
                    self?.sendEvent("st-native-notification-result", detail: [
                        "ok": ok,
                        "status": status,
                    ])
                }
            }

        default:
            break
        }
    }

    private func sendEvent(_ name: String, detail: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(detail),
              let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = "window.dispatchEvent(new CustomEvent(\(jsString(name)), { detail: \(json) }));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendEvent("st-native-ready", detail: [
            "platform": "ios",
            "bridgeVersion": AppConfig.bridgeVersion,
            "available": true,
            "persistentPiP": true,
        ])
        NotificationManager.shared.currentAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.sendEvent("st-native-notification-state", detail: [
                    "granted": status == "granted" || status == "provisional" || status == "ephemeral",
                    "status": status,
                ])
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host?.lowercased() == AppConfig.allowedHost.lowercased() {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    /// 让 target="_blank" 仍然在当前 SillyTavern WebView 打开。
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }
}
