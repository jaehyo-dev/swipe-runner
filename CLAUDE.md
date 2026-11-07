# 프로젝트 규칙

스와이프 러너(가칭): Godot 4 (GDScript) 3D, 세로 화면 720x1280, 웹(HTML5) 배포 러너. 설계는 [GAME_SPEC.md](GAME_SPEC.md)를 따른다. 전역 규칙(~/.claude/CLAUDE.md)이 기본이고 아래가 더 구체적이면 아래를 따른다.

- 나는 웹 개발을 공부하는 학생이야. 한국어로 대화하고 코드에는 한국어 주석을 달아.
- 너는 리더야. 계획을 세우고 작업을 나누고 최종 판단을 해. 기본 브랜치는 `main`.

## 정보
- 저장소: https://github.com/jaehyo-dev/swipe-runner
- 배포 주소: https://jaehyo-dev.github.io/swipe-runner/ (이전 버전: /versions/)
- 테스트: `godot --headless --path . --import` 후 `bash tests/run_tests.sh` (종료 코드 확인), 도구 테스트 `python3 -m unittest discover -s tools -p "test_*.py"`
- 웹 내보내기: `godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"` (Compatibility 렌더러, 스레드 없음)
- 구조: 계산은 `scripts/logic/`(화면과 분리, 자동 테스트), 화면은 `scripts/main.gd`·`runner.gd`·`shaders/`. 텍스처 그림은 쓰지 않는다.

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
| v0.2.0 | 점프·슬라이드 장애물, 충돌·재시작 | 진행 |
