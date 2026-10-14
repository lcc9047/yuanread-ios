/* 从主仓库的 public/icon.svg（图标唯一来源）生成 iOS 侧所需的位图。
 *
 * 用法（在源阅主仓库根跑，脚本会自己向上找到 playwright）：
 *   node ios-app/tools/gen-ios-assets.js
 *
 * 产物（都要提交进本仓库，CI 不重新生成 ⇒ 本工程保持零依赖）：
 *   Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png   1024, iOS 14+ 单尺寸 App 图标
 *   Resources/Assets.xcassets/LaunchIcon.imageset/launch-icon*.png  160/320/480 (1x/2x/3x)
 *
 * 启动屏图标为什么要三档：UILaunchScreen 的 UIImageName 按图片**自身 pt**居中显示、不缩放，
 * 所以 1x=160px 才是「显示 160pt」；只放一张大图会被撑成满屏。
 *
 * 为什么不引新依赖：复用主仓库已有的 playwright + Chromium 渲染矢量，跟
 * scripts/gen-app-icons.js（网页端图标）同一套做法，保证同一个 SVG 源在两端口味一致。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const REPO = path.join(ROOT, '..');
const SRC = path.join(REPO, 'public', 'icon.svg');
const OUT = [
  ['Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png', 1024],
  ['Resources/Assets.xcassets/LaunchIcon.imageset/launch-icon.png', 160],
  ['Resources/Assets.xcassets/LaunchIcon.imageset/launch-icon@2x.png', 320],
  ['Resources/Assets.xcassets/LaunchIcon.imageset/launch-icon@3x.png', 480],
];

/** 把 svg 根标签撑到指定尺寸（文件里的 width/height 会被替换）。 */
function atSize(svg, size) {
  return svg.replace(/<svg([^>]*?)>/, (m, attrs) => {
    const cleaned = attrs.replace(/\s(width|height)="[^"]*"/g, '');
    return '<svg' + cleaned + ' width="' + size + '" height="' + size + '" style="display:block">';
  });
}

/** 从 IHDR 读回真实尺寸与色彩类型 —— 断言产物，不靠约定。 */
function pngInfo(buf) {
  if (buf.toString('ascii', 1, 4) !== 'PNG') return null;
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20), colorType: buf.readUInt8(25) };
}

(async () => {
  if (!fs.existsSync(SRC)) { console.error('❌ 找不到图标源：' + SRC); process.exit(1); }
  const svg = fs.readFileSync(SRC, 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });

  for (const [rel, size] of OUT) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent('<html><body style="margin:0">' + atSize(svg, size) + '</body></html>');
    const buf = await page.screenshot({ clip: { x: 0, y: 0, width: size, height: size } });
    const got = pngInfo(buf);
    if (!got || got.w !== size || got.h !== size) {
      console.error('❌ ' + rel + ' 尺寸不对：' + JSON.stringify(got));
      process.exit(1);
    }
    const dest = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, buf);
    console.log('  ✅ ' + rel.padEnd(60) + String(buf.length).padStart(7) + ' B   '
      + got.w + 'x' + got.h + '  colorType=' + got.colorType + (got.colorType === 2 ? ' (RGB, 无 alpha)' : ''));
  }

  await browser.close();
  console.log('（源：' + SRC + '；改图后重跑本脚本 + 主仓库 scripts/gen-app-icons.js）');
})().catch((e) => { console.error('❌ 生成失败：' + e.message); process.exit(1); });
