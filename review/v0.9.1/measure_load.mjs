// 첫 로딩 시간: 크롬 DevTools 'Fast 4G' 속도 제한(다운 9Mbps×0.9, 업 1.5Mbps×0.9, 지연 60ms×2.75), 캐시 없음.
// 잼: 로딩 화면이 보인 시각(#loading이 그려진 첫 시각, 없으면 null), 메인 화면이 뜬 시각(window.gameReady), 파일별 받은 크기·끝난 시각.
// 사용: PW=.. CHROME=.. node measure_load.mjs <주소> <결과.json> [횟수]
import { createRequire } from 'module'; import fs from 'fs';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, runsArg] = process.argv.slice(2);
const runs = +(runsArg || 1), results = [];
// GPU=1: Xvfb 안의 창(화면에는 안 보임)에서 d3d12 GPU로 그린다 (DESKTOP_NOTES.md). 아니면 헤드리스 소프트웨어 렌더링
const gpu = process.env.GPU === '1';
const browser = await chromium.launch({ executablePath: process.env.CHROME, headless: !gpu, env: gpu ? { ...process.env, GALLIUM_DRIVER: 'd3d12' } : process.env,
  args: ['--disable-audio-output', ...(gpu ? ['--ozone-platform=x11', '--use-angle=gl', '--enable-gpu', '--ignore-gpu-blocklist'] : [])] });
for (let i = 0; i < runs; i++) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 60 * 2.75, downloadThroughput: 9e6 / 8 * 0.9, uploadThroughput: 1.5e6 / 8 * 0.9 });
  const files = {};
  cdp.on('Network.loadingFinished', e => { files[e.requestId] = { ...files[e.requestId], bytes: e.encodedDataLength, end: e.timestamp }; });
  cdp.on('Network.requestWillBeSent', e => { files[e.requestId] = { url: e.request.url.split('/').pop().split('?')[0], start: e.timestamp }; });
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'commit' });
  // 로딩 화면이 처음 보인 시각: 페이지가 스스로 기록 (없는 빌드는 null)
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 180000, polling: 50 });
  const r = await page.evaluate(() => ({ gl: (() => { const g = document.createElement('canvas').getContext('webgl2'); const d = g?.getExtension('WEBGL_debug_renderer_info'); return d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : null; })(), loadingShown: window.loadingShown ?? null, ready: window.gameReady, nav: performance.timeOrigin }));
  const navStart = Object.values(files).reduce((m, f) => Math.min(m, f.start ?? 1e18), 1e18);
  const list = Object.values(files).filter(f => f.end).map(f => ({ file: f.url || '(page)', kb: +(f.bytes / 1024).toFixed(0), done_s: +(f.end - navStart).toFixed(2) })).sort((a, b) => a.done_s - b.done_s);
  // 메인 화면 뒤에 받는 파일이 있으면 끝까지 기다려 크기를 남긴다
  await page.waitForTimeout(15000);
  const later = Object.values(files).filter(f => f.end && f.end - navStart > r.ready / 1000).map(f => f.url);
  results.push({ renderer: r.gl, loading_s: r.loadingShown == null ? null : +(r.loadingShown / 1000).toFixed(2), main_s: +(r.ready / 1000).toFixed(2), files: list,
    total_kb_before_main: list.filter(f => f.done_s <= r.ready / 1000).reduce((s, f) => s + f.kb, 0), later_files: later, errors });
  console.log(JSON.stringify(results.at(-1)));
  await ctx.close();
}
await browser.close();
fs.writeFileSync(out, JSON.stringify(results, null, 1));
