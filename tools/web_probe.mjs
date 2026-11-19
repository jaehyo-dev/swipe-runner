// v0.12.1 휴대폰 화질·30fps 확인 도구 (결과: review/v0.12.1/README.md). 창 없이: 헤드리스 크롬 + 맥 Metal GPU, 393x852 배율 3, 터치)
// 사용: PW=<playwright 폴더> CHROME=<크롬> node tools/web_probe.mjs <주소> <결과 폴더> fps <30|60> <이름> [cpu 배율=4]
//       PW=... CHROME=... node tools/web_probe.mjs <주소> <결과 폴더> shots <이름> [추가 쿼리]
//       PW=... CHROME=... node tools/web_probe.mjs <주소> <결과 폴더> heat <이름> [메인 화면 초=60] [플레이 초=30]
// v0.12.2: fps 30j = 30Hz에 시드 고정으로 4% 정도 한 번 더 건너뛰기(50ms, 아이폰 저전력 모드 실측 33·46ms 흉내). N=입력 횟수(기본 18, 1.4초씩)
// heat: 발열 대리 지표. 메인 화면 가만히 / 플레이 중 브라우저 전체 프로세스(GPU 프로세스 포함) CPU 시간 비율, rAF·엔진 프레임 수, 그리는 횟수·삼각형·3D 화소(v0.12.2부터)
// fps: ?seed=7&bpm=160&probe=1 처음부터 160BPM, 시작 뒤 20초. rAF 간격 분포·튀는 프레임(앞 프레임의 1.5배 이상), 게임이 받은 프레임 시간·이동 거리·박자 오차,
//      1.1초마다 ←/→ 입력 → 동작까지 지연(ms), QUALITY 줄. 30이면 rAF를 한 번 건너 하나씩만 불러 30Hz 화면을 흉내 낸다 (아이폰 저전력 모드), mix는 16·33ms 섞기
//      게임 쪽 값(프레임 시간·이동·박자 오차·지연)은 ?probe=1이 있는 v0.12.1부터. 옛 버전은 rAF와 QUALITY 줄만
// shots: ?seed=7 시작 뒤 WAIT ms(기본 3500)에 화면 전체 (난간·블록·방울은 compare.py가 잘라 키운다). HZ=30·NOTAP=1이면 30Hz 메인 화면
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, mode, a1, a2, a3] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const PC = process.env.PC === '1';  // PC=1: 1280x720 배율 1, 마우스 (PC 화면 확인)
const PHONE = PC ? { width: 1280, height: 720 } : { width: 393, height: 852 };
const report = { errors: [], logs: [] };

const INIT = (hz) => `
window.probe = { on: false, frames: [], last: 0 };
${hz !== 60 ? `{ // 30Hz 흉내: 진짜 rAF를 두 번에 한 번만 넘긴다. mix: 시드 고정 난수로 16·33ms가 섞이게 (반쯤 건너뜀). 게임·엔진·이 측정 모두 같은 rAF를 쓴다
  const raf = window.requestAnimationFrame.bind(window); let queue = [], odd = false, seed = 7;
  const skip = () => ${hz === 30 ? '(odd = !odd, !odd)' : hz === '30j' ? '(odd = !odd, !odd || (seed = (seed * 1103515245 + 12345) % 2147483648, seed % 25 === 0))' : '(seed = (seed * 1103515245 + 12345) % 2147483648, seed % 3 === 0)'};
  const pump = t => { if (!skip()) { const q = queue; queue = []; for (const cb of q) cb(t); } raf(pump); };
  raf(pump); window.requestAnimationFrame = cb => { queue.push(cb); return queue.length; }; window.cancelAnimationFrame = () => {}; }` : ''}
{ const tick = t => { if (window.probe.on && window.probe.last) window.probe.frames.push(+(t - window.probe.last).toFixed(2)); window.probe.last = t; requestAnimationFrame(tick); }; requestAnimationFrame(tick); }
addEventListener('keydown', () => { window.keyAt = performance.now(); }, true);
`;

async function open(query, hz, throttle) {
  const args = ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'];
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'probe-'));
  const ctx = await chromium.launchPersistentContext(dir, {
    executablePath: process.env.CHROME, headless: true, viewport: PHONE, deviceScaleFactor: PC ? 1 : 3, isMobile: !PC, hasTouch: !PC, args,
  });
  const page = ctx.pages()[0] || await ctx.newPage();
  await page.addInitScript(INIT(hz));
  page.on('console', m => {
    if (m.type() === 'error') report.errors.push(`${query}: ${m.text()}`);
    if (/^(QUALITY|HEAT)/.test(m.text())) report.logs.push(`${(performance.now() / 1000).toFixed(1)}s ${m.text()}`);
  });
  page.on('pageerror', e => report.errors.push(`${query}: ${e}`));
  if (process.env.VERBOSE) page.on('console', m => console.log('console', m.type(), m.text().slice(0, 200)));
  await page.goto(url + query);
  await page.waitForFunction(() => window.gameReady > 0, null, { polling: 500, timeout: +(process.env.TIMEOUT || 600000) });
  await page.waitForTimeout(3000);  // 셰이더 준비
  if (throttle > 1) {
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
    await page.waitForTimeout(2000);
  }
  return { ctx, page, dir };
}

// 이 측정의 브라우저 프로세스들(사용자 폴더 이름으로 본체를 찾고 그 자식들: GPU·렌더러 포함)의 누적 CPU 시간(초)
import { execSync } from 'child_process';
const cpuTime = dir => {
  const rows = execSync('ps -A -o pid=,ppid=,time=,command=').toString().split('\n').filter(Boolean).map(l => { const [pid, ppid, t, ...cmd] = l.trim().split(/\s+/); return { pid, ppid, t, cmd: cmd.join(' ') }; });
  const ids = new Set(rows.filter(r => r.cmd.includes(path.basename(dir))).map(r => r.pid));
  for (let grew = true; grew;) { grew = false; for (const r of rows) if (ids.has(r.ppid) && !ids.has(r.pid)) { ids.add(r.pid); grew = true; } }
  const sec = t => { const p = t.split(':').map(Number); return p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1]; };
  return rows.filter(r => ids.has(r.pid)).reduce((sum, r) => sum + sec(r.t), 0);
};

const q = (s, p) => s.length ? s[Math.min(s.length - 1, Math.floor((s.length - 1) * p))] : 0;
const dist = a => { const s = [...a].sort((x, y) => x - y); return { n: s.length, median: q(s, 0.5), p95: q(s, 0.95), p99: q(s, 0.99), max: q(s, 1) }; };
const jumps = a => a.filter((x, i) => i > 0 && x >= a[i - 1] * 1.5).length;  // 튀는 프레임: 간격이 앞 프레임의 1.5배 이상
// 간격 막대: 4ms 칸
const hist = a => { const h = {}; for (const x of a) { const k = Math.floor(x / 4) * 4; h[k] = (h[k] || 0) + 1; } return Object.keys(h).map(Number).sort((x, y) => x - y).map(k => `${k}-${k + 4}ms ${h[k]}`); };

if (mode === 'fps') {
  const hz = ['mix', '30j'].includes(a1) ? a1 : +a1, label = a2, cpu = +(a3 || 4);
  const { ctx, page } = await open(process.env.Q || '?seed=7&bpm=160&probe=1', hz, cpu);
  await page.touchscreen.tap(PHONE.width / 2, PHONE.height * 0.7);  // 시작
  await page.waitForTimeout(1500);
  await page.evaluate(() => { window.probe.frames = []; window.probe.on = true; window.gameProbe = []; });
  const lag = [];
  for (let i = 0; i < +(process.env.N || 18); i++) {
    await page.waitForTimeout(1100);
    await page.evaluate(() => { window.gameActed = 0; });
    await page.keyboard.press(i % 2 ? 'ArrowRight' : 'ArrowLeft');
    await page.waitForTimeout(300);
    lag.push(await page.evaluate(() => window.gameActed ? +(window.gameActed - window.keyAt).toFixed(1) : null));
  }
  const r = await page.evaluate(() => { window.probe.on = false; return { frames: window.probe.frames, game: window.gameProbe.join(';').split(';').filter(Boolean).map(x => x.split(',').map(Number)) }; });
  const delta = r.game.map(g => g[0]), drift = r.game.map(g => Math.abs(g[2]));
  // 이동 고르기: 프레임마다 간 거리 ÷ 그 프레임의 rAF 간격 기대값... 대신 '거리 ÷ 게임 프레임 시간'의 흔들림과, 거리 자체의 앞 프레임 대비 튐
  const step = r.game.slice(1).map((g, i) => g[1] - r.game[i][1]);
  // 속도 고르기: 프레임마다 간 거리 ÷ 그 프레임 시간. 중앙값에서 벗어난 비율(%) — 16·33ms가 섞여도 작아야 한다
  const v = step.map((x, i) => x / r.game[i + 1][0]).filter(x => x > 0), vm = [...v].sort((x, y) => x - y)[v.length >> 1];
  const speed_dev = dist(v.map(x => +(Math.abs(x / vm - 1) * 100).toFixed(2)));
  const res = { label, hz, cpu, query: process.env.Q || '?seed=7&bpm=160&probe=1', raf: dist(r.frames), raf_jumps: jumps(r.frames), raf_hist: hist(r.frames), delta: dist(delta), delta_jumps: jumps(delta),
    speed_dev_pct: speed_dev, drift_abs: dist(drift), lag_ms: dist(lag.filter(x => x !== null)), lag_missing: lag.filter(x => x === null).length, quality: report.logs, errors: report.errors };
  fs.writeFileSync(path.join(out, `fps_${label}.json`), JSON.stringify({ ...res, raw: { frames: r.frames, game: r.game } }));
  console.log(JSON.stringify(res, null, 1));
  await ctx.close();
} else if (mode === 'shots') {
  const label = a1, extra = a2 || '';
  const { ctx, page } = await open('?seed=7' + extra, +(process.env.HZ || 60), 1);  // HZ=30: 저전력 안내 캡처
  if (!process.env.NOTAP) await (PC ? page.mouse.click(PHONE.width / 2, PHONE.height * 0.7) : page.touchscreen.tap(PHONE.width / 2, PHONE.height * 0.7));  // NOTAP=1: 메인 화면 그대로
  await page.waitForTimeout(+(process.env.WAIT || 3500));
  await page.screenshot({ path: path.join(out, `shot_${label}.png`) });
  for (let i = 1; i <= +(process.env.SERIES || 0); i++) {  // SERIES=n: 그 뒤 2초마다 n장 더 (2칸 벽 같은 장면 찾기, ?probe=1이면 부딪혀도 계속)
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(out, `shot_${label}_${i}.png`) });
  }
  const canvas = await page.evaluate(() => { const c = document.querySelector('canvas'); return [c.width, c.height]; });
  console.log(JSON.stringify({ label, canvas, errors: report.errors, quality: report.logs }));
  await ctx.close();
} else if (mode === 'heat') {
  const label = a1, menuSec = +(a2 || 60), playSec = +(a3 || 30);
  const { ctx, page, dir } = await open('?seed=7&probe=1', 60, 1);
  await page.waitForTimeout(+(process.env.SETTLE || 0) * 1000);  // SETTLE초: 메인 화면 음악 미리 풀기가 끝난 뒤 재기 (휴대폰 흉내는 처음 1~2분 디코딩이 CPU 대부분)
  const span = async (sec) => {
    const c0 = cpuTime(dir), d0 = await page.evaluate(() => { window.probe.frames = []; window.probe.on = true; return window.gameDraw || null; });
    await page.waitForTimeout(sec * 1000);
    const d1 = await page.evaluate(() => { window.probe.on = false; return window.gameDraw || null; });
    const raf = await page.evaluate(() => window.probe.frames.length);
    return { cpu_pct: +((cpuTime(dir) - c0) / sec * 100).toFixed(1), raf_fps: +(raf / sec).toFixed(1), engine_fps: d0 && d1 ? +((d1[6] - d0[6]) / sec).toFixed(1) : null,
      draws: d1 && d1[0], primitives: d1 && d1[1], render: d1 && `${d1[2]}x${d1[3]}`, pixels: d1 && d1[2] * d1[3], msaa: d1 && [0, 2, 4, 8][d1[4]], level: d1 && d1[5] };
  };
  const menu = await span(menuSec);
  await page.touchscreen.tap(PHONE.width / 2, PHONE.height * 0.7);
  await page.waitForTimeout(2000);
  const play = await span(playSec);
  const res = { label, menu, play, quality: report.logs, errors: report.errors };
  fs.writeFileSync(path.join(out, `heat_${label}.json`), JSON.stringify(res));
  console.log(JSON.stringify(res, null, 1));
  await ctx.close();
}
