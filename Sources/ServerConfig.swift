import Foundation

/// 壳要加载的服务地址：默认走公网（https），也可在 App 内「改地址」切到局域网 http://192.168.x.x:4173 调试。
enum ServerConfig {

    static let defaultsKey = "yuanread.baseUrl"
    static let fallback = "https://lcc1107.ltd"

    /// 这些 host 视为「源阅自己」，留在 WebView 内导航；其余一律交给系统浏览器。
    private static let builtinHosts: Set<String> = ["lcc1107.ltd", "www.lcc1107.ltd"]

    static var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let url = normalize(saved) {
            return url
        }
        return URL(string: fallback)!
    }

    @discardableResult
    static func set(_ raw: String) -> URL? {
        guard let url = normalize(raw) else { return nil }
        UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey)
        return url
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// 允许用户只填 "192.168.3.84:4173" 这种，自动补 https://（本地回环补 http://）。
    static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var text = trimmed
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }

        let repaired = isLoopbackOrLAN(host) && url.scheme == "https" ? swapToHTTP(url) : url
        return repaired
    }

    static func isInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if builtinHosts.contains(host) { return true }
        if host == "localhost" { return true }
        if let baseHost = baseURL.host?.lowercased(), host == baseHost { return true }
        return isLoopbackOrLAN(host)
    }

    private static func isLoopbackOrLAN(_ host: String) -> Bool {
        return host.hasPrefix("127.")
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
            || host.hasPrefix("172.16.")
            || host == "localhost"
    }

    private static func swapToHTTP(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "http"
        return components.url ?? url
    }
}
