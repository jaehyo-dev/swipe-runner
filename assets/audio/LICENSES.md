# 게임 소리 출처와 라이선스

`tools/make_final_sounds.py`가 `review/v0.2.8/`의 후보에서 만든다. 공통 가공: 재생 속도 변경(높이와 길이가 같이 바뀌는 직선 보간 리샘플), 로우패스(Q 0.5), 끝 30ms 페이드 아웃.

| 파일 | 원본 | 가공 | 라이선스 |
|---|---|---|---|
| `sfx/lane.wav` | `sounds/sfx/lane_c.wav` | 높이 0, 필터 없음, 끝 페이드 | 직접 합성, 프로젝트 소유 |
| `sfx/jump.wav` | `sounds_v3/jump_b.wav` | +5반음, 12kHz, 끝 페이드 | 직접 합성, 프로젝트 소유 |
| `sfx/slide.wav` | `sounds_v3/slide_a.wav` | +7반음, 12kHz, 끝 페이드 | 직접 합성, 프로젝트 소유 |
| `sfx/land.wav` | `sounds_v2/land_c.wav` | -10반음, 12kHz, 끝 페이드 | Kenney CC0 소리 가공 + 프로젝트 가공 (아래) |
| `sfx/crash.wav` | `sounds_v3/crash_c.wav` | +9반음, 9.5kHz, 끝 페이드 | rubberduck CC0 소리 가공 + 직접 합성 몸통 (아래) |
| `sfx/orb.wav`, `sfx/combo_break.wav`, `sfx/close.wav` | `../v0.8.0/sounds/orb_a·break_a·close_a.wav` (`make_reward_sounds.py`) | 높이 0, 필터 없음, 끝 페이드 | 직접 합성, 프로젝트 소유 |
| `music/bgm_<BPM>_<편곡>.ogg` 7개 | `tools/make_ladder_music.py` (`review/v0.3.1/music/make_music.py`의 합성) | 템포별로 다시 합성, Vorbis q5 | 직접 합성, 프로젝트 소유 |

## 착지: Kenney CC0

| 원본 파일 | 팩 | 주소 | 라이선스 | 후보 단계 가공 |
|---|---|---|---|---|
| `impactGeneric_light_000.ogg` | Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | CC0 1.0 | 하이패스, 앞 60ms만 |
| `scratch_001.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | 하이패스, 앞 100ms에 빠른 감쇠 |
| `drop_001.ogg` | Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | CC0 1.0 | 재생 속도로 E7 |

공식 배포처 페이지와 zip 안의 `License.txt`에서 CC0을 확인했다 (2026-11-08). 전문: `licenses/License_impact-sounds.txt`, `licenses/License_interface-sounds.txt`.

## 충돌: OpenGameArt rubberduck CC0

| 원본 파일 | 팩 | 주소 | 라이선스 | 후보 단계 가공 |
|---|---|---|---|---|
| `splash_02.ogg` | 40 CC0 water / splash / slime SFX | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | CC0 1.0 | 앞 무음 제거, 0.68배속, 450~2200Hz, 감쇠, 직접 합성 몸통과 혼합 |

**근거는 페이지 표시다.** 위 주소의 License(s) 칸에 CC0로 표시되어 있고 올린 사람은 rubberduck이다. zip 안에 라이선스 파일은 없고 ogg 태그에도 라이선스 정보가 없다 (2026-11-08 확인). 전문: `licenses/License_CC0.txt` (creativecommons.org에서 받은 CC0 1.0).
