import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var webController: WebViewController? {
        window?.rootViewController as? WebViewController
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AudioSessionManager.shared.reassertIfNeeded()
        webController?.handleSceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AudioSessionManager.shared.reassertIfNeeded()
        webController?.handleSceneWillResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AudioSessionManager.shared.reassertIfNeeded()
        webController?.handleSceneDidEnterBackground()
    }
}
