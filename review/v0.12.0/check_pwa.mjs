// v0.12.0 홈 화면 앱(PWA) 확인 (창 없이: 헤드리스 크롬 + 맥 GPU). 결과는 check_pwa.json과 캡처 PNG.
// 사용: PW=<playwright 폴더> CHROME=<크롬> node check_pwa.mjs <빌드 주소> <빌드 폴더> <결과 폴더>
// 1) manifest·서비스 워커 등록·설치 가능 여부(CDP Page.getAppManifest / getInstallabilityErrors)·캐시 목록
// 2) 첫 실행 vs 두 번째 실행(서비스 워커 캐시) 메인 화면까지 시간, 같은 네트워크 제한(20Mbps, 40ms)에서
// 3) 오프라인(네트워크 차단) 다시 열기 → 메인 화면까지 + 음악 파일을 캐시에서 받는지
// 4) 새 버전 흉내: 서비스 워커의 버전을 바꿔 두고 업데이트 확인 → UPDATE 표시 캡처 → UPDATE 탭 → 새 캐시만 남는지, UPDATE가 사라지는지
// 5) 캡처: 아이폰 사파리 흉내(안내), 안드로이드 설치 가능 흉내(INSTALL 탭 → prompt), 노치 흉내(393x852, ?safe=59,0,34,0) 메인·플레이, PC 1280x720
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, buildDir, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const report = { errors: [] };
const ARGS = ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', '--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'];
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const S = (vp) => Math.min(vp.width / 720, vp.height / 1280);  // 화면 단위 → CSS px

async function open(vp, opts = {}) {
  const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'v0120-')), {
    executablePath: process.env.CHROME, headless: true, viewport: vp, deviceScaleFactor: opts.dpr || 1,
    isMobile: !!opts.mobile, hasTouch: !!opts.mobile, userAgent: opts.ua, args: ARGS });
  const page = ctx.pages()[0] || await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error') report.errors.push(`${vp.width}x${vp.height}: ${m.text()}`); });
  page.on('pageerror', (e) => report.errors.push(String(e)));
  return { ctx, page };
}
const ready = (page) => page.waitForFunction(() => window.gameReady, null, { timeout: 180000 });
async function loadTime(page, q = '') {
  const t = Date.now();
  await page.goto(new URL(q, url).href);
  await ready(page);
  return Date.now() - t;
}
// 노치·홈 막대 흉내 (캔버스 위 DOM이라 캡처에 같이 찍힌다)
const NOTCH = `document.body.insertAdjacentHTML('beforeend', '<div style="position:fixed;z-index:9;left:50%;top:11px;width:125px;height:37px;margin-left:-62px;border-radius:19px;background:#000;outline:1px solid #444"></div><div style="position:fixed;z-index:9;left:50%;bottom:8px;width:140px;height:5px;margin-left:-70px;border-radius:3px;background:#fff"></div><div style="position:fixed;z-index:9;left:0;right:0;top:59px;border-top:1px dashed rgba(255,80,80,.7)"></div><div style="position:fixed;z-index:9;left:0;right:0;bottom:34px;border-top:1px dashed rgba(255,80,80,.7)"></div>')`;
async function tap(page, vp, x, y) {  // 화면 단위(720 기준) 좌표 → 터치
  const k = S(vp);
  await page.touchscreen.tap(x * k, y * k);
}

// 1~3) 설치 가능·캐시·두 번째 실행·오프라인 (휴대폰 크기)
{
  const vp = { width: 390, height: 844 };
  const { ctx, page } = await open(vp, { mobile: true, dpr: 3 });
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  const net = { offline: false, latency: 40, downloadThroughput: 20e6 / 8, uploadThroughput: 5e6 / 8 };
  await cdp.send('Network.emulateNetworkConditions', net);
  report.firstLoadMs = await loadTime(page);
  await page.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 120000 });
  report.manifest = (await cdp.send('Page.getAppManifest')).data;
  report.manifest = JSON.parse(report.manifest);
  report.installabilityErrors = (await cdp.send('Page.getInstallabilityErrors').catch((e) => ({ installabilityErrors: [String(e)] }))).installabilityErrors;
  report.caches = await page.evaluate(async () => Object.fromEntries(await Promise.all((await caches.keys()).map(async (k) => [k, (await (await caches.open(k)).keys()).length]))));
  report.secondLoadMs = await loadTime(page);
  report.secondFromSW = await page.evaluate(() => performance.getEntriesByType('resource').filter((r) => /index\.(wasm|pck)$/.test(r.name)).map((r) => [r.name.split('/').pop(), r.deliveryType || '', Math.round(r.duration)]));
  await cdp.send('Network.emulateNetworkConditions', { ...net, offline: true });
  await ctx.setOffline(true);
  report.offlineLoadMs = await loadTime(page).catch((e) => 'FAIL ' + e.message.split('\n')[0]);
  report.offlineMusic = await page.evaluate(() => fetch('music/bgm_160_b.ogg').then((r) => r.status + ' ' + r.headers.get('content-length'), (e) => 'FAIL ' + e));
  await page.screenshot({ path: path.join(out, 'offline_phone.png') });
  await ctx.setOffline(false);
  await cdp.send('Network.emulateNetworkConditions', { ...net, offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });

  // 4) 새 버전 흉내: 서버의 서비스 워커만 버전을 바꾼다 (파일은 같고 캐시 이름이 바뀜)
  const swPath = path.join(buildDir, 'index.service.worker.js');
  const swOld = fs.readFileSync(swPath, 'utf8');
  const oldName = Object.keys(report.caches)[0];
  try {
    fs.writeFileSync(swPath, swOld.replace(/const VERSION = '([^']+)'/, "const VERSION = '$1-next'"));
    await page.evaluate(() => navigator.serviceWorker.getRegistration().then((r) => r.update()));
    await page.waitForFunction(() => window.pwa.state().includes('update'), null, { timeout: 120000 });
    await page.waitForTimeout(800);  // 게임이 0.5초마다 읽는다
    await page.screenshot({ path: path.join(out, 'update_phone.png') });
    const vis = { h: vp.height / S(vp) };
    const nav = page.waitForEvent('framenavigated', { timeout: 15000 });
    await tap(page, vp, 720 - 20 - 50, vis.h - 20 - 28);  // 오른쪽 아래 UPDATE
    await nav;
    await ready(page);
    report.update = await page.evaluate(async () => ({ caches: await caches.keys(), state: window.pwa.state() }));
    report.update.oldCacheGone = !report.update.caches.includes(oldName);
  } catch (e) {
    report.update = 'FAIL ' + e.message.split('\n')[0];
  } finally {
    fs.writeFileSync(swPath, swOld);
  }
  await ctx.close();
}

// 5) 캡처
{  // 아이폰 브라우저 흉내 (393x852): 설치 안내 → × 닫기 → 다시 열어도 안 뜸
  const vp = { width: 393, height: 852 };
  const { ctx, page } = await open(vp, { mobile: true, dpr: 3, ua: IPHONE_UA });
  await loadTime(page);
  await page.waitForTimeout(1200);
  report.iosState = await page.evaluate(() => window.pwa.state());
  await page.screenshot({ path: path.join(out, 'ios_hint_phone.png') });
  await tap(page, vp, 395, 20 + 48);  // × 가운데 (ios_hint_phone.png에서 잰 자리)
  await page.waitForTimeout(800);
  report.iosAfterClose = await page.evaluate(() => [window.pwa.state(), localStorage.getItem('pwaHintClosed'), window.gameStarted || null]);
  await loadTime(page);
  report.iosAfterReload = await page.evaluate(() => window.pwa.state());
  await ctx.close();
}
{  // 노치 흉내 홈 화면 앱: 메인·플레이
  const vp = { width: 393, height: 852 };
  const { ctx, page } = await open(vp, { mobile: true, dpr: 3 });
  await loadTime(page, '?safe=59,0,34,0&seed=7');
  await page.waitForTimeout(1200);
  await page.evaluate(NOTCH);
  await page.screenshot({ path: path.join(out, 'safe_menu_phone.png') });
  await tap(page, vp, 360, 1000);
  await page.waitForTimeout(900);  // 첫 장애물 전
  await page.screenshot({ path: path.join(out, 'safe_play_phone.png') });
  await ctx.close();
}
{  // 안드로이드 설치 가능 흉내: beforeinstallprompt를 직접 보낸다 → INSTALL → 누르면 prompt()
  const vp = { width: 390, height: 844 };
  const { ctx, page } = await open(vp, { mobile: true, dpr: 3 });
  await loadTime(page);
  await page.evaluate(() => { const e = new Event('beforeinstallprompt', { cancelable: true }); e.prompt = () => { window.prompted = (window.prompted || 0) + 1; window.promptActive = navigator.userActivation.isActive; return Promise.resolve(); }; window.dispatchEvent(e); });
  await page.waitForTimeout(1200);
  report.androidState = await page.evaluate(() => window.pwa.state());
  await page.screenshot({ path: path.join(out, 'install_phone.png') });
  await tap(page, vp, 20 + 60, 20 + 48);
  await page.waitForTimeout(800);
  report.androidAfterTap = await page.evaluate(() => [window.prompted || 0, window.promptActive, window.pwa.state(), window.gameStarted || null]);  // 설치 창을 연 횟수, 그때 사용자 활성화, 상태, 시작 안 함
  await ctx.close();
}
{  // PC 메인
  const vp = { width: 1280, height: 720 };
  const { ctx, page } = await open(vp);
  await loadTime(page);
  await page.waitForTimeout(1200);
  report.pcState = await page.evaluate(() => window.pwa.state());
  await page.screenshot({ path: path.join(out, 'menu_pc.png') });
  await ctx.close();
}
fs.writeFileSync(path.join(out, 'check_pwa.json'), JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
