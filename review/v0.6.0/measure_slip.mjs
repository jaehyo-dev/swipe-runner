// 경계가 4마디 미뤄질 때 음악이 끊기지 않는지 잰다: 150BPM에서 ?off=slip으로 예약을 잠깐 막아 다음 경계를 미룬다 (곡 준비가 늦거나 탭을 전환한 상황과 같다).
// 출력 음량을 0.1초마다 재서 0.2초 넘게 무음인 구간을 찾는다. 사용: PW=.. CHROME=.. node measure_slip.mjs <측정 빌드 주소>
import { createRequire } from 'module'; import fs from 'fs'; import os from 'os'; import path from 'path';
const { chromium } = createRequire(import.meta.url)(process.env.PW || 'playwright');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'slip-'));
const ctx = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME, headless: true, viewport: { width: 390, height: 844 }, args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--disable-audio-output'] });
const page = ctx.pages()[0] || await ctx.newPage();
await page.addInitScript(() => {
  const r = window.__s = { levels: [], schedules: [] }, connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (d, ...a) {
    if (d instanceof AudioDestinationNode) {  // 효과음 경로와 음악 경로가 따로 나간다: 전부 재는 곳에 잇는다
      if (!r.an) {
        r.an = d.context.createAnalyser(); r.an.fftSize = 2048;
        const buf = new Float32Array(2048);
        setInterval(() => { r.an.getFloatTimeDomainData(buf); r.levels.push([d.context.currentTime, Math.sqrt(buf.reduce((x, v) => x + v * v, 0) / 2048)]); }, 100);
      }
      connect.call(this, r.an);
    }
    return connect.call(this, d, ...a);
  };
  let v; Object.defineProperty(window, 'gameMusic', { configurable: true, get: () => v, set: g => { const s = g.schedule; g.schedule = (i, at, b, o) => { r.schedules.push({ step: i, at: +at.toFixed(3), pos: +g.position().toFixed(3) }); return s(i, at, b, o); }; v = g; } });
});
await page.goto(process.argv[2] + '?mode=accuracy&secs=32&bpm=150&off=slip');
await page.waitForFunction(() => window.gameMusic && window.musicStart > 0, null, { timeout: 120000, polling: 50 });
await page.waitForTimeout(30000);
const r = await page.evaluate(() => ({ levels: window.__s.levels, schedules: window.__s.schedules, start: window.gameAudioCtx ? window.gameAudioCtx.currentTime : 0 }));
let run = 0, longest = 0, where = 0; const t0 = r.levels.findIndex(l => l[1] > 1e-4);
for (const [t, v] of r.levels.slice(t0, -5)) { run = v < 1e-4 ? run + 1 : 0; if (run > longest) { longest = run; where = t; } }
const spans = r.schedules.map((s, i) => i ? +(s.at - r.schedules[i - 1].at).toFixed(2) : +s.at.toFixed(2));
console.log(JSON.stringify({ schedules: r.schedules, gaps_between_edges_s: spans, samples: r.levels.length, longest_silence_s: +(longest * 0.1).toFixed(1), silence_end_ctx: where, first_sound_ctx: r.levels[t0][0] }));
await ctx.close(); fs.rmSync(profile, { recursive: true, force: true });
process.exitCode = longest * 0.1 > 0.2 ? 1 : 0;
