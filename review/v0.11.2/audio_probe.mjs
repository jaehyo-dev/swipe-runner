// 오디오 그래프 조사: 표본율·지연·드라이버 노드·워클릿 수·포트 메시지·출력 시계 밀림
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW);
const [url, out, throttle = '1'] = process.argv.slice(2);
const INIT = `
window.ap = { worklets: {}, sp: [], sources: 0, msgs: 0, stamps: [], ctx: null };
{ const A = window.AudioContext; window.AudioContext = class extends A { constructor(o) { super(o); window.ap.ctx = this; window.ap.opts = JSON.stringify(o || {});
    const sp = this.createScriptProcessor.bind(this); this.createScriptProcessor = (...a) => { window.ap.sp.push(a); return sp(...a); };
    const bs = this.createBufferSource.bind(this); this.createBufferSource = () => { window.ap.sources++; return bs(); }; } }; }
{ const W = window.AudioWorkletNode; window.AudioWorkletNode = class extends W { constructor(c, name, o) { super(c, name, o); window.ap.worklets[name] = (window.ap.worklets[name] || 0) + 1;
    this.port.addEventListener('message', () => window.ap.msgs++); this.port.start(); } }; }
{ const tick = () => { const c = window.ap.ctx; if (c && c.state === 'running' && c.getOutputTimestamp) { const s = c.getOutputTimestamp(); window.ap.stamps.push([s.contextTime, s.performanceTime, c.currentTime, performance.now()]); } requestAnimationFrame(tick); }; requestAnimationFrame(tick); }
`;
const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'ap-')), {
  executablePath: process.env.CHROME, headless: true, viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const page = ctx.pages()[0];
const errors = []; page.on('pageerror', e => errors.push(String(e))); page.on('console', m => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(INIT);
await page.goto(url);
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 600000 });
await page.waitForTimeout(3000);
if (+throttle > 1) await (await ctx.newCDPSession(page)).send('Emulation.setCPUThrottlingRate', { rate: +throttle });
const U = 390 / 720, tap = (x, y) => page.touchscreen.tap(x * U, y * U);
await page.evaluate(() => { window.ap.msgs = 0; window.ap.stamps = []; });
const t0 = Date.now();
await tap(360, 900);
// 20초: 0.35초마다 좌우 스와이프(효과음), 죽으면 다시 시작
while (Date.now() - t0 < 20000) {
  const x = Math.random() < 0.5 ? 200 : 520;
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 360 * U, y: 900 * U }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x * U, y: 900 * U }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
  await page.waitForTimeout(350);
}
const r = await page.evaluate(() => { const c = window.ap.ctx, st = window.ap.stamps;
  // 출력 시계 밀림: (contextTime - performanceTime) 이 0.5초 창의 최댓값 기준으로 15ms 넘게 떨어진 횟수
  let drops = 0, base = null, worst = 0; const off = st.map(s => s[0] * 1000 - s[1]);
  for (let i = 0; i < off.length; i += 30) { const m = Math.max(...off.slice(i, i + 30)); if (base === null) base = m; else { if (base - m > 15) { drops++; worst = Math.max(worst, base - m); } base = m; } }
  const steps = []; for (let i = 1; i < st.length; i++) steps.push((st[i][2] - st[i-1][2]) * 1000);
  return { opts: window.ap.opts, rate: c.sampleRate, base: c.baseLatency, outLat: c.outputLatency, state: c.state, sp: window.ap.sp, worklets: window.ap.worklets, sources: window.ap.sources,
    msgsPerSec: Math.round(window.ap.msgs / 20), frames: st.length, drops, worstMs: Math.round(worst), currentTimeStepMax: Math.max(...steps).toFixed(1) }; });
r.errors = errors; r.throttle = throttle;
fs.writeFileSync(out, JSON.stringify(r, null, 1)); console.log(JSON.stringify(r));
await ctx.close();
