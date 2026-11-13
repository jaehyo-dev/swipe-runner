# 프로젝트 규칙

SWIPE PULSE(저장소 이름은 swipe-runner): Godot 4 (GDScript) 3D, 세로 화면 720x1280, 웹(HTML5) 배포 러너. 설계는 [GAME_SPEC.md](GAME_SPEC.md), 그림은 [ART_BIBLE.md](ART_BIBLE.md)를 따른다. 전역 규칙(~/.claude/CLAUDE.md)이 기본이고 아래가 더 구체적이면 아래를 따른다.
전역 규칙과 겹쳐 뺀 줄·지난 이야기·끝난 단계 표는 [docs/CLAUDE_REFERENCE.md](docs/CLAUDE_REFERENCE.md). 전역 파일을 못 읽는 클라우드 세션은 거기 "전역 규칙 사본"을 따른다.

- 코드 리뷰를 포함해 하위 에이전트·내장 리뷰 기능을 부를 때는 지시문에 "결과를 한국어로 보고해"를 꼭 넣는다. 그래도 영어로 나오면 사용자에게 보여 주기 전에 한국어로 옮겨서 보고한다.
- 기본 브랜치는 `main`.

## 정보
- 저장소: https://github.com/jaehyo-dev/swipe-runner
- 배포 주소: https://jaehyo-dev.github.io/swipe-runner/ (이전 버전: /versions/)
- 테스트: `godot --headless --path . --import` 후 `bash tests/run_tests.sh` (종료 코드 확인), 파일 하나만은 `TEST_FILE=test_orbs bash tests/run_tests.sh`, 도구 테스트 `python3 -m unittest discover -s tools -p "test_*.py"`, 난이도 표 `godot --headless --path . -s tools/difficulty_report.gd`, 오늘의 판 지문 `godot --headless --path . -s tools/daily_hash.gd`, 점수 분포 `godot --headless --path . -s tools/score_report.gd -- 곡선.csv`(그림 `python3 tools/plot_survival.py`)
- 웹 내보내기: `godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"` (Compatibility 렌더러, 스레드 없음) 뒤 `mkdir -p build/web/music && cp assets/audio/music/*.ogg build/web/music/` (첫 곡 뒤 음악은 .pck에 없음). 로딩 화면은 `web/shell.html`, 제목 글꼴 조각은 `tools/make_loading_font.py`(fonttools)
- 구조: 계산은 `scripts/logic/`(화면과 분리, 자동 테스트), 색 값은 `data/speed_palette.json`, 난이도 값은 `data/difficulty.json`, 화면은 `scripts/main.gd`·`runner.gd`·`art_meshes.gd`·`shaders/`, 소리는 오토로드 `scripts/audio_manager.gd`와 `scripts/web_music.gd`(효과음은 `tools/make_final_sounds.py`, 음악은 `tools/make_ladder_music.py`로 재현). 텍스처 그림은 쓰지 않는다.

## 에셋·기록
- 그림·효과·소리·음악·글꼴·셰이더·애드온·라이브러리는 만들기 전에 먼저 찾고, 어울리면 쓰고, 후보 2~4개를 게임 화면 안 시안으로 사용자에게 보여 준 뒤 확정한다. 이미 만든 것은 갈아엎지 않는다.
- 효과음·음악을 코드로 만드는 도구(`tools/make_final_sounds.py`·`tools/make_ladder_music.py`): 이미 만든 것은 유지, 새 소리·음악은 먼저 찾는다.
- 앞으로 review/에는 최종 비교 그림과 GIF만 커밋한다.
- 버전은 project.godot `config/version` 한 곳에 두고 CHANGELOG.md(한국어) 최신 버전과 일치(자동 테스트).

## 단계 표 (끝난 v0.1.0~v0.10.1은 참고 문서)
| 버전 | 내용 | 상태 |
|---|---|---|
| v0.11.0 | 젤리 스킨 8종 + 해금 미션, 메인 화면 넘기기·TAP TO START | 완료 |
| v0.11.1 | 점수 0.5배·기록 환산, 10000점 연출, 아이폰 끊김(배율 2.0·시계 보간·GC), 숨은 성능 표시, 설정 GRAPHICS | 완료 |
| v0.11.2 | 성능 표시를 설정 PERFORMANCE로, 오디오 줄·끊김 추정, 효과음 위치 워클릿 제거·휴대폰 출력 버퍼 20ms | 완료 |
| v0.11.3 | 일시정지 뒤 음악·효과음 밀림(AudioContext 재우지 않고 정확한 시각에 다시 예약, 3·2·1 오디오 시계), 휴대폰 디코딩 시점 | 완료 |
| 나중에 | 온라인 순위표, 곡 선택, 이어하기, (웹 정식 배포 때) 엔진 직접 빌드 | — |
