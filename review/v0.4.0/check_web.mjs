// 최종 웹 빌드: 첫 판 → 충돌 → 새로고침 뒤 기록 유지 → 새 기록 → 게임 오버 캡처. 콘솔 오류도 모은다.
// 사용: PW=.. CHROME=.. node check_web.mjs <주소> <결과 폴더>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
const SIZES = { phone: { width: 390, height: 844 }, pc: { width: 1280, height: 720 } };
const report = {};
const readBest = page => page.evaluate(() => new Promise(res => { // 엔진이 IndexedDB에 동기화한 파일을 직접 읽는다
  const open = indexedDB.open('/userfs'); open.onerror = () => res('열기 실패');
  open.onsuccess = () => { const tx = open.result.transaction('FILE_DATA'), st = tx.objectStore('FILE_DATA'), all = st.getAllKeys();
    all.onsuccess = () => { const k = all.result.find(x => String(x).endsWith('best.txt')); if (!k) return res(null); const g = st.get(k); g.onsuccess = () => res(new TextDecoder().decode(g.result.contents)); }; };
}));
for (const [name, viewport] of Object.entries(SIZES)) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'check-'));
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport, args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--autoplay-policy=document-user-activation-required', '--disable-audio-output'] });
  const page = ctx.pages()[0] || await ctx.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  const ready = () => page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
  const r = report[name] = {};
  await page.goto(url + '?seed=143'); await ready(); await page.waitForTimeout(300);
  await page.screenshot({ path: `${out}/${name}_wait.png` });
  // 첫 판: 그대로 두면 첫 장애물(시드 143은 내 레인)에 부딪혀 기록이 작다
  await page.keyboard.press('Space');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/${name}_first_run.png` });
  r.saved_during_first_run = await readBest(page); // 게임이 끝나기 전 저장 확인
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${out}/${name}_first_gameover.png` });
  await page.waitForTimeout(500);
  r.saved_after_crash = await readBest(page);
  await page.reload(); await ready(); await page.waitForTimeout(300);
  r.after_reload = await readBest(page);
  await page.screenshot({ path: `${out}/${name}_after_reload.png` });
  // 다음 판: 옆 레인으로 비켜 첫 기록을 넘긴다
  await page.keyboard.press('ArrowLeft');
  for (let i = 0; i < 60 && String(await readBest(page)) === String(r.after_reload); i++) await page.waitForTimeout(100);
  r.saved_on_new_record = await readBest(page);
  await page.waitForTimeout(150);
  await page.screenshot({ path: `${out}/${name}_new_best.png` });
  await page.waitForTimeout(13000);
  await page.screenshot({ path: `${out}/${name}_gameover.png` });
  await page.waitForTimeout(500);
  r.final = await readBest(page);
  // 재시작: 음악 위치가 0부터 다시 흐르고 다시 달린다
  await page.keyboard.press('Space'); await page.waitForTimeout(800);
  r.position_after_restart = await page.evaluate(() => window.gameMusic.position());
  await page.screenshot({ path: `${out}/${name}_restart.png` });
  r.errors = errors;
  await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
}
console.log(JSON.stringify(report, null, 1));
const bad = Object.values(report).some(r => r.errors.length || !(+r.final > +r.after_reload) || r.after_reload !== r.saved_after_crash || !(r.position_after_restart > 0.5 && r.position_after_restart < 1.1));
process.exit(bad ? 1 : 0);
