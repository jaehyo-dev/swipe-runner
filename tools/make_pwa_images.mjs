// 홈 화면 앱(PWA) 그림 만들기 (v0.12.0, 창 없이: 헤드리스 크롬). 결과는 web/pwa/에 넣어 커밋한다 (tools/pwa_build.py가 빌드에 복사).
// 사용: PW=<playwright 폴더> CHROME=<크롬> node tools/make_pwa_images.mjs <웹 빌드 주소> <검수 시트 폴더>
// - 아이콘: 게임 메인 화면을 ?icon=1(글자 숨김)&skin=mint 로 휴대폰 크기·GPU로 렌더링 → 젤리 둘레 정사각형을 잘라
//   180·192·512(젤리 밝은 몸이 약 55%)와 maskable 512(가운데 안전 원 안, 약 40%)로 줄인다. 손으로 그리지 않는다
// - 시작 화면: web/shell.html 로딩 화면(검정 + SWIPE PULSE)을 JS 없이 아이폰 화면 크기마다 찍는다 (apple-touch-startup-image)
// - 검수 시트: 아이콘 4종 + 둥근 모서리·원 마스크 미리보기 → <검수 시트 폴더>/icon_sheet.png
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, sheetDir] = process.argv.slice(2);
const OUT = path.resolve('web/pwa');
// 아이폰 화면 (CSS 폭, 높이, 배율). shell.html의 <link rel="apple-touch-startup-image">와 같은 목록
export const STARTUP = [[375, 667, 2], [375, 812, 3], [390, 844, 3], [393, 852, 3], [402, 874, 3], [414, 896, 2], [414, 896, 3], [420, 912, 3], [428, 926, 3], [430, 932, 3], [440, 956, 3]];
const BG = '#05040d';

const browser = await chromium.launch({ executablePath: process.env.CHROME, headless: true,
  args: ['--disable-audio-output', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const errors = [];

// 1) 게임 렌더링
const game = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3 });
game.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await game.goto(new URL('?icon=1&skin=mint', url).href);
await game.waitForFunction(() => window.gameReady, null, { timeout: 120000 });
await game.waitForTimeout(2500);  // 로딩 화면이 사라지고 젤리 숨쉬기가 자리 잡게
const shot = await game.screenshot({ type: 'png' });
fs.mkdirSync(sheetDir, { recursive: true });
fs.writeFileSync(path.join(sheetDir, 'icon_source.png'), shot);

// 2) 자르기·줄이기: 빈 페이지의 캔버스에서. 젤리 = 화면 가운데 아래쪽의 밝은 민트 덩어리
const tool = await browser.newPage();
const made = await tool.evaluate(async ({ src, bg }) => {
  const img = new Image();
  img.src = src;
  await img.decode();
  const c = document.createElement('canvas');
  c.width = img.width; c.height = img.height;
  const g = c.getContext('2d');
  g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, c.width, c.height).data;
  let x0 = c.width, y0 = c.height, x1 = 0, y1 = 0;
  for (let y = Math.floor(c.height * 0.35); y < c.height * 0.85; y += 2) {
    for (let x = Math.floor(c.width * 0.2); x < c.width * 0.8; x += 2) {
      const i = (y * c.width + x) * 4;
      if (d[i + 1] > 150 && d[i + 1] > d[i] + 50) {  // 민트 몸(초록이 빨강보다 훨씬 밝음). 보라 난간·어두운 웅덩이 빛은 빠진다
        x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
      }
    }
  }
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, body = Math.max(x1 - x0, y1 - y0);
  const square = (size, fill) => {  // 젤리가 한 변의 fill 비율이 되게 자른 정사각형
    const side = body / fill;
    const o = document.createElement('canvas');
    o.width = o.height = size;
    const og = o.getContext('2d');
    og.fillStyle = bg;
    og.fillRect(0, 0, size, size);
    og.imageSmoothingQuality = 'high';
    og.drawImage(c, cx - side / 2, cy - side / 2, side, side, 0, 0, size, size);
    return o.toDataURL('image/png');
  };
  return {
    box: [x0, y0, x1, y1],
    icons: { icon_144: square(144, 0.55), icon_180: square(180, 0.55), icon_192: square(192, 0.55), icon_512: square(512, 0.55), icon_maskable_512: square(512, 0.4) },
  };
}, { src: 'data:image/png;base64,' + shot.toString('base64'), bg: BG });
console.log('젤리 밝은 덩어리 (px):', made.box.join(','));
for (const [name, data] of Object.entries(made.icons)) fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(data.split(',')[1], 'base64'));

// 3) 검수 시트: 원본 4종(실제 크기) + 아이폰 둥근 모서리 흉내(180) + 안드로이드 원 마스크(maskable 512 → 192)
const sheet = await browser.newPage({ viewport: { width: 1180, height: 600 } });
const img = (n) => 'data:image/png;base64,' + fs.readFileSync(path.join(OUT, n + '.png')).toString('base64');
await sheet.setContent(`<body style="margin:0;background:#888;font:14px sans-serif;color:#fff;display:flex;gap:24px;padding:20px;align-items:flex-end;flex-wrap:wrap">
  ${['icon_180', 'icon_192', 'icon_512', 'icon_maskable_512'].map((n) => `<figure style="margin:0"><img src="${img(n)}" style="width:${n.includes('512') ? 256 : 180}px;display:block"><figcaption>${n}${n.includes('512') ? ' (½)' : ''}</figcaption></figure>`).join('')}
  <figure style="margin:0"><img src="${img('icon_180')}" style="width:120px;border-radius:27px;display:block"><figcaption>iOS 모서리</figcaption></figure>
  <figure style="margin:0"><img src="${img('icon_maskable_512')}" style="width:120px;border-radius:50%;display:block"><figcaption>원 마스크</figcaption></figure>
  <figure style="margin:0"><img src="${img('icon_maskable_512')}" style="width:120px;clip-path:inset(10% round 22%);display:block"><figcaption>maskable 안전 영역 80%</figcaption></figure></body>`);
await sheet.screenshot({ path: path.join(sheetDir, 'icon_sheet.png'), fullPage: true });

// 4) 시작 화면 (JS 없이 로딩 화면만: 막대는 비어 있다)
const shell = 'file://' + path.resolve('web/shell.html');
for (const [w, h, k] of STARTUP) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: k, javaScriptEnabled: false });
  const p = await ctx.newPage();
  await p.goto(shell);
  await p.evaluate(() => document.fonts.ready).catch(() => {});
  await p.waitForTimeout(300);
  await p.screenshot({ path: path.join(OUT, `startup_${w}x${h}@${k}.png`) });
  await ctx.close();
}
await browser.close();
console.log('콘솔 오류', errors.length, errors.slice(0, 5));
