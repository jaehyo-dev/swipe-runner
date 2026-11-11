// v0.9.0 웹 빌드 확인: 휴대폰 390x844·PC 1280x720에서 메인 화면 → 시작 → 게임 오버 → 집 버튼 → 메인 화면 → 소리 버튼.
// 캡처, 콘솔 오류, 그리고 소리: 출력 직전(destination)에 분석기를 붙여 구간마다 크기(dBFS)를 잰다.
// 자동 재생 허용 플래그를 주지 않는다: 실제 브라우저처럼 첫 입력 전에는 소리가 막혀야 한다.
// 사용: PW=.. CHROME=.. node check_web.mjs <주소> <결과 폴더>   (WSL·리눅스는 헤드리스 소프트웨어 렌더링으로 충분)
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const [url, out] = process.argv.slice(2);
const report = {};
for (const [name, viewport] of [['phone', { width: 390, height: 844 }], ['pc', { width: 1280, height: 720 }]]) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'check-'));
  const args = process.platform === 'darwin' ? ['--use-angle=metal', '--ignore-gpu-blocklist'] : [];
  const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport, args: [...args, '--disable-audio-output'] });
  const page = ctx.pages()[0] || await ctx.newPage();
  const errors = [], logs = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); if (/^(QUALITY|SAVE)/.test(m.text())) logs.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  await page.addInitScript(() => {
    // 출력으로 가는 모든 연결을 분석기에도 잇는다 (게임 소리 = 엔진 효과음 + 웹 음악)
    const connect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (dest, ...rest) {
      const c = this.context;
      if (dest === c.destination) {
        if (!c.__an) { c.__an = c.createAnalyser(); c.__an.fftSize = 2048; window.__an = c.__an; window.__ctx = c; }
        connect.call(this, c.__an);
      }
      return connect.call(this, dest, ...rest);
    };
  });
  // ms 동안 출력 크기(dBFS, RMS)와 오디오 상태
  const level = async ms => page.evaluate(async ms => {
    const an = window.__an, buf = new Float32Array(2048); let sum = 0, n = 0;
    for (const end = performance.now() + ms; performance.now() < end;) {
      if (an) { an.getFloatTimeDomainData(buf); for (const x of buf) sum += x * x; n += buf.length; }
      await new Promise(r => setTimeout(r, 40));
    }
    const rms = n ? Math.sqrt(sum / n) : 0;
    return { db: rms > 0 ? +(20 * Math.log10(rms)).toFixed(1) : -Infinity, state: window.gameAudioCtx?.state ?? '없음' };
  }, ms);
  const s = Math.min(viewport.width / 720, viewport.height / 1280);  // 720x1280 기준 → 화면 (stretch expand)
  const home = [68 * s, 68 * s], sound = [viewport.width - 68 * s, 68 * s];
  await page.goto(url + '?seed=143');
  await page.waitForFunction(() => window.gameReady > 0, null, { timeout: 120000 });
  await page.waitForTimeout(500);
  const r = {};
  r.menu_first = await level(800);
  await page.screenshot({ path: `${out}/${name}_menu_first.png` });
  await page.keyboard.press('ArrowLeft');  // 시작만 한다 (레인 이동 아님). 시드 143은 첫 장애물이 가운데로 와서 곧 부딪힌다
  await page.waitForTimeout(400);
  r.run = await level(1000);
  await page.screenshot({ path: `${out}/${name}_run.png` });
  await page.waitForTimeout(11000);  // 소프트웨어 렌더링은 느려 첫 충돌이 늦다 (시드 143은 100m 안팎에서 부딪힌다)
  await page.screenshot({ path: `${out}/${name}_gameover.png` });
  await page.mouse.click(...home);
  await page.waitForTimeout(1500);  // 페이드 0.4초 + 크로스페이드 0.3초 뒤
  r.menu_second = await level(1500);
  await page.screenshot({ path: `${out}/${name}_menu_second.png` });
  await page.mouse.click(...sound);
  await page.waitForTimeout(300);
  r.muted = await level(800);
  await page.screenshot({ path: `${out}/${name}_menu_muted.png` });
  await page.mouse.click(...sound);
  await page.waitForTimeout(300);
  r.unmuted = await level(800);
  report[name] = { errors, logs, levels: r, renderer: await page.evaluate(() => { const g = document.createElement('canvas').getContext('webgl2'); const e = g.getExtension('WEBGL_debug_renderer_info'); return g.getParameter(e ? e.UNMASKED_RENDERER_WEBGL : g.RENDERER); }) };
  await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
}
console.log(JSON.stringify(report, null, 1));
