import XCTest

/// 交互路径回归：在 iOS 模拟器里**真实点击**走一遍
/// 「搜索 → 详情 → 目录 → 正文 → 目录抽屉」，证明的不再是「首屏能渲染」，而是「点得动、能读到书」。
///
/// 依赖壳在 `-uiTestProbe 1` 下注入的可访问性标记（见 `WebShellViewController.uiTestMarkScript`）：
/// 关键元素带 `aria-label`，且**关键计数写进 label**（如 `search-results:54`）——
/// UI 测试读不到页面 JS，这样它既能精确点到元素，又能断言数量。
///
/// 选择器依据本地实测（`_tmp/probe-flow3.js`）：搜索结果卡片是 `article.book`（首个常来自影视源 🎬，要跳过）；
/// 章节项是 `<button>` 而不是 `<a>`。
final class YuanReadUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestProbe", "1"]
        app.launch()
    }

    private func webView() -> XCUIElement {
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 90), "WebView 未出现（页面可能没加载）")
        return web
    }

    /// 查 label 以某个前缀开头的元素（计数型 label 形如 `prefix:123`）。
    private func labelled(_ web: XCUIElement, _ prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix + ":")
        return web.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// 从 `prefix:123` 里取出 123；取不到返回 -1。
    private func count(_ element: XCUIElement, _ prefix: String) -> Int {
        let label = element.label
        guard label.hasPrefix(prefix + ":") else { return -1 }
        return Int(label.dropFirst(prefix.count + 1)) ?? -1
    }

    /// 轮询等待计数达到条件（真实上游慢，给足窗口）。
    private func waitForCount(_ web: XCUIElement, _ prefix: String, min: Int, attempts: Int, gap: UInt32 = 3) -> Int {
        var value = -1
        for _ in 0..<attempts {
            let element = labelled(web, prefix)
            if element.exists {
                value = count(element, prefix)
                if value >= min { return value }
            }
            sleep(gap)
        }
        return value
    }

    func testSearchToReadingFlow() throws {
        let web = webView()

        // ① 导航到搜索页（真实点击）
        let navSearch = web.buttons["nav-search"].firstMatch
        XCTAssertTrue(navSearch.waitForExistence(timeout: 60), "找不到导航「搜索」（标记脚本没注入？）")
        navSearch.tap()

        // ② 输入关键词并提交
        let searchField = web.searchFields["search-input"].firstMatch
        let textField = web.textFields["search-input"].firstMatch
        let input = searchField.exists ? searchField : textField
        XCTAssertTrue(input.waitForExistence(timeout: 30), "找不到搜索输入框")
        input.tap()
        input.typeText("剑来")

        let submit = web.buttons["search-submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 20), "找不到搜索提交按钮")
        submit.tap()

        // ③ 等搜索结果（真实上游，最多等 ~3 分钟）
        XCTAssertTrue(labelled(web, "search-results").waitForExistence(timeout: 60), "搜索结果容器没出现")
        let cards = waitForCount(web, "search-results", min: 1, attempts: 60)
        XCTAssertGreaterThan(cards, 0, "搜索没有返回任何结果 —— 上游书源不可用？")

        // ④ 点第一条**小说**结果（跳过影视源）→ 详情页
        let firstNovel = web.buttons["result-first-novel"].firstMatch
        XCTAssertTrue(firstNovel.waitForExistence(timeout: 60), "找不到可点的小说结果卡片")
        firstNovel.tap()

        XCTAssertTrue(labelled(web, "chapter-list").waitForExistence(timeout: 60), "详情页目录容器没出现")
        let chapters = waitForCount(web, "chapter-list", min: 1, attempts: 50)
        XCTAssertGreaterThan(chapters, 0, "详情页没加载出任何章节")

        // ⑤ 点第一章 → 阅读页
        let firstChapter = web.buttons["toc-first"].firstMatch
        XCTAssertTrue(firstChapter.waitForExistence(timeout: 30), "找不到第一章按钮")
        firstChapter.tap()

        XCTAssertTrue(labelled(web, "reading-content").waitForExistence(timeout: 60), "阅读页正文容器没出现")
        let readingLength = waitForCount(web, "reading-content", min: 200, attempts: 50)
        XCTAssertGreaterThan(readingLength, 200, "正文不足 200 字 —— 没真正读到书")

        // ⑥ 目录抽屉
        let openToc = web.buttons["open-toc"].firstMatch
        if openToc.waitForExistence(timeout: 20) { openToc.tap() }
        let tocItems = waitForCount(web, "toc-panel", min: 1, attempts: 15)
        XCTAssertGreaterThan(tocItems, 0, "目录抽屉里没有条目")

        print("[XCUITest] PASS 搜索卡片=\(cards) 章节=\(chapters) 正文=\(readingLength) 目录条目=\(tocItems)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reading-flow-end"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
