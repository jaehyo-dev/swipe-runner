// 웹 빌드의 로딩 후 첫 15초 프레임 시간을 잰다 (빌드를 고치지 않고 브라우저 쪽에서 기록). 콜드 시작을 위해 매번 새 프로필을 쓴다.
// 사용: PW=<playwright 경로> CHROME=<크로미움> node measure_frames.mjs <주소> <결과.json> <gpu|sw> '<시나리오 JSON [[초,키],...]>'
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, mode, scenario] = process.argv.slice(2);
const args = mode === 'sw' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu-rasterization'];
args.push('--autoplay-policy=document-user-activation-required'); // 실제 브라우저처럼 첫 입력 전엔 오디오가 잠김
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'frames-'));
const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, args, viewport: { width: 390, height: 844 } });
const page = ctx.pages()[0] || await ctx.newPage();
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push(String(e)));
await page.addInitScript(() => {
  const r = window.__rec = { frames: [], marks: [], statusHidden: 0, cur: { gl: 0, link: 0, compile: 0, upload: 0, audio: 0 } };
  const wrap = (proto, name, key) => { const f = proto[name]; if (!f) return; proto[name] = function (...a) { const t = performance.now(); const v = f.apply(this, a); r.cur.gl += performance.now() - t; if (key) r.cur[key]++; return v; }; };
  const G = WebGL2RenderingContext.prototype;
  wrap(G, 'compileShader', 'compile'); wrap(G, 'linkProgram', 'link'); wrap(G, 'getProgramParameter'); wrap(G, 'getShaderParameter');
  wrap(G, 'texImage2D', 'upload'); wrap(G, 'texSubImage2D', 'upload'); wrap(G, 'useProgram');
  // 어떤 소리가 처음 나는지는 버퍼 길이로 구별한다
  const names = [[0.1, 'lane'], [0.217, 'jump'], [0.267, 'slide'], [0.374, 'land'], [0.428, 'crash']];
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    const d = this.buffer ? this.buffer.duration : 0, hit = d > 10 ? 'music' : (names.find(n => Math.abs(n[0] - d) < 0.006) || [0, 'sfx' + d.toFixed(3)])[1];
    const t = performance.now(); const v = start.apply(this, a); r.marks.push([t, '소리:' + hit, performance.now() - t]); r.cur.audio += performance.now() - t; return v;
  };
  addEventListener('keydown', e => r.marks.push([performance.now(), '입력:' + e.key, 0]), true);
  const res = AudioContext.prototype.resume; AudioContext.prototype.resume = function () { const t = performance.now(); const v = res.apply(this); r.marks.push([t, 'AudioContext.resume', performance.now() - t]); return v; };
  let last = 0;
  const tick = now => {
    if (!r.statusHidden) { if (document.readyState !== 'loading' && !document.getElementById('status')) r.statusHidden = now; }
    if (last) { r.frames.push([now, now - last, +r.cur.gl.toFixed(1), r.cur.link, r.cur.compile, r.cur.upload]); }
    r.cur = { gl: 0, link: 0, compile: 0, upload: 0, audio: 0 }; last = now; requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});
const t0Load = Date.now();
await page.goto(url);
// 로딩 끝 = window.gameReady(READY=1) 또는, 없는 빌드는 로딩 표시가 사라진 때
await page.waitForFunction(() => window.__rec.statusHidden > 0, null, { timeout: 120000, polling: 50 });
const hasReady = process.env.READY === '1';
if (hasReady) await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000, polling: 50 });
const t0 = await page.evaluate(() => window.gameReady || window.__rec.statusHidden);
const steps = JSON.parse(scenario || '[]');
const renderer = await page.evaluate(() => { const g = document.createElement('canvas').getContext('webgl2'); const e = g.getExtension('WEBGL_debug_renderer_info'); return g.getParameter(e ? e.UNMASKED_RENDERER_WEBGL : g.RENDERER); });
for (const [sec, key] of steps) { const wait = t0 + sec * 1000 - await page.evaluate(() => performance.now()); if (wait > 0) await page.waitForTimeout(wait); await page.keyboard.press(key); }
await page.waitForTimeout(Math.max(0, t0 + 15000 - await page.evaluate(() => performance.now())));
const rec = await page.evaluate(() => window.__rec);
const frames = rec.frames.filter(f => f[0] >= t0 && f[0] <= t0 + 15000);
const slow = frames.filter(f => f[1] > 33).map(f => {
  const marks = rec.marks.filter(m => m[0] <= f[0] && m[0] > f[0] - f[1] - 17).map(m => m[1]);
  return { at: +((f[0] - t0) / 1000).toFixed(2), ms: +f[1].toFixed(1), gl_ms: f[2], link: f[3], compile: f[4], upload: f[5], marks };
});
const before = rec.frames.filter(f => f[0] < t0);
const ms = frames.map(f => f[1]).sort((a, b) => a - b);
const res = { url, mode, renderer, load_ms: Math.round(t0), t0_source: hasReady ? 'gameReady(가림막 걷힘)' : '로딩 표시 사라짐', frames: frames.length, p50: +ms[ms.length >> 1].toFixed(1), max: +ms[ms.length - 1].toFixed(1), over33: slow.length, slow,
  marks: rec.marks.filter(m => m[0] >= t0).map(m => [+((m[0] - t0) / 1000).toFixed(2), m[1], +m[2].toFixed(1)]), loading_frames_over33: before.filter(f => f[1] > 33).map(f => [+f[1].toFixed(0), f[3], f[4]]), errors };
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(JSON.stringify({ mode, renderer, load_ms: res.load_ms, frames: res.frames, p50: res.p50, max: res.max, over33: res.over33, errors: errors.length }));
await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
