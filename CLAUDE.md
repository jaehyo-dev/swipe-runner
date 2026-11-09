# 프로젝트 규칙

스와이프 러너(가칭): Godot 4 (GDScript) 3D, 세로 화면 720x1280, 웹(HTML5) 배포 러너. 설계는 [GAME_SPEC.md](GAME_SPEC.md)를 따른다. 전역 규칙(~/.claude/CLAUDE.md)이 기본이고 아래가 더 구체적이면 아래를 따른다.

- 나는 웹 개발을 공부하는 학생이야. 한국어로 대화하고 코드에는 한국어 주석을 달아.
- 너는 리더야. 계획을 세우고 작업을 나누고 최종 판단을 해. 기본 브랜치는 `main`.

## 정보
- 저장소: https://github.com/jaehyo-dev/swipe-runner
- 배포 주소: https://jaehyo-dev.github.io/swipe-runner/ (이전 버전: /versions/)
- 테스트: `godot --headless --path . --import` 후 `bash tests/run_tests.sh` (종료 코드 확인), 도구 테스트 `python3 -m unittest discover -s tools -p "test_*.py"`, 난이도 표 `godot --headless --path . -s tools/difficulty_report.gd`
- 웹 내보내기: `godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"` (Compatibility 렌더러, 스레드 없음)
- 구조: 계산은 `scripts/logic/`(화면과 분리, 자동 테스트), 색 값은 `data/speed_palette.json`, 화면은 `scripts/main.gd`·`runner.gd`·`art_meshes.gd`·`shaders/`, 소리는 오토로드 `scripts/audio_manager.gd`와 `scripts/web_music.gd`(효과음은 `tools/make_final_sounds.py`, 음악은 `tools/make_ladder_music.py`로 재현). 텍스처 그림은 쓰지 않는다.

## 진행 방식
- 큰 작업은 단계로 나누고 한 번에 한 단계만 만들어. 끝나면 멈추고 보고해. 다음 단계 기능을 미리 만들지 마.
- 단계마다: 테스트 → 내 코드 리뷰 → final-reviewer 최종 검토 → 통과하면 main에 푸시. 불통과·테스트 실패는 푸시 금지. 재검토는 최대 2번.
- 테스트는 출력과 종료 코드를 확인. 무작위 값은 시드를 받게 해서 고정.
- 화면은 로컬 서버로 열어 PC(1280x720)와 휴대폰(390x844)에서 확인, 콘솔 오류 없어야 함.
- 리뷰 지적은 하나씩 "수용 / 거절 + 이유"로 정리. final-reviewer에게는 이번 단계 요구사항만 전달하고, 검토 뒤 git status로 파일이 안 바뀌었는지 확인.
- 되돌릴 수 있는 결정은 묻지 말고 정해서 진행하고 보고에 적어. 되돌리기 어려운 일, 비용·계정·보안, 요청 충돌만 물어.
- 단계가 끝나면 PROGRESS.md에 10줄 이내로 기록하고, 보고 후 /clear를 안내해.

## Git·버전
- main에는 final-reviewer 통과분만 푸시. 커밋 이메일은 GitHub noreply만. 비밀 정보 커밋 금지.
- Semantic Versioning. 버전은 project.godot `config/version` 한 곳에 두고 CHANGELOG.md(한국어) 최신 버전과 일치(자동 테스트). 태그·릴리스는 Actions가 만들고 직접 만들지 마. 버전 태그는 지우거나 옮기지 마.
- 라이선스: MIT·Apache·BSD·zlib·CC0 자유, CC-BY·OFL은 출처 표기, GPL·CC-BY-SA 등은 먼저 질문. 쓴 외부 에셋은 모두 CREDITS.md에 기록.

## 단계 표
| 버전 | 내용 | 상태 |
|---|---|---|
| v0.1.0 | 세팅 + 3레인 스와이프 이동 + 유리 장애물 1종 | 완료 (v0.1.6까지 다듬음) |
| v0.2.0 | 점프·슬라이드 장애물, 충돌·재시작 | 완료 |
| v0.2.1 | 주인공 질감 "빛나는 푸딩 슬라임" + 레인 이동 출렁임 | 완료 |
| v0.2.2 | 주인공 질감 다듬기(맑게·MSAA) + 바닥에 붙은 느낌 | 완료 |
| v0.2.3 | 아쿠아 민트 색, 찹쌀떡 크기, 점프·슬라이드 액체 모션 | 완료 |
| v0.2.4 | 공중 둥근 물방울, 점프 그림자, 스와이프 한 번 = 한 동작 | 완료 |
| v0.2.5 | 공중 비율(키/폭 1.0 이상) 바로잡기, 굴절 선 색 | 완료 |
| v0.2.6 | 액체 모션: 속도 비례 점프, 단계적 착지 팬케이크 + 물방울, 녹아 흐르는 슬라이드, 위아래 시차 | 완료 |
| v0.2.7 | 공중 계란형(가장 넓은 높이 49%, 아래 깊이/위 돔 0.9 이상) | 완료 |
| v0.2.8 | 충돌 모션, 공중 아래 스와이프, 입력 저장, 그 자리 재시작, 소리 후보 | 완료 |
| v0.3.0 | 소리 확정·적용, 장애물을 박자에 맞추기 | 완료 |
| v0.3.1 | 빈 시간 없애기, 소리 균형, 첫 시작 렉, 배경 음악 후보 | 완료 |
| v0.4.0 | 속도와 템포가 같이 오르기(원본 → A → B), 최고 거리 기록 | 완료 |
| v0.4.1 | 길과 장애물 아트: 유리 바닥·반사·난간·박자 물방울, 모양으로 읽히는 장애물 | 완료 |
| v0.5.0 | 난이도(속도표, 8마디 템포, 단계별 패턴), 속도에 따라 진해지는 색, 장애물 반투명·막대 기둥 제거, 사람 모델 | 완료 |
| v0.5.1 | 난이도 크게(160BPM·속도 24, 4마디), 색 진하기 폭, 장애물 70%·앞면만·접지 그림자·빛 웅덩이, 맥북 렉(해상도 상한, MultiMesh, 자동 낮춤) | 완료 |
