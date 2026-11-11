// 크로미움에서 재는 프레임 시간. 측정 빌드(build_measure.sh)의 자동 플레이 1판 동안 requestAnimationFrame 간격과 자동 낮춤(QUALITY 줄)을 기록한다.
// v0.9.0: review/v0.8.1/measure_errors.mjs 복사본. 맥은 헤드리스(Metal) 그대로, WSL(데스크탑)은 창을 띄워 d3d12(RTX 4060)로. pmset은 맥에서만
// 맥북 전체 화면과 같은 캔버스: 1710x925, 화소 2배 = 3420x1850. 실제 창 측정은 measure_mac.mjs (사용자가 직접 실행)
// 사용: PW=<playwright> CHROME=<크로미움> node measure_headless.mjs <주소> <결과.json> <가로x세로> [uncapped]
import { createRequire } from 'module'; import { execSync } from 'child_process'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, size, cap] = process.argv.slice(2);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mac-'));
const [w, h] = size.split('x').map(Number);
const args = ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu-rasterization', '--autoplay-policy=no-user-gesture-required', '--disable-audio-output'];
if (cap === 'uncapped') args.push('--disable-gpu-vsync', '--disable-frame-rate-limit');  // 수직 동기를 꺼서 그리는 데 걸린 시간을 잰다
// WSL(데스크탑): 헤드리스는 소프트웨어 렌더링이라 창을 띄우고(headed) d3d12로 GPU를 쓴다. 맥은 그대로
const wsl = process.platform === 'linux' && /microsoft/i.test(os.release());
const gpu = wsl ? { headless: false, env: { ...process.env, GALLIUM_DRIVER: 'd3d12' } } : { headless: true };
if (wsl) args.splice(0, 1, '--use-angle=gl', '--enable-gpu');  // metal 대신 gl (나머지 플래그는 유지)
const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, ...gpu, viewport: { width: w, height: h }, deviceScaleFactor: 2, args });
const page = ctx.pages()[0] || await ctx.newPage();
if (/^cpu\d+$/.test(cap || '')) await (await ctx.newCDPSession(page)).send('Emulation.setCPUThrottlingRate', { rate: +cap.slice(3) });
const errors = []; let result = null;
page.on('console', m => { const t = m.text(); if (m.type() === 'error') errors.push(t); if (t.startsWith('RESULT ')) { errors.push('RESULT at ' + ((Date.now() - t0e) / 1000).toFixed(1)); try { result = JSON.parse(t.slice(7)); } catch (e) { errors.push('RESULT 해석 실패'); } } if (t.startsWith('QUALITY ')) levels.push(t.slice(8)); });
const levels = [];
const t0e = Date.now(); page.on('pageerror', e => errors.push(((Date.now() - t0e) / 1000).toFixed(1) + 's ' + String(e.stack).slice(0, 900)));
await page.addInitScript(() => {
  const r = window.__rec = [];
  let last = 0;
  const tick = now => { if (last) r.push(+(now - last).toFixed(2)); last = now; requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
});
await page.goto(url.startsWith('file:') || url.includes('blank') ? url : url + (url.includes('?') ? '&' : '?') + 'quiet=1');  // 스피커로 소리를 내지 않으면서 실제 오디오 장치 경로는 그대로 쓴다
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000, polling: 100 });
await page.evaluate(() => { window.__rec.length = 0; });
const env = await page.evaluate(() => { const c = document.querySelector('canvas') || { width: innerWidth * devicePixelRatio, height: innerHeight * devicePixelRatio }, g = document.createElement('canvas').getContext('webgl2'), e = g.getExtension('WEBGL_debug_renderer_info');
  return { inner: [innerWidth, innerHeight], dpr: devicePixelRatio, canvas: [c.width, c.height], screen: [screen.width, screen.height], ua: navigator.userAgent.match(/Chrome\/[\d.]+/)?.[0], gpu: g.getParameter(e ? e.UNMASKED_RENDERER_WEBGL : g.RENDERER) }; });
for (let i = 0; i < 400 && !result && errors.length < 20; i++) await page.waitForTimeout(1000);
const ms = await page.evaluate(() => window.__rec);
const therm = process.platform !== 'darwin' ? '해당 없음' : execSync('pmset -g therm').toString().match(/CPU_Speed_Limit\s*=\s*(\d+)/)?.[1] ?? '제한 없음';
let at = 0; const slow = []; for (const x of ms) { at += x; if (x > 20) slow.push([+(at / 1000).toFixed(2), x]); }
const sorted = [...ms].sort((a, b) => a - b), q = p => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
const bins = [[0, 9.5], [9.5, 12.5], [12.5, 18], [18, 25], [25, 33], [33, 1e9]].map(([a, b]) => ms.filter(x => x >= a && x < b).length);
const res = { url, load_end: os.loadavg().map(x => +x.toFixed(1)), therm, slow_frames: slow.slice(0, 60), size, cap: cap || 'vsync', env, frames: ms.length, fps: +(1000 * ms.length / ms.reduce((a, b) => a + b, 0)).toFixed(1), p50: q(0.5), p90: q(0.9), p99: q(0.99), max: sorted[sorted.length - 1], over33: ms.filter(x => x > 33).length, over20: ms.filter(x => x > 20).length, bins_ms: { '<9.5': bins[0], '9.5-12.5': bins[1], '12.5-18': bins[2], '18-25': bins[3], '25-33': bins[4], '>33': bins[5] },
  draw: result?.draw_calls, prims: result?.primitives, music: result?.music_time, crashes: result?.crashes, levels, render: result?.render_size, timing: { frame_err: result?.frame_err, wall_err: result?.wall_err, cross_wall: result?.cross_wall, cross_frame: result?.cross_frame, by_bpm: result?.by_bpm, rows_frame: result?.rows_frame }, segments: result?.segments?.length, jitter: result?.clock_jitter, errors };
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(JSON.stringify({ load: res.load_end[0], size, cap: res.cap, canvas: env.canvas, inner: env.inner, dpr: env.dpr, frames: res.frames, fps: res.fps, p50: res.p50, p99: res.p99, max: res.max, over33: res.over33, draw: res.draw?.mean, jitter: res.jitter, crashes: res.crashes, levels, errors: errors.length }));
await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
