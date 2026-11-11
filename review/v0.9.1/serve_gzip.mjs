// GitHub Pages처럼 gzip으로 보내는 정적 서버 (로딩 시간 측정용). 사용: node serve_gzip.mjs <폴더> <포트>
import http from 'http'; import fs from 'fs'; import path from 'path'; import zlib from 'zlib';
const [rootArg, port] = process.argv.slice(2), root = path.resolve(rootArg);
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.woff2': 'font/woff2', '.ogg': 'audio/ogg', '.json': 'application/json' };
const cache = {};  // 파일별 gzip 결과 (한 번만 압축). 캐시 머리글은 GitHub Pages처럼 10분
http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/\/$/, '/index.html'));
  if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  const st = fs.statSync(p), etag = `"${st.size}-${Math.floor(st.mtimeMs)}"`;  // GitHub Pages처럼 ETag: 다시 확인하면 304
  const ext = path.extname(p), headers = { 'Content-Type': types[ext] || 'application/octet-stream', 'Cache-Control': 'max-age=600', ETag: etag };
  if (req.headers['if-none-match'] === etag) { res.writeHead(304, headers); return res.end(); }
  // Pages는 woff2·png·ogg 같은 이미 압축된 파일은 gzip하지 않는다
  if (['.woff2', '.png', '.ogg'].includes(ext)) { res.writeHead(200, headers); return res.end(fs.readFileSync(p)); }
  const key = p + fs.statSync(p).mtimeMs;
  cache[key] ??= zlib.gzipSync(fs.readFileSync(p), { level: 6 });
  res.writeHead(200, { ...headers, 'Content-Encoding': 'gzip' }); res.end(cache[key]);
}).listen(+port, () => console.log('serving', root, port));
