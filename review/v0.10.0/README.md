# v0.10.0 확인 기록 — 오늘의 판 (DAILY)

맥(Apple Silicon)에서 창 없이 확인. 화면은 헤드리스 크롬(소프트웨어 렌더링, 약 12fps), 서버는 `review/v0.9.1/serve_gzip.mjs`.

## 같은 날 같은 배치 (지문 비교)
`DailyRecord.layout_hash`: 앞 150마디의 장애물(박·레인·종류·줄)과 계획된 방울 줄(박·레인·x·y, x·y는 1e-4 반올림)의 sha256 앞 16자리. 출시일(#1)부터 날짜 30개.

| 환경 | 명령 | 결과 |
|---|---|---|
| 맥 네이티브 (Godot 4.7.2) | `godot --headless --path . -s tools/daily_hash.gd` | `hash_mac.txt`, ALL `0d9a4121563f7b20` |
| 웹 wasm (헤드리스 크롬) | `?dailyhash=1` 콘솔 (`check_web.mjs`) | `hash_web.txt`, ALL `0d9a4121563f7b20` — 30개 모두 같음 |
| 윈도우 WSL | 같은 명령 | **미확인**: 주말에 데스크탑에서 돌려 `hash_wsl.txt`로 비교할 것 (`diff review/v0.10.0/hash_mac.txt hash_wsl.txt`) |

- 프레임 간격과 무관: 자동 테스트가 같은 날짜를 60Hz·144Hz·24Hz 간격으로 계산해 같은 지문인지, 전역 난수(seed/randi)를 바꿔도 같은지 확인 (`tests/test_daily.gd`)
- 고정 지문 테스트: #1의 지문 `99e7039b5e52de92`. 패턴·방울 규칙이나 data 값을 바꾸면 깨진다 → 의도한 변경이면 값을 고치고 CHANGELOG에 "오늘의 판 배치 바뀜"
- 같은 #1 판을 휴대폰·PC 두 브라우저에서 따로 달린 화면(`web/daily_copied_*.png`)도 장애물·방울 줄이 같다

## 날짜 바꾸기 자동 테스트 (테스트용 시간 덮어쓰기 `clock_override`)
`tests/test_daily.gd`(12개), `tests/test_main_scene.gd`의 오늘의 판 5개: UTC 자정(한국 9시) 경계, 번호 #1·#12, 씨앗 1년 겹침 없음, 남은 시간, 하루 여러 판 = STREAK +1, 이어짐·하루 빠짐 → 0 → 1, 날짜별 최고 점수, 자정을 넘긴 판은 시작한 날 기록 + 다시 시작부터 새 날·새 씨앗, 30일 지난 기록 정리, 깨진 파일, 일반 최고 점수와 섞이지 않음(양쪽 파일 확인), SHARE 글, 일반 모드엔 SHARE 없음

## 화면 (`check_web.mjs`, 콘솔 오류 0)
- 메인: `web/menu_phone.png`, `web/menu_pc.png` — SWIPE TO START 아래 DAILY #1 버튼, 오늘 안 했으면 연보라 점
- 오늘의 판 시작 화면: `web/daily_start_phone.png`, `web/daily_start_pc.png`
- 플레이 중 DAILY BEST 자리: `web/daily_play_*.png` (첫 판이라 숨김)
- 게임 오버 + SHARE → COPIED: `web/daily_over_*.png`, `web/daily_copied_*.png`. 클립보드 글 `SWIPE PULSE Daily #1 — 174 https://jaehyo-dev.github.io/swipe-runner/` (`check_web.json`)
- 집 → 메인, 점 사라짐: `web/menu_after_*.png`
- PC 가로 화면에서는 SHARE가 다시 시작 안내 아래 젤리와 겹쳐 TRIES 줄 아래로 옮겼다
- 관찰: 첫 실행에서 같은 판인데 점수가 174/109로 달랐다(방울 하나 65점). 소프트웨어 렌더링 12fps라 가만히 있는 젤리가 방울을 먹은 프레임이 갈린 것으로, 배치 차이는 아니다(두 번째 실행은 둘 다 174). 실제 GPU 60fps에서는 영향 없음
- 휴대폰 공유 창(Web Share)은 헤드리스에서 열 수 없어 미확인 (누르는 화면 + navigator.share가 있을 때만 씀)
