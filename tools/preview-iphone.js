'use strict';
/**
 * iPhone 视口调试回路：在 Windows 上用**真实 WebKit 引擎**打开源阅，验证 iOS 观感与交互，
 * 不必每改一处就等云 CI（那一轮要 6 分钟）。
 *
 * 为什么用 WebKit 而不是 Chromium：iOS 上的 WKWebView 就是 WebKit；Playwright 的 webkit
 * 是同一内核在 Windows/Linux 上的构建，能用同一套 DevTools 协议调试 —— 比 Chromium
 * 模拟 iPhone 更接近真实。第一次用需要下载引擎（约 150MB）：
 *   node node_modules/playwright/cli.js install webkit
 *
 * 用法（在源阅主仓库根跑）：
 *   node ios-app/tools/preview-iphone.js                       # 开一个 iPhone 视口窗口，边点边看
 *   node ios-app/tools/preview-iphone.js --engine=chromium      # 换个引擎做对照
 *   node ios-app/tools/preview-iphone.js --shot=_tmp/iphone.png --headless   # 只出一张图
 *   node ios-app/tools/preview-iphone.js --url=http://192.168.3.84:4173/     # 换地址（默认本机 4173）
 *   node ios-app/tools/preview-iphone.js --theme=night          # 进去后切成指定主题（模拟壳里那个开关）
 */
const path = require('node:path');
const fs = require('node:fs');
const { webkit, chromium, devices } = require('playwright');

function arg(name, fallback) {
  const prefix = '--' + name + '=';
  const hit = process.argv.find((a) => a.startsWith(prefix));
  return hit ? hit.slice(prefix.length) : fallback;
}
const hasFlag = (name) => process.argv.includes('--' + name);

const engineName = arg('engine', 'webkit');
const url = arg('url', 'http://127.0.0.1:4173/');
const deviceName = arg('device', 'iPhone 15');
const theme = arg('theme', '');
const shot = arg('shot', '');
const headless = hasFlag('headless') || !!shot;

(async () => {
  const type = engineName === 'chromium' ? chromium : webkit;
  const device = devices[deviceName] || devices['iPhone 15'];
  if (!device) throw new Error('未知设备名：' + deviceName);

  const browser = await type.launch({ headless });
  const context = await browser.newContext(Object.assign({}, device, { locale: 'zh-CN' }));
  const page = await context.newPage();

  page.on('console', (m) => console.log('[console.' + m.type() + '] ' + m.text()));
  page.on('pageerror', (e) => console.log('[pageerror] ' + e.message));
  page.on('requestfailed', (r) => console.log('[requestfailed] ' + r.url() + ' -> ' + ((r.failure() || {}).errorText || '')));

  console.log('engine=' + engineName + '  device=' + deviceName + '  headless=' + headless);
  console.log('url=' + url);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2500);

  if (theme) {
    await page.evaluate((t) => { document.body.dataset.theme = t; }, theme);
    await page.waitForTimeout(400);
  }

  const info = await page.evaluate(() => ({
    theme: document.body.dataset.theme || '(默认 paper)',
    bodyBackground: getComputedStyle(document.body).backgroundColor,
    viewport: window.innerWidth + 'x' + window.innerHeight,
    dpr: window.devicePixelRatio,
    userAgent: navigator.userAgent,
    hasIDB: typeof indexedDB !== 'undefined',
  }));
  console.log('页面自述：' + JSON.stringify(info, null, 2));

  if (shot) {
    fs.mkdirSync(path.dirname(path.resolve(shot)), { recursive: true });
    await page.screenshot({ path: shot });
    console.log('已截图：' + shot);
    await browser.close();
    return;
  }

  console.log('窗口已打开 —— 直接点着调；关掉窗口或 Ctrl+C 结束。');
  await page.waitForEvent('close', { timeout: 0 }).catch(() => {});
  await browser.close();
})().catch((e) => {
  console.error('❌ ' + e.message);
  if (String(e.message).includes("Executable doesn't exist")) {
    console.error('   ↳ 引擎没装：node node_modules/playwright/cli.js install webkit');
  }
  process.exit(1);
});
