// 윈도우 데스크탑(WSL)용 프레임 측정: 윈도우 크롬을 헤드리스(창 없음) + D3D11로 띄워 RTX 4060으로 그린다.
// 윈도우의 node.exe로 실행한다 (Playwright 없이 크롬 원격 디버깅(CDP)을 내장 WebSocket으로 직접 다룬다). measure_frames.mjs가 WSL에서 이 파일을 부른다.
// 재는 것은 measure_frames.mjs와 같다: 측정 빌드 자동 플레이 1판 동안 requestAnimationFrame 간격, 자동 낮춤(QUALITY 줄), 오류.
// 사용: node.exe measure_frames_win.mjs <주소> <결과.json(윈도우 경로)> <가로x세로>
import { spawn } from 'child_process'; import fs from 'fs'; import os from 'os'; import path from 'path';
const [url, out, size] = process.argv.slice(2);
const [w, h] = size.split('x').map(Number);
const chrome = process.env.CHROME_WIN || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const port = 9300 + Math.floor(Math.random() * 600);
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'swipe-measure-'));
const proc = spawn(chrome, ['--headless=new', `--remote-debugging-port=${port}`, '--remote-debugging-address=127.0.0.1', `--user-data-dir=${profile}`,
  '--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--no-first-run', '--autoplay-policy=no-user-gesture-required', '--disable-audio-output', `--window-size=${w},${h}`, 'about:blank'], { stdio: 'ignore' });
let target;
for (let i = 0; i < 50 && !target; i++) {
  await new Promise(r => setTimeout(r, 200));
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch { }
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0; const wait = {}, errors = [], levels = []; let result = null;
const send = (method, params = {}) => new Promise(r => { const i = ++id; wait[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
const t0 = Date.now();
ws.onmessage = e => {
  const m = JSON.parse(e.data);
  if (m.id && wait[m.id]) return wait[m.id](m.result ?? m.error);
  if (m.method === 'Runtime.consoleAPICalled') {
    const t = m.params.args.map(a => a.value ?? a.description ?? '').join(' ');
    if (m.params.type === 'error') errors.push(t);
    if (t.startsWith('RESULT ')) { errors.push('RESULT at ' + ((Date.now() - t0) / 1000).toFixed(1)); try { result = JSON.parse(t.slice(7)); } catch { errors.push('RESULT 해석 실패'); } }
    if (t.startsWith('QUALITY ')) levels.push(t.slice(8));
  }
  if (m.method === 'Runtime.exceptionThrown') errors.push(((Date.now() - t0) / 1000).toFixed(1) + 's ' + (m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text).slice(0, 900));
};
await new Promise(r => ws.onopen = r);
const evaluate = async expression => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.value;
await send('Runtime.enable');
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 2, mobile: false });  // 맥북 전체 화면과 같은 캔버스 (measure_frames.mjs와 같다)
await send('Page.addScriptToEvaluateOnNewDocument', { source: 'const r = window.__rec = []; let last = 0; const tick = now => { if (last) r.push(+(now - last).toFixed(2)); last = now; requestAnimationFrame(tick); }; requestAnimationFrame(tick);' });
await send('Page.navigate', { url: url + (url.includes('?') ? '&' : '?') + 'quiet=1' });
for (let i = 0; i < 1200 && !(await evaluate('window.gameReady > 0')); i++) await new Promise(r => setTimeout(r, 100));
await evaluate('window.__rec.length = 0');
const env = await evaluate(`(() => { const c = document.querySelector('canvas'), g = document.createElement('canvas').getContext('webgl2'), e = g.getExtension('WEBGL_debug_renderer_info');
  return { inner: [innerWidth, innerHeight], dpr: devicePixelRatio, canvas: [c.width, c.height], ua: navigator.userAgent.match(/Chrome\\/[\\d.]+/)?.[0], gpu: g.getParameter(e ? e.UNMASKED_RENDERER_WEBGL : g.RENDERER), hidden: document.hidden }; })()`);
for (let i = 0; i < 400 && !result && errors.length < 20; i++) await new Promise(r => setTimeout(r, 1000));
const ms = await evaluate('window.__rec');
let at = 0; const slow = []; for (const x of ms) { at += x; if (x > 20) slow.push([+(at / 1000).toFixed(2), x]); }
const sorted = [...ms].sort((a, b) => a - b), q = p => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
const res = { url, method: '윈도우 크롬 헤드리스 + D3D11 (CDP)', slow_frames: slow.slice(0, 60), size, env, frames: ms.length, fps: +(1000 * ms.length / ms.reduce((a, b) => a + b, 0)).toFixed(1), p50: q(0.5), p90: q(0.9), p99: q(0.99), max: sorted[sorted.length - 1],
  over33: ms.filter(x => x > 33).length, over20: ms.filter(x => x > 20).length, draw: result?.draw_calls, music: result?.music_time, crashes: result?.crashes, levels, render: result?.render_size, jitter: result?.clock_jitter, errors };
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(JSON.stringify({ size, gpu: env.gpu, hidden: env.hidden, canvas: env.canvas, frames: res.frames, fps: res.fps, p50: res.p50, p99: res.p99, max: res.max, over33: res.over33, over20: res.over20, draw: res.draw?.mean, crashes: res.crashes, levels, errors: errors.length }));
await send('Browser.close').catch(() => { });
ws.close();
setTimeout(() => { try { proc.kill(); } catch { } try { fs.rmSync(profile, { recursive: true, force: true }); } catch { } process.exit(0); }, 1000);
