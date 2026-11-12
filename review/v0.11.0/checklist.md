# v0.11.0 QUALITY_BAR 체크리스트 (이번에 확인한 것)
- [x] 주인공이 화면에서 가장 밝다: 8종 모두 테두리 빛 2.4 > 장애물 기호 1.98 (자동 테스트), NIGHT도 테두리·별로 몸이 읽힘 (`web/jelly_run_q0.png`)
- [x] 장애물·방울과 색 구분: 색상 30°/대비 1.5/파랑 예외 기준 자동 테스트, GRAPE·SODA·GOLD 조정 (`colors.md`, `web/color_compare*.png`)
- [x] 흑백에서도 젤리·무늬가 보임 (`web/jelly_run_q0_gray.png`)
- [x] 휴대폰 낮은 효과 단계에서도 무늬가 뭉개지지 않음 (`web/jelly_run_q4.png`)
- [x] 첫 화면에서 탭 한 번이면 시작 (TAP TO START, 뗄 때). 좌우 스와이프는 넘기기
- [x] 화면이 잘리지 않음·겹치지 않음: 휴대폰 390x844, PC 1280x720 (`web/menu_*.png`, 자동 테스트 4개 크기)
- [x] 브라우저 콘솔 오류 0 (check_web.json)
- [x] 맥 GPU 60fps 유지(8종, `perf_mac_gpu.json`). 아이폰 Safari 60fps는 미확인
- [ ] 휴대폰 실기기 손맛(넘기기·흔들림)·소리 켜짐 — 미확인, 사용자 확인
