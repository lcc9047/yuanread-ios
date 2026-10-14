import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    /// 场景化启动：窗口交给 SceneDelegate 创建，这里只声明用哪个配置。
    /// （此前用的是 legacy window 模式，UIKit 会警告 `UIScene lifecycle will soon be required`。）
    /// delegateClass 用代码指定而不是写进 Info.plist 的 `$(PRODUCT_MODULE_NAME).SceneDelegate`
    /// —— 少一层字符串替换，少一个静默失败点。
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
