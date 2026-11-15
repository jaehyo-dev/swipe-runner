# 진행 기록

지난 기록(v0.1.0 ~ v0.11.3)은 [docs/PROGRESS_ARCHIVE.md](docs/PROGRESS_ARCHIVE.md).

## v0.12.0 홈 화면 앱(PWA)
- manifest(아이콘 192·512·maskable, 세로·standalone), 아이폰 아이콘 180·시작 화면 11장(tools/make_pwa_images.mjs, 엔진 렌더링), viewport-fit=cover·안전 영역
- 서비스 워커(web/pwa/sw.js → tools/pwa_build.py가 index.service.worker.js로): 캐시 이름에 버전, 음악 포함, versions/는 건드리지 않음
- 메인 화면 UPDATE(새 버전), INSTALL(안드로이드), ADD TO HOME SCREEN 안내(아이폰 브라우저, × 저장)
- 리뷰 반영: pwa_hit 한 번만, STARTUP export 제거. 전체 테스트 383 통과. 확인 스크립트 review/v0.12.0/check_pwa.mjs
- 주의: test_main_scene 실제 시간 타이머 → 맥이 잠들면 전체 테스트가 멈춘 듯 보임. caffeinate -i로 돌린다

## v0.12.1 휴대폰 화질, 저전력 모드 30fps, PWA 범위
- AUTO 3D 배율 2.0 → 2.5 → 3.0: 3초 동안 99% 일하는 시간(rAF 시작 ~ 그리기 뒤 메시지) ≤ 갱신 간격 70%면 올림. 밀리면 배율부터 내리고 그 배율은 다시 안 올림. HIGH = 3.0 + MSAA 4x
- 가는 선: 난간·테두리·기호는 fwidth로 가장자리 녹이기, 대시·방울 이음선은 1.5픽셀 최소 폭 + 옅게. 엔진(Compatibility)은 alpha-to-coverage가 없어 알파 대신 색 섞기
- 30Hz: 예전 판단기가 33ms를 모두 느림으로 봐 끝까지(4단계) 낮췄음 → 갱신 간격 기준 판단 + 30Hz면 한 단계만. 엔진이 이미 프레임 시간을 33.33ms로 고르게 줘서 보간 코드는 안 넣음
- 휴대폰 ?bpm 로딩 멈춤 버그 수정. 측정 도구 tools/web_probe.mjs(?probe=1), 기록 review/v0.12.1/
- versions/ 서비스 워커 제외는 이미 됨 → 자동 테스트로 고정

## 나중에(앱 출시 때)
- 휴대폰 음악 지지직: 앱(네이티브 오디오)에서 다시 확인. 48kHz 변환·출력 버퍼 조정은 그때

## 이어서 할 일
- 맥에서 v0.12.1까지 (작업 브랜치 wip/v0.12.1, main에 올림·배포 확인)
- 아이폰에서 직접: 화질(난간·블록 테두리), 저전력 모드 끊김, 성능 표시로 AUTO 배율이 3.0까지 오르는지·내려오는지, 홈 화면 앱 UPDATE로 v0.12.1 받기
- v0.11.3부터 남은 실기기 확인(일시정지 뒤 소리 밀림). 다음 단계는 사용자와 정함
