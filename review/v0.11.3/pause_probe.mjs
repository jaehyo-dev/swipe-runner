// v0.11.3 일시정지 → 3·2·1 → 이어 하기 뒤 소리 밀림 측정 (창 없이: 헤드리스 크롬 휴대폰 흉내 / 플레이라이트 WebKit 아이폰 흉내)
// 사용: PW=<playwright 폴더> [CHROME=<크롬>] node pause_probe.mjs <주소> <결과.json> <chromium|webkit> <pause|hide> <횟수>
// pause: ‖ 버튼 → 0.8초 → RESUME. hide: 탭 가림 이벤트 + 브라우저가 AudioContext를 재움(아이폰처럼) → 1초 → 다시 보임 → RESUME
// 한 판에 PER_RUN번 (장애물이 오기 전 짧게 달리며), 판이 모자라면 HOME → 다시 시작.
// 매번 잰다:
//  - game: 게임이 이어 한 뒤 남기는 "박자 오차"(화면 음악 시간 − 게임이 아는 재생 위치, 평균·최소~최대)
//  - lat: 실제 출력 지연(currentTime − getOutputTimestamp로 잰 지금 소리 나는 시각)과 브라우저가 알려 주는 지연(baseLatency+outputLatency)의 차이.
//         게임은 알려 주는 지연만 빼므로, 이 차이가 일시정지 전후로 바뀌면 그만큼 소리가 화면보다 밀린다 (장애물 도착 vs 박)
//  - sfx: 터치 → 효과음 start() 명령(ms), 명령 → 소리 시작 예약(when − currentTime, ms), 그 위에 실제 출력 지연
//  - state: RESUME을 누를 때 / 이어 한 뒤의 AudioContext 상태 (곡이 멈춘 자리에서 이어지는지는 tools/test_web_music.py가 확인)
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const pw = createRequire(import.meta.url)(process.env.PW);
const [url, out, engine = 'chromium', mode = 'pause', total = '10'] = process.argv.slice(2);
const PER_RUN = 2;
const INIT = `
window.pp = { n: 0, starts: [], stops: [], touches: [], lat: [] };
{ const S = AudioBufferSourceNode.prototype, st = S.start, sp = S.stop;
  S.start = function (when = 0, offset = 0, ...r) { const c = this.context; window.pp.ctx = c; this._pid = this._pid || ++window.pp.n;
    window.pp.starts.push({ id: this._pid, perf: performance.now(), now: c.currentTime, when, offset, dur: this.buffer ? this.buffer.duration : 0, loop: this.loop, loopEnd: this.loopEnd });
    return st.call(this, when, offset, ...r); };
  S.stop = function (when, ...r) { const c = this.context; window.pp.stops.push({ id: this._pid, perf: performance.now(), now: c.currentTime, when: when === undefined ? c.currentTime : when });
    return sp.call(this, when, ...r); }; }
document.addEventListener('touchstart', () => window.pp.touches.push(performance.now()), true);
document.addEventListener('keydown', () => window.pp.touches.push(performance.now()), true);
// 프레임마다 실제 출력 지연: 지금 렌더 시각(currentTime) − 지금 귀에 닿는 시각(출력 타임스탬프 + 그 뒤 흐른 시간)
{ const tick = () => { const c = window.pp.ctx; if (c && c.state === 'running' && c.getOutputTimestamp) { const s = c.getOutputTimestamp();
    if (s.performanceTime > 0) window.pp.lat.push([performance.now(), (c.currentTime - s.contextTime - (performance.now() - s.performanceTime) / 1000) * 1000, ((c.baseLatency || 0) + (c.outputLatency || 0)) * 1000]); }
  requestAnimationFrame(tick); }; requestAnimationFrame(tick); }
`;
const dev = pw.devices[engine === 'webkit' ? 'iPhone 13' : 'Pixel 7'];
const opts = engine === 'webkit' ? { ...dev, viewport: { width: 390, height: 844 } }
  : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, executablePath: process.env.CHROME,
      args: ['--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] };
const ctx = await pw[engine].launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'pp-')), { headless: true, ...opts });
const page = ctx.pages()[0] || await ctx.newPage();
const errors = [], drifts = [];
page.on('pageerror', e => errors.push(String(e)));
const starts = [];  // 판 시작 뒤 박자 오차 (일시정지 전 기준값)
page.on('console', m => { const t = m.text(); if (m.type() === 'error') errors.push(t); const d = t.match(/PAUSE (.+?) \d+초 박자 오차 평균 ([+-][\d.]+)ms \(([+-][\d.]+) ~ ([+-][\d.]+), (\d+)프레임\)/);
  if (d) (d[1] === '시작 뒤' ? starts : drifts).push(d.slice(2).map(Number)); });
await page.addInitScript(INIT);
await page.goto(url);
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 600000 });
await page.waitForTimeout(2000);
const U = 390 / 720, tap = (x, y) => page.touchscreen.tap(x * U, y * U), wait = ms => page.waitForTimeout(ms);
const now = () => page.evaluate(() => performance.now());
async function swipe(dx) {
  await wait(400);  // 앞 동작이 끝난 뒤에 (동작 중 입력은 저장됐다가 늦게 실행되어 지연이 섞인다)
  await page.evaluate(() => { window.pp.touches.length = 0; });
  const t = await now();
  // 터치 시작·이동·끝을 한 번에 (게임은 이동 거리로 스와이프를 알아챈다)
  if (engine === 'chromium') {
    const cdp = await ctx.newCDPSession(page);
    for (const [type, x] of [['touchStart', 360], ['touchMove', 360 + dx], ['touchEnd', null]])
      await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: x === null ? [] : [{ x: x * U, y: 900 * U }] });
    await cdp.detach();
  } else {  // 맥 WebKit은 터치 이벤트를 만들 수 없다: 방향키로 레인 이동 (키 누름 → 효과음)
    await page.keyboard.press(dx < 0 ? 'ArrowLeft' : 'ArrowRight');
  }
  await wait(300);
  return page.evaluate(t0 => { const pp = window.pp, c = pp.ctx, touch = pp.touches[0];
    const s = pp.starts.find(s => s.perf >= t0 && s.dur < 2);
    if (!s || touch === undefined) return null;
    const last = pp.lat.slice(-10), real = last.reduce((a, b) => a + b[1], 0) / Math.max(last.length, 1);
    return { cmd: +(s.perf - touch).toFixed(1), sched: +(Math.max(s.when - s.now, 0) * 1000).toFixed(1), real: +real.toFixed(1), total: +((s.perf - touch) + Math.max(s.when - s.now, 0) * 1000 + real).toFixed(1) }; }, t);
}
// 최근 ms 동안 [실제 출력 지연 평균, 알려 준 지연 평균]
const latWindow = (from, to) => page.evaluate(([from, to]) => { const l = window.pp.lat.filter(x => x[0] >= from && x[0] <= to);
  if (!l.length) return null; return [l.reduce((a, b) => a + b[1], 0) / l.length, l.reduce((a, b) => a + b[2], 0) / l.length].map(v => +v.toFixed(1)); }, [from, to]);
const state = () => page.evaluate(() => window.pp.ctx.state);

const rows = [];
let inRun = 0;
await tap(360, 900);  // 메인 화면에서 시작
await wait(1200);
for (let k = 0; k < +total; k++) {
  if (inRun === PER_RUN) {  // 장애물이 오기 전에 판을 바꾼다: 일시정지 → HOME → 시작
    await tap(68, 68); await wait(600); await tap(360, 800); await wait(2500); await tap(360, 900); await wait(1200); inRun = 0;
  }
  const before = await swipe(k % 2 ? 140 : -140);
  const tPause = await now();
  const latBefore = await latWindow(tPause - 400, tPause);
  if (mode === 'pause') { await tap(68, 68); await wait(800); }
  else {
    await page.evaluate(() => { Object.defineProperty(document, 'hidden', { value: true, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); window.pp.ctx.suspend(); });
    await wait(1000);
    await page.evaluate(() => { Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
    await wait(200);
  }
  const atResume = await state();
  await tap(360, 700);  // RESUME
  await wait(2000);      // 3·2·1 (100BPM 최대 1.8초) 뒤
  const tBack = await now();
  const after = await swipe(k % 2 ? -140 : 140);
  await wait(300);
  const latAfter = await latWindow(tBack, await now());
  rows.push({ k: k + 1, state: [atResume, await state()], latBefore, latAfter, sfxBefore: before, sfxAfter: after });
  console.log(JSON.stringify(rows[rows.length - 1]));
  inRun++;
}
await tap(68, 68); await wait(500);  // 마지막 이어 하기의 박자 오차 줄을 남기게 멈춘다
rows.forEach((r, i) => { r.game = drifts[i] || null; });
// 위: 이어 할 때마다 한 줄 (다음 일시정지 때 찍힌다)
const info = await page.evaluate(() => { const c = window.pp.ctx; return { rate: c.sampleRate, base: c.baseLatency, outLat: c.outputLatency, state: c.state, ua: navigator.userAgent }; });
fs.writeFileSync(out, JSON.stringify({ url, engine, mode, info, starts, rows, errors }, null, 1));
console.log('errors', errors.length);
await ctx.close();
