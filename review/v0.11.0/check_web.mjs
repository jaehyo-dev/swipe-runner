// v0.11.0 웹 확인 (창 없이: 헤드리스). 사용: PW=<playwright 폴더> CHROME=<브라우저> node check_web.mjs <주소> <결과 폴더> [sheet|ui]
// sheet: 휴대폰 390x844에서 스킨 8종 × (메인 / 달리기 / 점프 / 충돌), 높은(0)·낮은(4) 효과 단계. ?skin=all 로 모두 열고 → 넘기며 찍는다
// ui: 넘기기 GIF 프레임, 잠긴 스킨 탭 GIF 프레임, 메인(휴대폰·PC, 처음 3판 안내 보임), NEW SKIN 게임 오버(?orbs=499: 방울 하나면 GRAPE)
// 콘솔 오류는 모두 모은다 (check_web.json)
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out, mode = 'all'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const report = { errors: [], logs: [] };
const S = vp => Math.min(vp.width / 720, vp.height / 1280);
const PHONE = { width: 390, height: 844 }, PC = { width: 1280, height: 720 };
const SKINS = ['mint', 'strawberry', 'lemon', 'grape', 'soda', 'night', 'aurora', 'gold'];

async function open(vp, query) {
  const ctx = await chromium.launchPersistentContext(fs.mkdtempSync(path.join(os.tmpdir(), 'v0110-')), { executablePath: process.env.CHROME, headless: true, viewport: vp, args: ['--disable-audio-output', '--autoplay-policy=no-user-gesture-required', ...(process.env.GPU ? ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] : [])] });  // GPU=1: 창 없는 크롬 + 맥 GPU(Metal, 60Hz)
  const page = ctx.pages()[0] || await ctx.newPage();
  page.on('console', m => {
    if (m.type() === 'error') report.errors.push(`${vp.width}x${vp.height} ${query}: ${m.text()}`);
    if (/^QUALITY/.test(m.text())) report.logs.push(`${query}: ${m.text()}`);
  });
  page.on('pageerror', e => report.errors.push(`${vp.width}x${vp.height} ${query}: ${e}`));
  await page.goto(url + query);
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 240000 });
  await page.waitForTimeout(3000);  // 2단계 셰이더 준비
  return { ctx, page };
}

// 짧은 간격으로 연달아 찍는다 (GIF 프레임)
async function burst(page, dir, ms) {
  fs.mkdirSync(dir, { recursive: true });
  const t0 = Date.now(); let i = 0;
  while (Date.now() - t0 < ms) await page.screenshot({ path: `${dir}/${String(i++).padStart(3, '0')}.png` });
  return i;
}

if (mode === 'all' || mode === 'sheet') {
  for (const q of [0, 4]) {
    const { ctx, page } = await open(PHONE, `?seed=143&skin=all&quality=${q}`);
    const s = S(PHONE);
    for (const id of SKINS) {
      const dir = `${out}/sheet_q${q}`; fs.mkdirSync(dir, { recursive: true });
      await page.screenshot({ path: `${dir}/${id}_menu.png` });
      await page.keyboard.press('Space');  // 시작
      await page.waitForTimeout(2500);
      await page.screenshot({ path: `${dir}/${id}_run.png` });
      await page.keyboard.press('ArrowUp');  // 점프
      await page.waitForTimeout(200);
      await page.screenshot({ path: `${dir}/${id}_jump.png` });
      await page.waitForTimeout(11000);  // 가만히 있으면 가운데 레인 장애물에 부딪힌다
      await page.screenshot({ path: `${dir}/${id}_crash.png` });
      await page.mouse.click(68 * s, 68 * s);  // 왼쪽 위 집
      await page.waitForTimeout(1500);
      await page.keyboard.press('ArrowRight');  // 다음 스킨
      await page.waitForTimeout(800);
    }
    await ctx.close();
  }
}

if (mode === 'all' || mode === 'ui') {
  {  // 휴대폰: 처음 상태(민트만 열림, 안내 보임)
    const { ctx, page } = await open(PHONE, '?seed=143');
    await page.screenshot({ path: `${out}/menu_phone.png` });
    await ctx.close();
  }
  {  // GIF: 게임을 10배 느리게(?slow=0.1) 돌려 헤드리스 캡처 간격(약 0.1초)에도 프레임이 촘촘하게
    const { ctx, page } = await open(PHONE, '?seed=143&slow=0.1');
    await page.keyboard.press('ArrowRight');  // 다음 스킨(잠긴 딸기)
    report.flip = { frames: await burst(page, `${out}/gif_flip`, 4000), ms: 4000, slow: 0.1 };
    await page.screenshot({ path: `${out}/menu_locked_phone.png` });
    await page.mouse.click(PHONE.width / 2, PHONE.height * 0.62);  // 잠긴 딸기 탭 → 흔들림만
    report.locked = { frames: await burst(page, `${out}/gif_locked`, 6000), ms: 6000, slow: 0.1 };
    report.lockedStarted = await page.evaluate(() => window.gameStarted > 0);  // false여야 함
    await ctx.close();
  }
  for (const [name, vp] of [['phone', PHONE], ['pc', PC]]) {  // NEW SKIN: 방울 499 → 하나 먹으면 GRAPE
    const { ctx, page } = await open(vp, '?seed=143&orbs=499');
    if (name === 'pc') await page.screenshot({ path: `${out}/menu_pc.png` });
    await page.keyboard.press('Space');
    await page.waitForTimeout(13500);
    await page.screenshot({ path: `${out}/new_skin_${name}.png` });
    await ctx.close();
  }
}
if (mode === 'menu') {  // 빠른 확인: 스킨 8종 메인 화면만
  const { ctx, page } = await open(PHONE, '?seed=143&skin=all');
  for (const id of SKINS) {
    await page.screenshot({ path: `${out}/m_${id}.png` });
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(700);
  }
  await ctx.close();
}

if (mode === 'perf') {  // 프레임 측정 (GPU=1로): 스킨마다 시작부터 12초 rAF 간격. 가만히 있다 부딪혀도 그때까지의 프레임
  report.perf = {};
  for (const id of SKINS) {
    const { ctx, page } = await open(PHONE, `?seed=143&skin=${id}`);
    await page.evaluate(() => { window.__iv = []; let last = 0; const f = t => { if (last) window.__iv.push([t, t - last]); last = t; requestAnimationFrame(f); }; requestAnimationFrame(f); });
    await page.keyboard.press('Space');
    await page.waitForTimeout(12500);
    report.perf[id] = await page.evaluate(() => { const v = window.__iv.filter(([t]) => t > window.gameStarted + 500 && t < window.gameStarted + 12500).map(([, d]) => d); v.sort((a, b) => a - b);
      const g = document.createElement('canvas').getContext('webgl2'), d = g.getExtension('WEBGL_debug_renderer_info');
      return { frames: v.length, over20: v.filter(x => x > 20).length, p50: +v[Math.floor(v.length / 2)].toFixed(1), p99: +v[Math.floor(v.length * 0.99)].toFixed(1), max: +v[v.length - 1].toFixed(1), renderer: g.getParameter(d.UNMASKED_RENDERER_WEBGL) }; });
    await ctx.close();
  }
}
fs.writeFileSync(`${out}/check_web.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
