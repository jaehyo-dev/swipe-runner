// 웹 빌드 캡처: 휴대폰 4장(대기·달림·게임 오버·재시작), PC 2장(달림·게임 오버). 콘솔 오류도 모은다.
// 사용: PW=.. CHROME=.. node check_web.mjs <주소> <결과 폴더>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
const report = {};
for (const [name, viewport, shots] of [['phone', { width: 390, height: 844 }, 4], ['pc', { width: 1280, height: 720 }, 2]]) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'check-'));
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport, args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu-rasterization', '--disable-audio-output', '--autoplay-policy=no-user-gesture-required'] });
  const page = ctx.pages()[0] || await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto(url + '?seed=143');
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
  await page.waitForTimeout(300);
  if (shots === 4) await page.screenshot({ path: `${out}/${name}_wait.png` });
  await page.keyboard.press('ArrowLeft'); // 시드 143의 첫 장애물을 피하고 더 달린다
  await page.waitForTimeout(1700); // v0.6.3: 속도 15에서 첫 줄이 2.4초에 닿으므로 그 전에 찍는다
  await page.screenshot({ path: `${out}/${name}_run.png` });
  await page.waitForTimeout(10500); // 그대로 두면 부딪힌다
  await page.screenshot({ path: `${out}/${name}_gameover.png` });
  if (shots === 4) {
    await page.keyboard.press('Space');
    await page.waitForTimeout(150); // 물방울과 장애물이 '퐁' 솟는 중
    await page.screenshot({ path: `${out}/${name}_restart.png` });
  }
  report[name] = { errors, renderer: await page.evaluate(() => { const g = document.createElement('canvas').getContext('webgl2'); const e = g.getExtension('WEBGL_debug_renderer_info'); return g.getParameter(e ? e.UNMASKED_RENDERER_WEBGL : g.RENDERER); }) };
  await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
}
console.log(JSON.stringify(report));
