# 소리 후보 2차 출처와 라이선스

## 후보별 출처

| 후보 | 출처 | 라이선스 |
|---|---|---|
| jump_a, jump_b, slide_a, slide_b, land_a, land_b, crash_a, crash_b | `make_sounds_v2.py`로 직접 합성 (사인파 + 걸러낸 노이즈) | 프로젝트 소유 |
| jump_c, slide_c, land_c, crash_c | 아래 CC0 원본을 가공 (일부에 합성음을 얇게 더함) | CC0 원본 + 프로젝트 가공 |

비교용 1차 소리, bgm_3, lane_c는 `../sounds/`의 직접 합성 소리다.

## CC0 원본 파일

전부 Kenney의 공식 배포처(kenney.nl)에서 받았고, 페이지의 라이선스 표기와 zip 안의 `License.txt`에서 CC0을 직접 확인했다 (2026-11-08). 원본 파일은 `sources/`, 라이선스 전문은 `sources/License_*.txt`에 있다.

| 원본 파일 | 팩 | 주소 | 라이선스 | 쓰는 곳 | 가공 |
|---|---|---|---|---|---|
| `drop_004.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | jump_c | 재생 속도로 E5까지 끌어올림 |
| `pluck_002.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | jump_c | 재생 속도로 B5→E6 |
| `footstep_snow_000.ogg` | Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | CC0 1.0 | slide_c, crash_c | 하이패스. slide_c는 40ms 알갱이로 잘라 흩뿌리고 공명 필터로 끌어내림 |
| `impactGeneric_light_000.ogg` | Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | CC0 1.0 | land_c | 하이패스, 앞 60ms만 |
| `scratch_001.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | land_c | 하이패스, 앞 100ms에 빠른 감쇠 |
| `drop_001.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | land_c | 재생 속도로 E7 |
| `impactGlass_light_000.ogg` | Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | CC0 1.0 | crash_c | 하이패스 |
| `glass_004.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | crash_c | 재생 속도로 E8·B7, 겹치고 감쇠 |

받은 zip의 SHA-256:

- `kenney_interface-sounds.zip`: `f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`
- `kenney_impact-sounds.zip`: `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8`

Digital Audio 팩은 레이저·8비트 계열이라 쓰지 않았다 (기준 7).
