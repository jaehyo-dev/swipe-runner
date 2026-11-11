// v0.9.1 웹 확인 (창 없이: 헤드리스 소프트웨어 렌더링, 화면 확인용)
// 1) 메인 화면 3종: 휴대폰 390x844, PC 1280x720, 짧은 창 800x900 (SWIPE TO START가 젤리·빛과 겹치는지 보는 캡처)
// 2) 휴대폰: 설정 패널 → MUSIC 30%·SFX 60%·SHOW GUIDE → DONE → 새로고침 → 다시 열어 값이 남았는지 (캡처 + SETTINGS 로그)
// 3) 휴대폰: 시작 → ‖ → 일시정지 캡처 → RESUME → 3·2·1 프레임(GIF용) → 이어 한 뒤 박자 오차(PAUSE 로그)
// 4) 탭 가림 흉내(visibilitychange) → 자동 일시정지
// 콘솔 오류는 모두 모은다. 사용: PW=.. CHROME=.. node check_web.mjs <주소> <결과 폴더>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
fs.mkdirSync(`${out}/frames`, { recursive: true });
const report = { errors: [], logs: [] };
const S = (vp) => Math.min(vp.width / 720, vp.height / 1280);  // 720x1280 기준 → 화면 (stretch expand)

async function open(vp, profile) {
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport: vp, args: ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required'] });
  const page = ctx.pages()[0] || await ctx.newPage();
  page.on('console', m => { if (m.type() === 'error') report.errors.push(`${vp.width}x${vp.height}: ${m.text()}`); if (/^(SETTINGS|PAUSE|SAVE|QUALITY|MUSIC)/.test(m.text())) report.logs.push(`${vp.width}x${vp.height}: ${m.text()}`); });
  page.on('pageerror', e => report.errors.push(`${vp.width}x${vp.height}: ${e}`));
  return { ctx, page };
}
const ready = page => page.waitForFunction(() => window.gameReady > 0, null, { timeout: 180000 });

// 1) 메인 화면 3종
for (const [name, vp] of [['phone', { width: 390, height: 844 }], ['pc', { width: 1280, height: 720 }], ['short', { width: 800, height: 900 }]]) {
  const { ctx, page } = await open(vp, fs.mkdtempSync(path.join(os.tmpdir(), 'v091-')));
  await page.goto(url);
  await ready(page);
  await page.waitForTimeout(2500);  // 박에 맞춰 밝아졌다 흐려지는 SWIPE TO START: 여러 장 중 가장 밝은 때를 고르지 않고 그대로
  await page.screenshot({ path: `${out}/menu_${name}_${vp.width}x${vp.height}.png` });
  await ctx.close();
}

// 2~4) 휴대폰
const vp = { width: 390, height: 844 }, s = S(vp);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'v091-'));
let { ctx, page } = await open(vp, profile);
await page.goto(url);
await ready(page);
await page.waitForTimeout(1500);
const gear = [vp.width - 20 * s - 96 * s - 48 * s, 20 * s + 48 * s];
await page.mouse.click(...gear);
await page.waitForTimeout(400);
await page.screenshot({ path: `${out}/settings_phone.png` });
// 패널 자리 (SettingsPanel: 폭 600, 줄 96, 첫 줄 TOP 150, 슬라이더 오른쪽 300px). 진동은 헤드리스 크롬에도 navigator.vibrate가 있어 줄이 보인다
const cx = vp.width / 2, cy = vp.height / 2;
const rows = await page.evaluate(() => (typeof navigator.vibrate === 'function') ? 4 : 3);
const height = 150 + 96 * rows + 28 + 60 + 44, top = cy - height * s / 2;
const sliderX = k => cx + (300 - 48 - 300 + 13 + (300 - 26) * k) * s;  // 패널 가운데 기준 슬라이더 위치
const rowY = i => top + (150 + 96 * i + 48) * s;
await page.mouse.click(sliderX(0.3), rowY(0));
await page.mouse.click(sliderX(0.6), rowY(1));
await page.mouse.click(cx, rowY(rows - 1));  // SHOW GUIDE
await page.waitForTimeout(200);
await page.screenshot({ path: `${out}/settings_phone_changed.png` });
await page.mouse.click(cx, top + (150 + 96 * rows + 28 + 30) * s);  // DONE
await page.waitForTimeout(500);
await page.reload();
await ready(page);
await page.waitForTimeout(1500);
await page.mouse.click(...gear);
await page.waitForTimeout(400);
await page.screenshot({ path: `${out}/settings_phone_after_reload.png` });
await page.mouse.click(cx, top + (150 + 96 * rows + 28 + 30) * s);  // DONE (값은 그대로 다시 저장)
await page.waitForTimeout(300);

// 3) 일시정지
await page.mouse.click(cx, vp.height * 0.7);  // 시작 (화면 아무 곳)
await page.waitForFunction(() => window.gameStarted > 0, null, { timeout: 30000 });
await page.waitForTimeout(3000);
await page.mouse.click(20 * s + 48 * s, 20 * s + 48 * s);  // ‖
await page.waitForTimeout(300);
await page.screenshot({ path: `${out}/paused_phone.png` });
const resumeY = (660 + 40) * s + (vp.height - 1280 * s) / 2 * 0;  // 위 기준 배치 (세로 화면은 위가 맞음)
await page.mouse.click(cx, resumeY);
const t0 = Date.now();
let i = 0;
while (Date.now() - t0 < 2600) {  // 3·2·1 (100BPM 한 박 0.6초 × 2 + 조각) + 이어진 뒤 조금
  await page.screenshot({ path: `${out}/frames/count_${String(i++).padStart(3, '0')}.png` });
  await page.waitForTimeout(60);
}
await page.waitForTimeout(3500);  // 박자 오차 3초 기록
// 4) 탭 가림 흉내 → 자동 일시정지
await page.evaluate(() => { Object.defineProperty(document, 'hidden', { value: true, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
await page.waitForTimeout(300);
await page.evaluate(() => { Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/auto_paused_phone.png` });
report.audio_state_after_hide = await page.evaluate(() => window.gameAudioCtx?.state);
await ctx.close();
fs.writeFileSync(`${out}/check_web.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
