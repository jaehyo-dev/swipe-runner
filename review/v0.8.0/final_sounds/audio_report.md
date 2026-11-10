# 확정 소리 측정 (v0.8.0에 다시 만듦)

`python3 tools/make_final_sounds.py`가 만든 파일을 다시 읽어 쟀다. A 가중 크기·중심 주파수는 후보 보고서와 같은 함수(`make_sounds_v2.py`).

| 파일 | 원본 | 높이 | 밝기 | 길이 (예상) | 중심 주파수 | A 가중 크기 | 피크 | 끝 30ms 100~150Hz 전 → 후 |
|---|---|---|---|---|---|---|---|---|
| sfx/lane.wav | sounds/sfx/lane_c.wav | +0 | 없음 | 0.100초 (0.10) | 473Hz | -22.9dB | -7.5dBFS | -74.6 → -84.1dBFS |
| sfx/jump.wav | sounds_v3/jump_b.wav | +5 | 12000.0 | 0.217초 (0.22) | 715Hz | -21.2dB | -6.1dBFS | -69.4 → -80.7dBFS |
| sfx/slide.wav | sounds_v3/slide_a.wav | +7 | 12000.0 | 0.267초 (0.28) | 1171Hz | -21.3dB | -5.9dBFS | -74.6 → -81.6dBFS |
| sfx/land.wav | sounds_v2/land_c.wav | -10 | 12000.0 | 0.374초 (0.37) | 1629Hz | -19.8dB | -4.8dBFS | -132.2 → -130.2dBFS |
| sfx/crash.wav | sounds_v3/crash_c.wav | +9 | 9500.0 | 0.428초 (0.43) | 1626Hz | -18.9dB | -0.7dBFS | -56.8 → -64.2dBFS |
| sfx/orb.wav | ../v0.8.0/sounds/orb_a.wav | +0 | 없음 | 0.090초 (0.09) | 361Hz | -28.9dB | -9.7dBFS | -73.8 → -83.2dBFS |
| sfx/combo_break.wav | ../v0.8.0/sounds/break_a.wav | +0 | 없음 | 0.100초 (0.10) | 155Hz | -32.9dB | -8.5dBFS | -32.6 → -37.4dBFS |
| sfx/close.wav | ../v0.8.0/sounds/close_a.wav | +0 | 없음 | 0.180초 (0.18) | 1114Hz | -26.9dB | -11.5dBFS | -80.9 → -89.7dBFS |

그래프: `audio_fade.png` (위 페이드 전, 가운데 페이드 후, 아래 끝 80ms 파형을 크게).

## 끝부분 저음

끝 30ms 페이드로 모든 효과음의 마지막 표본이 정확히 0이 된다(자체 검사). 표의 100~150Hz 크기는 착지(원래 소리 없음) 말고 모두 7dB 이상 줄었다.
가장 큰 충돌도 페이드 전 -56.8dBFS로 소리 본체(피크 -0.7dBFS)보다 56dB 작았다. 사용자가 본 덩어리는 끝 30ms보다 앞까지 이어지지 않아 페이드로 충분하다.

## 페이지와 같은지 (2026-11-08)

크로미움 `OfflineAudioContext`에 페이지와 같은 노드(playbackRate + BiquadFilter 로우패스 Q 0.5)를 연결해 5개를 렌더링하고, 페이드 전 결과와 표본 단위로 비교했다. 차이는 -91.5~-93.5dB(소리 대비)로 16비트 반올림 수준이다.
