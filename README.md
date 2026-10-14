# 源阅 iOS 壳（yuanread-ios）

一个 WKWebView 容器，加载源阅的 Web 前端。**阅读器逻辑照旧在主仓库里维护**，这里只管容器该管的事：外链丢给系统浏览器、下拉刷新、加载失败兜底、服务地址可切换。前端有更新，App 不用重装就跟着变。

## 你不需要什么

- ❌ 不需要 Mac —— 构建跑在 GitHub 的 macOS runner 上
- ❌ 不需要 $99 开发者账号 —— **iOS 模拟器不校验签名**，所以「模拟器测试」免费；真机用免费 Apple ID 自签
- ❌ 不需要上架 App Store

## 目录

```
ios-app/
├── project.yml                       # XcodeGen 工程描述（不手写 .xcodeproj）
├── Sources/
│   ├── AppDelegate.swift             # 入口
│   ├── WebShellViewController.swift  # WKWebView 主体
│   └── ServerConfig.swift            # 服务地址（默认 https://lcc1107.ltd）
├── Resources/Info.plist              # 启动屏声明 + ATS 本地网络例外
└── .github/workflows/ios-ipa.yml     # 云 macOS：构建 → 模拟器跑 → 截图 → 出未签名 ipa
```

## 一、推成一个独立仓库（一次性）

1. GitHub Desktop → **File → Add local repository** → 选本目录（`...\ban\ios-app`）
2. 它还不是 git 仓库，GitHub Desktop 会提示创建 → **Create New Repository**，名字建议 `yuanread-ios`，**选 Public**
   - 公开仓库的 macOS runner 分钟数免费不限；私有仓库只有约 200 分钟/月
3. **Publish repository** 推上去
4. 打开仓库的 **Actions** 页，`ios-build` 会自动开始跑（也可以点 **Run workflow** 手动触发）

> ⚠️ 这个目录是给「独立仓库」准备的：workflow 必须落在仓库根的 `.github/workflows/` 才生效。
> 以后若要并进源阅主仓库，把这个 yml 移到主仓库根即可。

## 二、看模拟器结果

跑完在该次 run 页面底部下载两个 artifact：

| artifact | 内容 |
|---|---|
| `simulator-run` | `home-6s.png` / `home-16s.png`（模拟器截图）、`yuanread-sim.log`（App 日志）、`site-probe.txt`（runner 到站点的连通性）、`build-simulator.log` |
| `yuanread-ios-unsigned-ipa` | 未签名 ipa（真机自签用）+ sha256 |

## 三、装到真机（免费 Apple ID 自签）

0. 手机先开 **设置 → 隐私与安全性 → 开发者模式**（iOS 16+ 必须，开了要重启一次）
1. Windows 装 [Sideloadly](https://sideloadly.io/)（依赖 iTunes/iCloud 的驱动；装不上就装 web 版 iTunes）
2. 数据线连 iPhone → 拖入 `YuanRead-unsigned.ipa` → 填 Apple ID → Start
   - **建议用小号 Apple ID**，别用主号
3. 手机 **设置 → 通用 → VPN 与设备管理** 里信任你的开发者证书
4. **有效期 7 天**：到期 App 打不开时，重连电脑点一次即可（同一 Apple ID + 同一 bundle id 会覆盖安装，Web 端数据在服务端，本地缓存丢失无伤）
   - 免费账号硬限制：同时最多 3 个自签 App、每 7 天 10 个 App ID

## 四、有 Mac 的话（可选，最快）

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project YuanRead.xcodeproj -scheme YuanRead \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

或直接在 Xcode 里 Cmd+R。

## 改服务地址

- 加载失败页上有「改地址」按钮；任何时候**两指长按屏幕 1.5 秒**也能唤出
- 默认 `https://lcc1107.ltd`
- 同一 Wi-Fi 下想连你电脑上的源阅，填 `192.168.3.84:4173` 即可（会自动补成 `http://`；本地网络权限弹窗点允许）

## 常见问题

| 现象 | 先看哪 |
|---|---|
| 截图里是「打不开源阅」+ 英文错误 | `site-probe.txt`：runner 连不上站点 ⇒ 网络问题；能连上 ⇒ 壳的问题 |
| 白屏但没报错 | `yuanread-sim.log`（多半是页面 JS 报错） |
| 真机上装完打不开 | 证书过期（7 天）或没信任开发者证书 |
| 提示「无法验证 App」 | 手机没开开发者模式 |
