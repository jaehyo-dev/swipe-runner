// 이름이 바뀐 뒤 웹 기록 옮겨 오기 확인: 같은 주소(origin)에서 v0.8.2로 한 판 해 기록을 만든 뒤 v0.9.0을 연다.
// 웹의 user:// 도 이름을 따른다(/userfs/godot/app_userdata/<이름>). 두 빌드를 한 서버의 old/, new/에 둔다.
// 사용: PW=.. CHROME=.. node check_migrate.mjs <서버 주소(끝 /)> <결과 폴더>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [base, out] = process.argv.slice(2);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-'));
const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport: { width: 390, height: 844 }, args: ['--disable-audio-output'] });
const page = ctx.pages()[0] || await ctx.newPage();
const logs = [];
page.on('console', m => logs.push(m.type() + ' ' + m.text()));
page.on('pageerror', e => logs.push('error ' + String(e)));
await page.goto(base + 'old/?seed=143');
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(14000);  // 부딪히면 기록이 저장된다
await page.screenshot({ path: `${out}/migrate_old_gameover.png` });
await page.goto(base + 'new/?seed=143');
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/migrate_new_menu.png` });
await page.reload();  // 두 번째 열기: 이미 옮겼으니 0개
await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
console.log(JSON.stringify(logs.filter(l => /SAVE|^error/.test(l)), null, 1));
await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
