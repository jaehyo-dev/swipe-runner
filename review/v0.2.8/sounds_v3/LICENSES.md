# 소리 후보 3차 출처와 라이선스

## 후보별 출처

| 후보 | 출처 | 라이선스 |
|---|---|---|
| jump_a·b·c, slide_a·b, crash_a·b | `make_sounds_v3.py`로 직접 합성 (사인파 + 걸러낸 노이즈) | 프로젝트 소유 |
| land_a·b·c | 직접 합성 몸통 + `splash_10.ogg` 가공 | CC0 원본 + 프로젝트 가공 |
| slide_c | `slime_13.ogg` 가공 + 직접 합성 몸통 | CC0 원본 + 프로젝트 가공 |
| crash_c | `splash_02.ogg` 가공 + 직접 합성 몸통 | CC0 원본 + 프로젝트 가공 |

bgm_3, lane_c는 `../sounds/`, 비교용 jump_a·land_c는 `../sounds_v2/`의 소리다.

## CC0 원본 파일

| 원본 파일 | 팩 | 작성자 | 주소 | 라이선스 | 쓰는 곳 | 가공 |
|---|---|---|---|---|---|---|
| `slime_13.ogg` | 40 CC0 water / splash / slime SFX | rubberduck | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | CC0 1.0 | slide_c | 앞 무음 제거, 0.62배속, 300~3000Hz, 감쇠 |
| `splash_10.ogg` | 같음 | rubberduck | 같음 | CC0 1.0 | land_a·b·c | 앞 무음 제거, 600~2500Hz, 감쇠 |
| `splash_02.ogg` | 같음 | rubberduck | 같음 | CC0 1.0 | crash_c | 앞 무음 제거, 0.68배속, 450~2200Hz, 감쇠 |

확인 내용 (2026-11-08):

- **페이지**: 위 주소의 License(s) 칸에 CC0로 표시되어 있고, 파일을 올린 사람은 rubberduck이다. 로그인 없이 받았다.
- **파일**: zip 안에 라이선스 파일은 **없다**. ogg 태그에는 ARTIST=rubberduck만 있고 라이선스 태그는 없다. 그래서 CC0의 근거는 페이지 표시다.
- `sources/License_CC0.txt`는 creativecommons.org에서 받은 CC0 1.0 전문이다.
- 받은 zip `water-splash-slime-sfx.zip`의 SHA-256: `7cd39abb49d4362a37ba18dc0e454c7dc1d08029d4e5b683149046bc237b2eba`

쓰지 않은 나머지 37개 파일은 넣지 않았다.
