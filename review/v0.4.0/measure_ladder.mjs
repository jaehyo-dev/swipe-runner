// 처음부터 130BPM 두 바퀴까지 자동 플레이를 웹 빌드에서 재고, 곡 경계를 실제 AudioBuffer로 렌더링해 이음매를 검사한다.
// 사용: PW=<playwright> CHROME=<크로미움> node measure_ladder.mjs <측정 빌드 주소> <결과.json>  (도구 장면으로 내보낸 빌드: build_measure.sh)
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ladder-'));
const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport: { width: 390, height: 844 },
  // --disable-audio-output: 실제 장치 대신 타이머로 같은 Web Audio 렌더러를 돌린다. 이 기기의 헤드리스 크로미움은 실제 장치에서 빈 페이지의 AudioContext도 0.01초에 멈췄다 (2026-11-09 확인)
  args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu-rasterization', '--autoplay-policy=no-user-gesture-required', '--disable-audio-output'] });
const page = ctx.pages()[0] || await ctx.newPage();
const errors = []; let result = null;
page.on('console', m => { const t = m.text(); if (m.type() === 'error') errors.push(t); if (t.startsWith('RESULT ')) result = JSON.parse(t.slice(7)); });
page.on('pageerror', e => errors.push(String(e)));
await page.addInitScript(() => {
  const r = window.__rec = { frames: [], decode: {}, schedules: [], feedMax: 0 };
  let v;
  Object.defineProperty(window, 'gameMusic', { configurable: true, get: () => v, set: g => {
    const { alloc, feed, schedule } = g;
    g.alloc = (i, n, rate) => { r.decode[i] = { from: performance.now(), frames: n, rate }; return alloc(i, n, rate); };
    g.feed = (i, d) => { const t = performance.now(); feed(i, d); const e = performance.now(); r.feedMax = Math.max(r.feedMax, e - t); r.decode[i].to = e; };
    g.schedule = (i, at, blend) => { r.schedules.push({ step: i, at, blend, perf: performance.now(), ctx: window.gameAudioCtx.currentTime, pos: g.position() }); return schedule(i, at, blend); };
    v = g;
  } });
  let last = 0;
  const tick = now => { if (last) r.frames.push([+now.toFixed(1), +(now - last).toFixed(1)]); last = now; requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
});
await page.goto(url);
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000, polling: 100 });
// 오디오 시계 감시: 초마다 AudioContext 시간·상태를 남겨 멈춤을 찾는다 (음악 시계와 독립인 판단 근거)
await page.evaluate(() => { const c = window.gameAudioCtx, w = window.__rec.watch = [], st = window.__rec.states = [];
  c.addEventListener('statechange', () => st.push([performance.now(), c.state]));
  setInterval(() => w.push([+performance.now().toFixed(0), +c.currentTime.toFixed(3), c.state, +(c.outputLatency || 0).toFixed(3), +c.baseLatency.toFixed(3)]), 1000); });
const started = Date.now();
while (!result && Date.now() - started < 420000) await page.waitForTimeout(1000);
const rec = await page.evaluate(() => { const r = window.__rec; return { watch: r.watch, states: r.states, decode: r.decode, schedules: r.schedules, feedMax: r.feedMax, frames: r.frames, ready: window.gameReady, start: window.musicStart, rate: window.gameAudioCtx.sampleRate }; });
// 곡 경계 이음매: 게임과 같은 노드 구성으로 경계 앞뒤를 렌더링해, 뒤 곡과 앞 곡을 겹친 이론 값과 비교한다
const seams = await page.evaluate(async () => {
  const b = window.gameMusic.bufs, res = [];
  for (const k of Object.keys(b).map(Number).sort((x, y) => x - y)) {
    if (!b[k + 1]) continue;
    const A = b[k], B = b[k + 1], sr = A.sampleRate, pre = 0.1, blend = 0.005, total = 0.3;
    const off = new OfflineAudioContext(2, Math.round(total * sr), sr);
    const a = off.createBufferSource(), n = off.createBufferSource(), ga = off.createGain(), gn = off.createGain();
    a.buffer = A; a.loop = true; n.buffer = B; n.loop = true; a.connect(ga); ga.connect(off.destination); n.connect(gn); gn.connect(off.destination);
    ga.gain.setValueAtTime(1, pre); ga.gain.linearRampToValueAtTime(0, pre + blend);
    gn.gain.setValueAtTime(0, pre); gn.gain.linearRampToValueAtTime(1, pre + blend);
    a.start(0, A.duration - pre); a.stop(pre + blend); n.start(pre);
    const x = (await off.startRendering()).getChannelData(0), edge = Math.round(pre * sr), bl = B.getChannelData(0), al = A.getChannelData(0), N = al.length, nb = Math.round(blend * sr);
    let worst = 0, zeros = 0, run = 0, maxStep = 0;
    for (let i = edge - 200; i < edge + 2000; i++) {
      const rel = i - edge, ga2 = rel < 0 ? 1 : Math.max(0, 1 - rel / nb), gb2 = rel < 0 ? 0 : Math.min(1, rel / nb);
      const want = (ga2 ? al[(N + rel) % N] * ga2 : 0) + (gb2 ? bl[rel >= 0 ? rel : 0] * gb2 : 0);
      worst = Math.max(worst, Math.abs(x[i] - want));
      run = Math.abs(x[i]) < 1e-6 ? run + 1 : 0; zeros = Math.max(zeros, run);
      maxStep = Math.max(maxStep, Math.abs(x[i] - x[i - 1]));
    }
    let songStep = 0; for (let i = 1; i < N; i += 1) songStep = Math.max(songStep, Math.abs(al[i] - al[i - 1]));
    res.push({ from: k, to: k + 1, gap_frames: zeros, diff_from_ideal: worst, step_at_edge: maxStep, song_max_step: songStep });
  }
  return res;
});
const res = { url, watch: rec.watch, states: rec.states, result, schedules: rec.schedules, decode: rec.decode, feed_max_ms: rec.feedMax, rate: rec.rate, seams, errors };
const after = rec.frames.filter(f => f[0] >= rec.ready);
res.frames = { count: after.length, over33: after.filter(f => f[1] > 33).length, max: Math.max(...after.map(f => f[1])), p50: after.map(f => f[1]).sort((a, b) => a - b)[after.length >> 1], slow: after.filter(f => f[1] > 33).map(f => [+((f[0] - rec.ready) / 1000).toFixed(2), f[1]]) };
res.boundaries = rec.schedules.map(s => { const e = rec.start + s.at * 1000, near = after.filter(f => Math.abs(f[0] - e) < 2000); return { to: s.step, at: s.at, frame_max_2s: Math.max(...near.map(f => f[1])) }; });
fs.writeFileSync(out, JSON.stringify(res, null, 1));
const stalls = rec.watch.slice(1).filter((b, i) => Math.abs((b[0] - rec.watch[i][0]) / 1000 - (b[1] - rec.watch[i][1])) > 0.05);
res.audio_clock_stalls = stalls.length;
if (stalls.length) process.exitCode = 1; // 오디오 시계가 멈춘 측정은 믿을 수 없다
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(JSON.stringify({ frames: { ...res.frames, slow: undefined }, feed_max_ms: res.feed_max_ms, rate: rec.rate, errors: errors.length, result: !!result }));
await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
