// v0.11.1 휴대폰 흉내 확인 (창 없이: 헤드리스 크롬 + 맥 Metal GPU).
// 사용: PW=<playwright 폴더> CHROME=<크롬> DEBUG=pw:browser node phone_web.mjs <주소> <결과 폴더> perf <이름>
//       PW=... CHROME=... node phone_web.mjs <주소> <결과 폴더> shots
// perf: 390x844, 배율 3, 터치, CPU 4배 느리게, ?bpm=160 → 메인 4초 + 시작 뒤 12초의 rAF 간격, 긴 작업(longtask), 가비지 수집(--trace-gc), 캔버스 크기
// shots: 효과 단계 0~4 × 스킨 MINT·NIGHT·AURORA 달리기, 성능 표시(메인·플레이), GRAPHICS 설정, 10000점 연출 GIF 프레임(?points=9990)
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, mode, label = 'run'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const PHONE = { width: 390, height: 844 };
const U = PHONE.width / 720;  // UI 1단위 = CSS px (세로 화면은 폭이 720에 맞는다)
const report = { errors: [], logs: [] };
const gc = [];

// 페이지가 열리기 전에: rAF 간격과 긴 작업을 모은다 (게임과 따로)
const INIT = `
window.probe = { on: false, frames: [], long: [] };
(() => { let last = 0; const tick = t => { if (window.probe.on && last) window.probe.frames.push(t - last); last = t; requestAnimationFrame(tick); }; requestAnimationFrame(tick); })();
try { new PerformanceObserver(l => { if (window.probe.on) for (const e of l.getEntries()) window.probe.long.push(e.duration); }).observe({ entryTypes: ['longtask'] }); } catch (e) {}
`;

async function open(query, throttle) {
  const args = ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist', '--js-flags=--trace-gc'];
  const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'v0111-')), {
    executablePath: process.env.CHROME, headless: true, viewport: PHONE, deviceScaleFactor: 3, isMobile: true, hasTouch: true, args,
    logger: { isEnabled: () => true, log: (name, sev, msg) => { if (/Scavenge|Mark-Compact|Mark-sweep/.test(String(msg))) gc.push(String(msg)); } },
  });
  const page = ctx.pages()[0] || await ctx.newPage();
  await page.addInitScript(INIT);
  page.on('console', m => {
    if (m.type() === 'error') report.errors.push(`${query}: ${m.text()}`);
    if (/^(QUALITY|SCORE V2|SAVE|SETTINGS)/.test(m.text())) report.logs.push(`${query}: ${m.text()}`);
  });
  page.on('pageerror', e => report.errors.push(`${query}: ${e}`));
  if (throttle) {
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
  }
  await page.goto(url + query);
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 600000 });
  await page.waitForTimeout(3000);  // 2단계 셰이더 준비
  return { ctx, page };
}

const tap = (page, x, y) => page.touchscreen.tap(x * U, y * U);  // UI 좌표(720 폭)로 누른다
const stats = a => {
  const s = [...a].sort((x, y) => x - y), q = p => s.length ? s[Math.min(s.length - 1, Math.floor((s.length - 1) * p))] : 0;
  return { frames: s.length, median: +q(0.5).toFixed(2), p95: +q(0.95).toFixed(2), p99: +q(0.99).toFixed(2), max: +q(1).toFixed(2), over25: s.filter(x => x > 25).length, over50: s.filter(x => x > 50).length };
};
async function window_(page, ms) {
  await page.evaluate(() => { window.probe.frames = []; window.probe.long = []; window.probe.on = true; });
  await page.waitForTimeout(ms);
  return page.evaluate(() => { window.probe.on = false; return { frames: window.probe.frames, long: window.probe.long }; });
}

if (mode === 'perf') {
  const { ctx, page } = await open('?seed=7&bpm=160', 4);
  const canvas = await page.evaluate(() => { const c = document.querySelector('canvas'); return { width: c.width, height: c.height, dpr: devicePixelRatio, css: [c.clientWidth, c.clientHeight] }; });
  const gc0 = gc.length;
  const menu = await window_(page, 4000);
  await tap(page, 360, 900);  // 탭(뗄 때)으로 시작
  const play = await window_(page, 12000);
  const gcLines = gc.slice(gc0);
  const pauses = gcLines.map(l => +(/([\d.]+) \/ [\d.]+ ms/.exec(l) || [0, 0])[1]).filter(x => x > 0);
  await page.keyboard.press('F3');  // 성능 표시 (고친 뒤 빌드만 있음)
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${out}/perf_${label}.png` });
  Object.assign(report, { label, canvas, menu: stats(menu.frames), play: stats(play.frames), longtasks: { count: play.long.length, total: Math.round(play.long.reduce((a, b) => a + b, 0)), max: Math.round(Math.max(0, ...play.long)) },
    gc: { count: gcLines.length, pauseTotal: +pauses.reduce((a, b) => a + b, 0).toFixed(1), pauseMax: +Math.max(0, ...pauses).toFixed(1), sample: gcLines.slice(0, 3) } });
  await ctx.close();
}

if (mode === 'shots') {
  for (const q of [0, 1, 2, 3, 4]) {  // 효과 단계별 × 스킨
    for (const skin of ['mint', 'night', 'aurora']) {
      const { ctx, page } = await open(`?seed=143&skin=${skin}&quality=${q}`, 0);
      await tap(page, 360, 900);
      await page.waitForTimeout(1800);
      await page.screenshot({ path: `${out}/q${q}_${skin}.png` });
      await ctx.close();
    }
  }
  {  // 성능 표시: 메인 화면에서 왼쪽 위 세 번 탭 → 플레이 중
    const { ctx, page } = await open('?seed=143', 0);
    for (let i = 0; i < 3; i++) { await tap(page, 199, 62); await page.waitForTimeout(120); }
    await page.waitForTimeout(1500);
    await page.screenshot({ path: `${out}/overlay_menu.png` });
    report.overlayStartedGame = await page.evaluate(() => window.gameStarted > 0);  // false여야 함
    await tap(page, 360, 900);
    await page.waitForTimeout(2500);
    await page.screenshot({ path: `${out}/overlay_play.png` });
    await ctx.close();
  }
  {  // GRAPHICS 설정: 톱니 → AUTO, 한 번 눌러 HIGH
    const { ctx, page } = await open('?seed=143', 0);
    await tap(page, 720 - 20 - 96 - 48, 68);
    await page.waitForTimeout(600);
    await page.screenshot({ path: `${out}/settings_auto.png` });
    await page.keyboard.press('Escape');
    await ctx.close();
  }
  {  // 10000점 연출: ?points=9990 은 다시 시작한 판부터 → 부딪힐 때까지 기다렸다 다시 시작, 게임을 5배 느리게 찍는다
    const { ctx, page } = await open('?seed=143&points=9990', 0);
    await page.keyboard.press('Space');
    await page.waitForTimeout(14000);
    await page.keyboard.press('Space');  // 다시 시작
    const dir = `${out}/gif_milestone`; fs.mkdirSync(dir, { recursive: true });
    const t0 = Date.now(); let i = 0;
    while (Date.now() - t0 < 2600) await page.screenshot({ path: `${dir}/${String(i++).padStart(3, '0')}.png`, clip: { x: 0, y: 0, width: 390, height: 260 } });
    report.milestoneFrames = i;
    await page.waitForTimeout(1500);
    await page.screenshot({ path: `${out}/milestone_after.png` });
    await ctx.close();
  }
}

fs.writeFileSync(`${out}/${mode === 'perf' ? `perf_${label}` : 'shots'}.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify({ errors: report.errors.length, logs: report.logs.slice(0, 6), ...(mode === 'perf' ? { canvas: report.canvas, play: report.play, gc: report.gc.count, long: report.longtasks } : {}) }));
