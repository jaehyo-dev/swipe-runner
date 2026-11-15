// SWIPE PULSE 서비스 워커 (v0.12.0). tools/pwa_build.py가 __VERSION__·__FILES__를 채워 index.service.worker.js로 내보낸다.
// Godot가 만드는 서비스 워커 대신 쓰는 이유: 캐시 이름에 게임 버전, 나중에 받는 음악(music/)도 저장, versions/ 옛 버전은 건드리지 않기, 주소 /와 /index.html을 같은 페이지로.
// - 설치: 목록 전부를 새 캐시에 받는다. 이미 다른 버전이 있으면(업데이트) 브라우저 HTTP 캐시를 건너뛰어 옛 파일이 섞이지 않게
// - 새 버전은 기다린다(바로 바꾸지 않음). 메인 화면 UPDATE가 'skip'을 보내면 바뀌고, 페이지가 다시 불러온다 (web/shell.html)
// - 켜질 때 다른 버전 캐시를 지운다
const VERSION = '__VERSION__';
const CACHE = 'swipe-pulse-v' + VERSION;
const FILES = __FILES__;
const BASE = new URL('./', self.location).href;

self.addEventListener('install', (event) => {
	const mode = self.registration.active ? 'reload' : 'default';  // 첫 설치는 방금 받은 파일(HTTP 캐시)을 그대로 쓴다
	event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES.map((f) => new Request(f, { cache: mode })))));
});

self.addEventListener('activate', (event) => {
	event.waitUntil(caches.keys()
		.then((keys) => Promise.all(keys.filter((k) => k.startsWith('swipe-pulse-') && k !== CACHE).map((k) => caches.delete(k))))
		.then(() => self.clients.claim()));
});

self.addEventListener('message', (event) => {
	if (event.data === 'skip') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
	const req = event.request;
	if (req.method !== 'GET' || !req.url.startsWith(BASE) || req.url.startsWith(BASE + 'versions/')) return;
	const path = req.url.slice(BASE.length).split(/[?#]/)[0];
	const key = req.mode === 'navigate' && path === '' ? 'index.html' : path;
	if (!FILES.includes(key)) return;  // 목록 밖(licenses/ 등)은 네트워크 그대로
	event.respondWith(caches.open(CACHE).then((cache) => cache.match(key)).then((hit) => hit || fetch(req)));
});
