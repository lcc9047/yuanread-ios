import UIKit

/// iOS 13+ 的窗口在这里创建（Info.plist 的 UIApplicationSceneManifest 指向本类）。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = WebShellViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
