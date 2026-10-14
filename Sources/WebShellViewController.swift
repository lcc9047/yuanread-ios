import UIKit
import WebKit

/// 源阅 iOS 壳：一个 WKWebView 容器，加载同一套 Web 前端。
/// 前端更新后 App 无需重装即生效；这里只负责容器该管的事：外链、刷新、失败兜底、地址切换。
final class WebShellViewController: UIViewController {

    private var currentURL: URL = ServerConfig.baseURL

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupOverlay()
        setupAddressGesture()
        observeProgress()
        loadBaseURL()
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

    // MARK: - 组装

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
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
        overlay.backgroundColor = .systemBackground
        overlay.alpha = 0
        overlay.isHidden = true
        view.addSubview(overlay)

        overlayTitle.text = "打不开源阅"
        overlayTitle.font = .preferredFont(forTextStyle: .headline)
        overlayTitle.textAlignment = .center
        overlayTitle.numberOfLines = 0

        overlayDetail.font = .preferredFont(forTextStyle: .footnote)
        overlayDetail.textColor = .secondaryLabel
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
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func observeProgress() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            guard let self = self else { return }
            let value = Float(view.estimatedProgress)
            self.progressBar.isHidden = value >= 1.0
            self.progressBar.setProgress(value, animated: true)
        }
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
