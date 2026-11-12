// v0.10.0 웹 확인 (창 없이: 헤드리스, 화면 확인용)
// 1) 휴대폰 390x844, PC 1280x720: 메인(DAILY 버튼·점) → D 키로 오늘의 판 시작 화면 → 시작 → 가만히 있다가 부딪힘 → 게임 오버(SHARE)
//    → SHARE 누름(COPIED, 클립보드 글) → 다시 시작 → 집 → 메인(점 사라짐)
// 2) ?dailyhash=1: 웹(wasm)에서 계산한 날짜 30개 지문 표 (DAILYHASH 콘솔)
// 콘솔 오류는 모두 모은다. 사용: PW=<playwright 폴더> CHROME=<브라우저> node check_web.mjs <주소> <결과 폴더>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const report = { errors: [], logs: [], clipboard: {}, hash: '' };
const S = vp => Math.min(vp.width / 720, vp.height / 1280);  // 720x1280 기준 → 화면 (stretch expand)

async function open(vp) {
  const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'v0100-')), { executablePath: process.env.CHROME, headless: true, viewport: vp, args: ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required'] });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(url).origin });
  const page = ctx.pages()[0] || await ctx.newPage();
  page.on('console', m => {
    const t = m.text();
    if (m.type() === 'error') report.errors.push(`${vp.width}x${vp.height}: ${t}`);
    if (t.startsWith('DAILYHASH') || /^(#\d+ |ALL )/.test(t)) report.hash += t + '\n';  // 엔진이 줄마다 따로 찍는다
  });
  page.on('pageerror', e => report.errors.push(`${vp.width}x${vp.height}: ${e}`));
  return { ctx, page };
}
const ready = page => page.waitForFunction(() => window.gameReady > 0, null, { timeout: 240000 });

for (const [name, vp] of [['phone', { width: 390, height: 844 }], ['pc', { width: 1280, height: 720 }]]) {
  const { ctx, page } = await open(vp);
  await page.goto(url);
  await ready(page);
  await page.waitForTimeout(3000);  // 2단계 셰이더 준비
  await page.screenshot({ path: `${out}/menu_${name}.png` });
  await page.keyboard.press('d');
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${out}/daily_start_${name}.png` });
  await page.keyboard.press('ArrowUp');  // 시작 (동작은 아님)
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${out}/daily_play_${name}.png` });
  await page.waitForTimeout(12000);  // 가만히 있으면 가운데 레인 장애물에 부딪힌다
  await page.screenshot({ path: `${out}/daily_over_${name}.png` });
  // SHARE 가운데: 세로는 다시 시작 안내(가운데 + 370) 아래 100 + 반 높이 38, 가로는 위에서 384 + 56 + 38 (720x1280 기준)
  const s = S(vp), portrait = vp.height >= vp.width;
  await page.mouse.click(vp.width / 2, portrait ? vp.height / 2 + 508 * s : 478 * s);
  await page.waitForTimeout(250);
  await page.screenshot({ path: `${out}/daily_copied_${name}.png` });
  report.clipboard[name] = await page.evaluate(() => navigator.clipboard.readText().catch(e => 'ERR ' + e));
  await page.waitForTimeout(1000);
  await page.mouse.click(68 * s, 68 * s);  // 왼쪽 위 집
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/menu_after_${name}.png` });
  await ctx.close();
}

{
  const { ctx, page } = await open({ width: 390, height: 844 });
  await page.goto(url + '?dailyhash=1');
  await ready(page);
  await ctx.close();
}
fs.writeFileSync(`${out}/check_web.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ errors: report.errors, clipboard: report.clipboard }, null, 2));
