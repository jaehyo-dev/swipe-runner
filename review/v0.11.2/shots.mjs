// v0.11.2 화면 확인 (창 없이: 헤드리스 크롬 + 맥 Metal GPU). 사용: PW=<playwright 폴더> CHROME=<크롬> node shots.mjs <주소> <결과 폴더>
// 휴대폰 390x844: 설정 패널(PERFORMANCE OFF → ON), 성능 표시 메인·플레이·게임 오버. PC 1280x720: 설정 패널, 성능 표시 메인
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW);
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const report = { errors: [], logs: [] };

async function open(viewport, phone) {
  const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'v0112-')), {
    executablePath: process.env.CHROME, headless: true, viewport, deviceScaleFactor: phone ? 3 : 1, isMobile: phone, hasTouch: phone,
    args: ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
  const page = ctx.pages()[0];
  page.on('console', m => { if (m.type() === 'error') report.errors.push(m.text()); if (/^SETTINGS/.test(m.text())) report.logs.push(m.text()); });
  page.on('pageerror', e => report.errors.push(String(e)));
  await page.goto(url);
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 600000 });
  await page.waitForTimeout(3000);
  return { ctx, page };
}

{ // 휴대폰
  const PHONE = { width: 390, height: 844 }, U = PHONE.width / 720, H = PHONE.height / U;
  const { ctx, page } = await open(PHONE, true);
  const tap = (x, y) => page.touchscreen.tap(x * U, y * U);
  await tap(720 - 20 - 96 - 48, 68);  // 톱니
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${out}/phone_settings_off.png` });
  // PERFORMANCE 줄: 패널은 화면 가운데, 줄은 위에서 TOP 150 + 4줄(MUSIC·SFX·VIBRATION·GRAPHICS) 아래
  const panelH = 150 + 6 * 96 + 28 + 60 + 44;
  await tap(360, H / 2 - panelH / 2 + 150 + 4 * 96 + 48);
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${out}/phone_settings_on.png` });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${out}/phone_overlay_menu.png` });
  await tap(360, 900);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${out}/phone_overlay_play.png` });
  await page.waitForTimeout(12000);  // 조작하지 않으면 부딪힌다
  await page.screenshot({ path: `${out}/phone_overlay_gameover.png` });
  await ctx.close();
}
{ // PC
  const { ctx, page } = await open({ width: 1280, height: 720 }, false);
  await page.keyboard.press('F3');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${out}/pc_overlay_menu.png` });
  await ctx.close();
}
fs.writeFileSync(`${out}/shots.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify(report));
