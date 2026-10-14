import UIKit
import WebKit

/// 源阅 iOS 壳：一个 WKWebView 容器，加载同一套 Web 前端。
/// 前端更新后 App 无需重装即生效；这里只负责容器该管的事：外链、刷新、失败兜底、地址切换，
/// 以及「跟随页面主题」的状态栏与容器底色。
final class WebShellViewController: UIViewController {

    /// paper 主题的 --paper（styles.css 的 :root），与启动屏底色同值 ⇒ 从启动到首屏不闪白。
    private static let paperColor = UIColor(red: 248 / 255, green: 244 / 255, blue: 235 / 255, alpha: 1)
    private static let chromeBridgeName = "yuanreadChrome"

    private var currentURL: URL = ServerConfig.baseURL
    private var statusBarStyle: UIStatusBarStyle = .darkContent

    /// **仅供自动化验证**：`simctl launch … -themeOverride night` 时把 body 的 data-theme 钉在指定款，
    /// 用来在 CI 里截「深色主题」的图。走 NSArgumentDomain（不落盘）；只放行字母数字与 - _，防注入。
    private var themeOverride: String? {
        guard let raw = UserDefaults.standard.string(forKey: "themeOverride")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return raw
    }

    private let userContentController = WKUserContentController()

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController = self.userContentController
        self.userContentController.add(self, name: Self.chromeBridgeName)
        self.userContentController.addUserScript(WKUserScript(
            source: Self.chromeBridgeScript(overrideTheme: self.themeOverride),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let refreshControl = UIRefreshControl()
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let overlay = UIView()
    private let overlayTitle = UILabel()
    private let overlayDetail = UILabel()
    private var progressObservation: NSKeyValueObservation?

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    deinit {
        userContentController.removeScriptMessageHandler(forName: Self.chromeBridgeName)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.paperColor
        setupWebView()
        setupOverlay()
        setupAddressGesture()
        observeProgress()
        loadBaseURL()
    }

    // MARK: - 组装

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // 禁缩放：viewport 里没写 user-scalable=no（改了会影响安卓与桌面端），所以在容器侧钳住，
        // 避免阅读时双击把正文放大。
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.bouncesZoom = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        refreshControl.addTarget(self, action: #selector(doReload), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.trackTintColor = .clear
        progressBar.isHidden = true
        view.addSubview(progressBar)
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    private func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = Self.paperColor
        overlay.alpha = 0
        overlay.isHidden = true
        view.addSubview(overlay)

        overlayTitle.text = "打不开源阅"
        overlayTitle.font = .preferredFont(forTextStyle: .headline)
        overlayTitle.textAlignment = .center
        overlayTitle.numberOfLines = 0

        overlayDetail.font = .preferredFont(forTextStyle: .footnote)
        overlayDetail.textAlignment = .center
        overlayDetail.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            overlayTitle,
            overlayDetail,
            makeButton("重试") { [weak self] in self?.loadBaseURL() },
            makeButton("改地址") { [weak self] in self?.promptForAddress() },
            makeButton("用 Safari 打开") { [weak self] in
                guard let url = self?.currentURL else { return }
                UIApplication.shared.open(url)
            }
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32)
        ])

        applyOverlayColors(dark: false)
    }

    private func applyOverlayColors(dark: Bool) {
        let ink = dark ? UIColor.white : UIColor.black
        let link = UIColor(red: 0.88, green: 0.72, blue: 0.48, alpha: 1)
        overlayTitle.textColor = ink
        overlayDetail.textColor = ink.withAlphaComponent(0.7)
        for case let button as UIButton in (overlay.subviews.first as? UIStackView)?.arrangedSubviews ?? [] {
            button.setTitleColor(dark ? link : nil, for: .normal)
        }
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// 两指长按 1.5 秒打开地址设置 —— 刻意做得不容易误触，避免和网页手势打架。
    private func setupAddressGesture() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleAddressPress))
        press.numberOfTouchesRequired = 2
        press.minimumPressDuration = 1.5
        view.addGestureRecognizer(press)
    }

    @objc private func handleAddressPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        promptForAddress()
    }

    private func observeProgress() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            guard let self = self else { return }
            let value = Float(view.estimatedProgress)
            self.progressBar.isHidden = value >= 1.0
            self.progressBar.setProgress(value, animated: true)
        }
    }

    // MARK: - 与页面主题联动

    /// 注入到每个页面的桥：**页面主题一变就主动告诉原生**。
    /// 为什么不是「加载完成后读一次」：源阅的主题由前端 `applyPrefs()` 设置，而它在读完 IDB 之后才跑，
    /// 时机晚于 `didFinish`；用户在设置页切主题更是随时发生 —— 只在 didFinish 读一次必然漏。
    /// `overrideTheme` 非空时（仅 CI 验证用）还会**持续压制**成指定款，直到压住前端的 applyPrefs。
    private static func chromeBridgeScript(overrideTheme: String?) -> String {
        let value = overrideTheme.map { "'\($0)'" } ?? "''"
        return """
        (function () {
          var OVERRIDE = \(value);
          var lastBg = '';
          function bg() { try { return getComputedStyle(document.body).backgroundColor; } catch (e) { return ''; } }
          function notify() {
            var cur = bg();
            if (cur === lastBg) { return; }
            lastBg = cur;
            try {
              window.webkit.messageHandlers.\(chromeBridgeName).postMessage({
                bg: cur,
                theme: (document.body && document.body.dataset.theme) || ''
              });
            } catch (e) {}
          }
          function enforce() {
            if (!OVERRIDE || !document.body) { return; }
            if (document.body.dataset.theme !== OVERRIDE) { document.body.dataset.theme = OVERRIDE; }
            document.body.style.removeProperty('background');
            document.body.style.removeProperty('background-color');
            document.documentElement.style.removeProperty('--reader-bg');
          }
          function start() {
            if (!document.body) { setTimeout(start, 50); return; }
            enforce();
            notify();
            var observer = new MutationObserver(function () { enforce(); notify(); });
            observer.observe(document.body, { attributes: true, attributeFilter: ['data-theme', 'style'] });
            observer.observe(document.documentElement, { attributes: true, attributeFilter: ['style'] });
            var rounds = 0;
            var timer = setInterval(function () { enforce(); notify(); if (++rounds >= 20) { clearInterval(timer); } }, 200);
          }
          start();
        })();
        """
    }

    /// 状态栏文字色与容器底色都从**页面真实背景色**推算：页面切到 night/oled 时状态栏自动转白字、
    /// 回弹区不再露白边；而且不必维护「主题名 → 颜色」映射表（那张表迟早与 styles.css 漂移）。
    private func applyChrome(raw: String, color: UIColor, via source: String, theme: String) {
        let luminance = Self.relativeLuminance(color)
        let dark = luminance < 0.5
        let style: UIStatusBarStyle = dark ? .lightContent : .darkContent
        DispatchQueue.main.async {
            if self.statusBarStyle != style {
                self.statusBarStyle = style
                self.setNeedsStatusBarAppearanceUpdate()
            }
            self.view.backgroundColor = color
            self.overlay.backgroundColor = color
            self.webView.scrollView.backgroundColor = color
            self.webView.underPageBackgroundColor = color
            self.applyOverlayColors(dark: dark)
            NSLog("[YuanRead] chrome sync via=%@ bg=%@ luminance=%.3f statusBar=%@ theme=%@",
                  source, raw, luminance, dark ? "lightContent" : "darkContent", theme)
        }
    }

    private func syncChromeFromPage() {
        webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") { [weak self] result, error in
            guard let self = self else { return }
            guard error == nil, let raw = result as? String, let color = Self.parseCSSColor(raw) else {
                NSLog("[YuanRead] chrome probe failed raw=%@ err=%@",
                      String(describing: result), String(describing: error))
                return
            }
            self.applyChrome(raw: raw, color: color, via: "probe", theme: "")
        }
    }

    /// 解析 `rgb(r, g, b)` / `rgba(r, g, b, a)`。
    private static func parseCSSColor(_ raw: String) -> UIColor? {
        let digits = raw
            .replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let parts = digits.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              let red = Double(parts[0]), let green = Double(parts[1]), let blue = Double(parts[2]) else { return nil }
        return UIColor(red: CGFloat(red / 255), green: CGFloat(green / 255), blue: CGFloat(blue / 255), alpha: 1)
    }

    private static func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }

    // MARK: - 加载

    @objc private func doReload() {
        webView.reload()
    }

    private func loadBaseURL() {
        hideOverlay()
        currentURL = ServerConfig.baseURL
        webView.load(URLRequest(url: currentURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    private func showOverlay(_ message: String) {
        overlayDetail.text = message
        overlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.overlay.alpha = 1 }
    }

    private func hideOverlay() {
        guard !overlay.isHidden else { return }
        UIView.animate(withDuration: 0.15, animations: { self.overlay.alpha = 0 }) { _ in
            self.overlay.isHidden = true
        }
    }

    private func promptForAddress() {
        let alert = UIAlertController(
            title: "服务地址",
            message: "例如 https://lcc1107.ltd　或　http://192.168.3.84:4173（同一 Wi-Fi 调试用）",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = ServerConfig.fallback
            field.text = UserDefaults.standard.string(forKey: ServerConfig.defaultsKey)
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存并加载", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            if ServerConfig.set(text) != nil {
                self?.loadBaseURL()
            } else {
                self?.showOverlay("地址格式不正确")
            }
        })
        alert.addAction(UIAlertAction(title: "恢复默认", style: .destructive) { [weak self] _ in
            ServerConfig.reset()
            self?.loadBaseURL()
        })
        present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension WebShellViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "http" && scheme != "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        if isMainFrame && !ServerConfig.isInApp(url) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        progressBar.isHidden = true
        hideOverlay()
        syncChromeFromPage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        showOverlay(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        showOverlay(error.localizedDescription)
    }
}

// MARK: - WKUIDelegate

extension WebShellViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

// MARK: - 页面 → 原生 的主题桥

extension WebShellViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == Self.chromeBridgeName,
              let payload = message.body as? [String: Any],
              let raw = payload["bg"] as? String,
              let color = Self.parseCSSColor(raw) else { return }
        applyChrome(raw: raw, color: color, via: "bridge", theme: (payload["theme"] as? String) ?? "")
    }
}
