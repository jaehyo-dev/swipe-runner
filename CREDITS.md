# 크레딧

| 이름 | 버전 | 만든 사람 | 라이선스 | 출처 | 쓰는 곳 | 수정 |
|---|---|---|---|---|---|---|
| Godot Engine | 4.7.2 | Godot Engine contributors | MIT | https://godotengine.org | 게임 엔진 (배포 사이트 `licenses/godot.txt`에 전문) | 없음 |
| Poppins ExtraLight | google/fonts@7dc16b7 | The Poppins Project Authors (Indian Type Foundry) | SIL OFL 1.1 | https://github.com/google/fonts/tree/7dc16b7de42db624b902f2292b68ed9e489e5053/ofl/poppins | 거리 숫자·버전 글자 (`assets/fonts/`, 라이선스 전문 `assets/fonts/LICENSE-OFL.txt`) | 없음 |

그림 텍스처는 쓰지 않았다. 주인공·길·장애물은 기본 메시와 직접 쓴 셰이더(`shaders/`)로 만들었다 (직접 제작).
주인공 질감 시안 `assets/concept/jelly_options.svg`(v0.2.0·A·B·C 비교)는 이 프로젝트에서 직접 만든 SVG다 (직접 제작, 화면 확인 기준용, 게임에는 들어가지 않음).
길 시안 `assets/concept/road_options.svg`(A·B·C와 장애물 3종)도 직접 만든 SVG다 (직접 제작, 수정 없음, 화면 확인 기준용, 게임에는 들어가지 않음).

네온 무대 시안 `assets/concept/neon_stage.svg`(무대 한 장면과 장애물 세 종류)도 직접 만든 SVG다 (직접 제작, 수정 없음, 화면 확인 기준용, 게임에는 들어가지 않음).
소리 후보 2차 `review/v0.2.8/sounds_v2/`의 C 후보 4개는 아래 Kenney CC0 소리를 가공했고(원본 파일별 표·라이선스 전문은 같은 폴더 LICENSES.md와 sources/), A·B 후보 8개는 `make_sounds_v2.py`로 직접 합성했다 (화면 확인 기록이라 게임에는 들어가지 않음).

| 이름 | 버전 | 만든 사람 | 라이선스 | 출처 | 쓰는 곳 | 수정 |
|---|---|---|---|---|---|---|
| Interface Sounds (drop_001, drop_004, pluck_002, scratch_001, glass_004) | 1.0 | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds | 소리 후보 2차 C (게임 미적용) | 있음 (음 높이·필터·감쇠) |
| Impact Sounds (footstep_snow_000, impactGeneric_light_000, impactGlass_light_000) | 1.0 | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds | 소리 후보 2차 C (게임 미적용) | 있음 (필터·알갱이·감쇠) |
| 40 CC0 water / splash / slime SFX (slime_13, splash_02, splash_10) | 받은 날 2026-11-08 (zip SHA-256은 LICENSES.md) | rubberduck | CC0 1.0 | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | 소리 후보 3차 `review/v0.2.8/sounds_v3/` slide_c, crash_c, land_a·b·c (게임 미적용) | 있음 (재생 속도·필터·감쇠) |

소리 후보 `review/v0.2.8/sounds/`(효과음 15개, 배경 음악 3개)는 이 프로젝트에서 `make_sounds.py`로 직접 합성했다 (직접 제작, 외부 음원 없음, 화면 확인 기록이라 게임에는 들어가지 않음. 파일별 표는 같은 폴더 README.md).

## 게임 소리 (v0.3.0~, 파일별 표와 라이선스 전문은 `assets/audio/LICENSES.md`, `assets/audio/licenses/`)

| 이름 | 버전 | 만든 사람 | 라이선스 | 출처 | 쓰는 곳 | 수정 |
|---|---|---|---|---|---|---|
| Impact Sounds (impactGeneric_light_000) | 1.0 | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds | `sfx/land.wav` | 있음 |
| Interface Sounds (scratch_001, drop_001) | 1.0 | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds | `sfx/land.wav` | 있음 |
| 40 CC0 water / splash / slime SFX (splash_02) | 받은 날 2026-11-08 | rubberduck | CC0 1.0 (페이지 표시가 근거) | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | `sfx/crash.wav` | 있음 |
| 레인 이동·점프·슬라이드 효과음 | - | 이 프로젝트 (직접 합성) | 프로젝트 소유 | `review/v0.2.8/` | `sfx/lane.wav`, `jump.wav`, `slide.wav` | - |
| 방울 "톡"·콤보 끊김 "툭"·아슬아슬 "슉" 효과음 | v0.8.0 | 이 프로젝트 (직접 합성, lane_c 재료) | 프로젝트 소유 | `review/v0.8.0/sounds/make_reward_sounds.py` | `sfx/orb.wav`, `combo_break.wav`, `close.wav` | - |
| 부서짐 효과음 (후보 A·B·C) | - | 이 프로젝트 (직접 합성, 외부 음원 없음) | 프로젝트 소유 | `review/v0.6.0/shatter_sounds/make_shatter_sounds.py` | 게임에 쓰지 않음 (v0.6.1에서 삭제). 듣기 페이지만 기록으로 남김 | - |
| 배경 음악 Jelly Pulse (원본·A Drive·B Drive+ 13곡) | - | 이 프로젝트 (직접 합성) | 프로젝트 소유 | `tools/make_ladder_music.py` | `music/bgm_*.ogg` | - |

## 배경 음악 후보 (v0.3.1, 화면 확인 기록)

`review/v0.3.1/music/`의 후보(원본·A·B × 100/115/130BPM)는 `make_music.py`로 직접 합성했다 (이 프로젝트 소유, 외부 음원 없음, 수정 없음, 게임에는 들어가지 않음). 같이 듣기에 쓰는 효과음은 위 게임 소리와 같은 파일이다.
