import Foundation

enum AppConfig {
    /// 你的 SillyTavern 地址。需要改地址时只改这一行即可。
    static let startURL = URL(string: "http://aaa.xixisillytavern.top:8001/")!

    /// 只允许这个主机在 App 内作为顶层页面导航；其他 http(s) 链接会交给系统浏览器。
    static let allowedHost = "aaa.xixisillytavern.top"

    static let bridgeName = "stNative"
    static let bridgeVersion = "1.4.0"

    /// 与 SillyTavern Server Plugin 共用的稳定设备 ID。
    static let deviceID: String = {
        let key = "st.native.device-id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()

    static var monitorStatusURL: URL {
        URL(string: "/api/plugins/st-native-monitor/status", relativeTo: startURL)!.absoluteURL
    }
}
