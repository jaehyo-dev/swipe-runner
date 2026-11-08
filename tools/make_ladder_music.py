#!/usr/bin/env python3
"""음악 사다리 7곡을 다시 합성해 assets/audio/music/에 저장한다 (numpy, ffmpeg 필요).

리샘플이 아니라 review/v0.3.1/music/make_music.py의 합성을 템포만 바꿔 다시 하므로 음 높이가 그대로다.
사용: python3 tools/make_ladder_music.py  (기준을 못 맞추면 종료 코드 1)
결과: assets/audio/music/bgm_<BPM>_<편곡>.ogg, review/v0.4.0/music.md
"""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "review/v0.3.1/music"))
import make_music as mm

# scripts/logic/music_ladder.gd의 STEPS와 같은 순서
LADDER = [(100, "orig"), (105, "orig"), (110, "a"), (115, "a"), (120, "b"), (125, "b"), (130, "b")]
OUT = ROOT / "assets/audio/music"
REPORT = ROOT / "review/v0.4.0/music.md"
LOOP_BEATS = 64


def main():
    mm.self_test()
    gains = mm.game_gains()
    crash_peak = 10 ** (-0.7 / 20) * 10 ** (gains["SFX_DB"] / 20)
    target = None
    errors, lines = [], ["# 음악 사다리 7곡 측정", "", "`python3 tools/make_ladder_music.py`가 만든 파일을 다시 디코딩해 쟀다.", "",
                         "| 파일 | 길이 | 표본 수 | A 가중 | 피크 | 4kHz 위 | 반복 이음매 (곡 안 99.9%) | 크기 |", "|---|---|---|---|---|---|---|---|"]
    for bpm, arr in LADDER:
        x = mm.render(arr, bpm)
        if target is None:  # 원본 100BPM의 크기에 나머지를 맞춘다
            target = mm.v2.a_weighted_db(mm.mono(x))
        x = x * 10 ** ((target - mm.v2.a_weighted_db(mm.mono(x))) / 20)
        data, back = mm.encode(x)
        name = f"bgm_{bpm}_{arr}.ogg"
        (OUT / name).write_bytes(data)
        level = mm.v2.a_weighted_db(mm.mono(back))
        peak = float(np.abs(back).max())
        share = mm.high_share(back)
        seam = float(np.abs(back[0] - back[-1]).max())
        step = float(np.quantile(np.abs(np.diff(back, axis=0)), 0.999))
        want = round(LOOP_BEATS * 60.0 / bpm * mm.SR)
        lines.append(f"| {name} | {len(back) / mm.SR:.3f}초 | {len(back)} | {level:.2f}dB | {20 * np.log10(peak):.1f}dBFS | {share * 100:.1f}% | {seam:.4f} ({step:.4f}) | {len(data) // 1024}KB |")
        print(lines[-1])
        if abs(len(back) - want) > 1:
            errors.append(f"{name}: 표본 수 {len(back)}, 기준 {want}")
        if abs(level - target) > mm.LEVEL_TOLERANCE_DB:
            errors.append(f"{name}: 크기 {level:.2f}dB, 기준 {target:.2f}dB")
        if peak * 10 ** (gains["MUSIC_DB"] / 20) + crash_peak > 1.0:
            errors.append(f"{name}: 게임 크기에서 음악 피크 + 충돌 피크가 1을 넘음")
        if share > mm.HIGH_SHARE_LIMIT:
            errors.append(f"{name}: 4kHz 위 {share * 100:.1f}%")
        if seam > step * 2:
            errors.append(f"{name}: 반복 이음매 {seam:.4f}, 곡 안 99.9% {step:.4f}")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    for e in errors:
        print("실패:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
