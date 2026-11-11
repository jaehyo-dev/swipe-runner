// v0.9.1 GPU 측정 (Xvfb + d3d12, 창 없음, 60Hz): 첫 판 끊김과 일시정지 뒤 박자 오차.
// 1) 메인 화면이 뜨자마자(2단계 셰이더 준비가 끝나기 전) 시작 → 시작부터 12초 동안 rAF 간격, 33ms 넘는 프레임 수
// 2) 다시 시작 → 1.5초 뒤 ‖ → 1초 → RESUME → 3·2·1 → 이어 한 뒤 3초 박자 오차(PAUSE 로그). TRIALS번
// 사용: env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 1280x1024x24" node measure_play.mjs <주소> <결과.json> [TRIALS]
import { createRequire } from 'module'; import fs from 'fs';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, trialsArg] = process.argv.slice(2);
const trials = +(trialsArg || 3);
const browser = await chromium.launch({ executablePath: process.env.CHROME, headless: false, env: { ...process.env, GALLIUM_DRIVER: 'd3d12' },
  args: ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', '--ozone-platform=x11', '--use-angle=gl', '--enable-gpu', '--ignore-gpu-blocklist'] });
const vp = { width: 390, height: 844 }, s = Math.min(vp.width / 720, vp.height / 1280);
const page = await (await browser.newContext({ viewport: vp, deviceScaleFactor: process.env.FRAMES ? 1 : 2 })).newPage();
const logs = [], errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); if (/^(PAUSE|QUALITY|MUSIC)/.test(m.text())) logs.push(m.text()); });
page.on('pageerror', e => errors.push(String(e)));
await page.addInitScript(() => { window.__iv = []; let last = 0; const f = t => { if (last) window.__iv.push([t, t - last]); last = t; requestAnimationFrame(f); }; requestAnimationFrame(f); });
await page.goto(url);
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 180000, polling: 16 });
await page.mouse.click(vp.width / 2, vp.height * 0.7);  // 바로 시작
await page.waitForFunction(() => window.gameStarted > 0, null, { timeout: 60000, polling: 16 });
const waitStart = await page.evaluate(() => window.gameStarted - window.gameReady);
await page.waitForTimeout(12000);
const first = await page.evaluate(() => { const v = window.__iv.filter(([t]) => t > window.gameStarted && t < window.gameStarted + 12000).map(([, d]) => d); v.sort((a, b) => a - b);
  return { frames: v.length, over33: v.filter(d => d > 33.4).length, p99: +v[Math.floor(v.length * 0.99)].toFixed(1), max: +v[v.length - 1].toFixed(1),
    renderer: (() => { const g = document.createElement('canvas').getContext('webgl2'); const d = g.getExtension('WEBGL_debug_renderer_info'); return g.getParameter(d.UNMASKED_RENDERER_WEBGL); })() }; });
for (let i = 0; i < trials; i++) {
  await page.mouse.click(vp.width / 2, vp.height * 0.7);  // 게임 오버였으면 다시 시작 (아직 달리는 중이면 레인 이동 없이 탭만)
  await page.waitForTimeout(1500);
  await page.mouse.click(68 * s, 68 * s);  // ‖
  await page.waitForTimeout(1000);
  await page.mouse.click(vp.width / 2, 700 * s);  // RESUME
  if (i === 0 && process.env.FRAMES) {  // 첫 회: 3·2·1 → 이어 하기 GIF용 프레임
    fs.mkdirSync(process.env.FRAMES, { recursive: true });
    for (let k = 0, t0 = Date.now(); Date.now() - t0 < 2800; k++) await page.screenshot({ path: `${process.env.FRAMES}/${String(k).padStart(3, '0')}.png` });
    await page.waitForTimeout(3200);
  } else {
    await page.waitForTimeout(6000);
  }
}
const result = { first_run: { wait_start_ms: Math.round(waitStart), ...first }, logs, errors };
console.log(JSON.stringify(result, null, 1));
fs.writeFileSync(out, JSON.stringify(result, null, 1));
await browser.close();
