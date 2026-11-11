// 첫 로딩 시간 (창 없이). 모드:
//   fast4g: 크롬 DevTools 'Fast 4G' (다운 9Mbps×0.9, 업 1.5Mbps×0.9, 지연 60ms×2.75), 캐시 없음, 첫 방문
//   wifi:   보통 와이파이 (다운 20Mbps, 업 10Mbps, 지연 20ms), 캐시 없음, 첫 방문
//   repeat: 와이파이 조건으로 한 번 연 뒤 같은 브라우저로 다시 방문 (캐시 사용) — 두 번째 방문만 기록
// 잼: 로딩 화면이 보인 시각(window.loadingShown), 메인 화면이 뜬 시각(window.gameReady), 파일별 크기·끝난 시각, 메인 화면 뒤에 받은 파일.
// GPU=1이면 Xvfb 안의 창에서 d3d12 GPU로 그린다 (DESKTOP_NOTES.md). SHOTS=폴더면 fast4g 첫 회에 로딩 화면 캡처.
// 사용: PW=.. CHROME=.. node measure_load.mjs <주소> <결과.json> <모드> [횟수]
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, mode, runsArg] = process.argv.slice(2);
const runs = +(runsArg || 1), results = [];
const NET = {
  fast4g: { latency: 60 * 2.75, downloadThroughput: 9e6 / 8 * 0.9, uploadThroughput: 1.5e6 / 8 * 0.9 },
  wifi: { latency: 20, downloadThroughput: 20e6 / 8, uploadThroughput: 10e6 / 8 },
};
const gpu = process.env.GPU === '1';
const browser = await chromium.launch({ executablePath: process.env.CHROME, headless: !gpu, env: gpu ? { ...process.env, GALLIUM_DRIVER: 'd3d12' } : process.env,
  args: ['--disable-audio-output', ...(gpu ? ['--ozone-platform=x11', '--use-angle=gl', '--enable-gpu', '--ignore-gpu-blocklist'] : [])] });
async function visit(ctx, net, cache, shots) {
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: !cache });
  await cdp.send('Network.emulateNetworkConditions', { offline: false, ...NET[net] });
  const files = {};
  cdp.on('Network.requestWillBeSent', e => { files[e.requestId] = { url: e.request.url.split('/').pop().split('?')[0] || '(page)', start: e.timestamp }; });
  cdp.on('Network.responseReceived', e => { if (files[e.requestId]) files[e.requestId].cached = e.response.fromDiskCache || e.response.fromMemoryCache || e.response.status === 304; });
  cdp.on('Network.loadingFinished', e => { if (files[e.requestId]) Object.assign(files[e.requestId], { bytes: e.encodedDataLength, end: e.timestamp }); });
  await page.goto(url, { waitUntil: 'commit' });
  if (shots) {  // 로딩 화면: 1초, 6초(받는 중), 메인 화면 직전
    await page.waitForTimeout(1000); await page.screenshot({ path: `${shots}/loading_1s.png` });
    await page.waitForTimeout(5000); await page.screenshot({ path: `${shots}/loading_6s.png` });
  }
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 180000, polling: 50 });
  const r = await page.evaluate(() => ({ shown: window.loadingShown ?? null, ready: window.gameReady,
    gl: (() => { const g = document.createElement('canvas').getContext('webgl2'); const d = g?.getExtension('WEBGL_debug_renderer_info'); return d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : null; })() }));
  await page.waitForTimeout(net === 'fast4g' ? 8000 : 3000);  // 메인 화면 뒤에 받는 음악
  const t0 = Math.min(...Object.values(files).map(f => f.start));
  const list = Object.values(files).filter(f => f.end).map(f => ({ file: f.url, kb: Math.round(f.bytes / 1024), cached: !!f.cached, done_s: +(f.end - t0).toFixed(2) })).sort((a, b) => a.done_s - b.done_s);
  const ready_s = r.ready / 1000;
  await page.close();
  return { renderer: r.gl, loading_s: r.shown == null ? null : +(r.shown / 1000).toFixed(2), main_s: +ready_s.toFixed(2),
    kb_before_main: list.filter(f => f.done_s <= ready_s).reduce((s, f) => s + f.kb, 0),
    kb_after_main: list.filter(f => f.done_s > ready_s).reduce((s, f) => s + f.kb, 0),
    files: list, errors };
}
for (let i = 0; i < runs; i++) {
  // 두 번째 방문은 실제 브라우저처럼 디스크 캐시가 있는 프로필로 (임시 창 문맥은 메모리 캐시만 있어 큰 wasm을 담지 못한다)
  const ctx = mode === 'repeat'
    ? await chromium.launchPersistentContext(fs.mkdtempSync(os.tmpdir() + '/load-'), { executablePath: process.env.CHROME, headless: !gpu, viewport: { width: 390, height: 844 },
        env: gpu ? { ...process.env, GALLIUM_DRIVER: 'd3d12' } : process.env, args: ['--disable-audio-output', ...(gpu ? ['--ozone-platform=x11', '--use-angle=gl', '--enable-gpu', '--ignore-gpu-blocklist'] : [])] })
    : await browser.newContext({ viewport: { width: 390, height: 844 } });
  let r;
  if (mode === 'repeat') {
    await visit(ctx, 'wifi', true, null);
    r = await visit(ctx, 'wifi', true, null);
  } else {
    r = await visit(ctx, mode, false, i === 0 ? process.env.SHOTS : null);
  }
  results.push(r);
  console.log(JSON.stringify({ mode, loading_s: r.loading_s, main_s: r.main_s, kb_before_main: r.kb_before_main, kb_after_main: r.kb_after_main, errors: r.errors.length }));
  await ctx.close();
}
await browser.close();
fs.writeFileSync(out, JSON.stringify(results, null, 1));
