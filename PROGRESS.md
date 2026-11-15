# 진행 기록

지난 기록(v0.1.0 ~ v0.11.2)은 [docs/PROGRESS_ARCHIVE.md](docs/PROGRESS_ARCHIVE.md).

## v0.11.3 일시정지 뒤 음악·효과음 밀림, 휴대폰 디코딩 시점
- 웹 일시정지는 AudioContext를 재우지 않고 곡 노드만 세운 뒤, 화면이 멈춘 음악 시간 자리부터 정확한 시각에 다시 예약(기준점·경계 함께 이동). 3·2·1은 오디오 시계
- 일시정지 때 효과음 재생기는 끈다(옛: 멈춤 → 재개 때 꼬리가 늦게 남). 효과음은 원래 지금 바로 재생(예약 0ms)
- 흉내 측정: 옛 크롬은 이어 한 직후 −85~−110ms, 새는 기준값과 평균 6ms 안·누적 없음. 맥 WebKit은 아이폰 증상 재현 안 됨 → 실기기 확인 남음
- 휴대폰 디코딩: 메인·일시정지·숫자·숨 고르기 마디 8ms, 보통 마디는 예약 4초 전부터만. 메인·게임 오버에서 첫 경계 곡 미리. 기록 review/v0.11.3/

## v0.12.0 홈 화면 앱(PWA)
- manifest(아이콘 192·512·maskable, 세로·standalone), 아이폰 아이콘 180·시작 화면 11장(tools/make_pwa_images.mjs, 엔진 렌더링), viewport-fit=cover·안전 영역
- 서비스 워커(web/pwa/sw.js → tools/pwa_build.py가 index.service.worker.js로): 캐시 이름에 버전, 음악 포함, versions/는 건드리지 않음
- 메인 화면 UPDATE(새 버전), INSTALL(안드로이드), ADD TO HOME SCREEN 안내(아이폰 브라우저, × 저장)
- 리뷰 반영: pwa_hit 한 번만, STARTUP export 제거. 전체 테스트 383 통과. 확인 스크립트 review/v0.12.0/check_pwa.mjs
- 주의: test_main_scene 실제 시간 타이머 → 맥이 잠들면 전체 테스트가 멈춘 듯 보임. caffeinate -i로 돌린다

## 나중에(앱 출시 때)
- 휴대폰 음악 지지직: 앱(네이티브 오디오)에서 다시 확인. 48kHz 변환·출력 버퍼 조정은 그때

## 이어서 할 일
- 맥에서 v0.12.0까지 (작업 브랜치 wip/v0.12.0, main에 올림·배포 확인)
- 아이폰·안드로이드에서 직접: 홈 화면 추가 → 아이콘·시작 화면·노치 안전 영역, 비행기 모드 실행, 다음 배포 때 UPDATE 흐름
- 아이폰에서 직접(v0.11.3부터 남음): 일시정지 뒤 소리 밀림, PERFORMANCE GAP 숫자. 다음 단계는 사용자와 정함
