#!/usr/bin/env python3
"""30초 녹화 소리에서 음악과 효과음의 A 가중 크기를 잰다. 음악·효과음은 같은 장면을 버스 하나씩만 켜고 따로 녹음한 것.
사용: python3 measure_loudness.py <음악만.avi> <효과음만.avi> <전체.avi> <events.json> <결과.md>  (목표 2~3dB를 못 맞추면 종료 코드 1)
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "review/v0.2.8/sounds_v2"))
import make_sounds_v2 as v2

SR = 44100
LENGTHS = {"lane": 0.100, "jump": 0.217, "slide": 0.267, "land": 0.374, "crash": 0.428}
PITCH_ROOM = 1.1  # 높이 무작위로 길이가 조금 달라지는 몫
LEAD = 0.05       # 기록 시각보다 소리가 앞설 수 있어(믹스 단위) 앞을 넉넉히 잡는다. 무음은 평균에서 빠진다


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-acodec", "pcm_s16le", "-ar", str(SR), "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16).reshape(-1, 2) / 32768.0


def main():
    music_path, sfx_path, mix_path, events_path, out = sys.argv[1:]
    music, sfx, mix = load(music_path), load(sfx_path), load(mix_path)
    events = json.load(open(events_path, encoding="utf-8"))
    sounds = [(e["at"], e["sound"]) for e in events if e["type"] == "sound"]
    first = next(e["at"] for e in events if e["type"] == "input")
    crash = next(e["at"] for e in events if e["type"] == "crash")
    # 음악: 첫 입력부터. 충돌로 낮아진 1초는 뺀다
    keep = np.ones(len(music), bool)
    keep[:int(first * SR)] = False
    keep[int(crash * SR):int((crash + 1.0) * SR)] = False
    music_db = v2.a_weighted_db(music[keep].mean(axis=1))
    per = {}
    for i, (at, name) in enumerate(sounds):
        end = at + LENGTHS[name] * PITCH_ROOM
        if (i > 0 and sounds[i - 1][0] + LENGTHS[sounds[i - 1][1]] * PITCH_ROOM + LEAD > at - LEAD) or (i + 1 < len(sounds) and sounds[i + 1][0] - LEAD < end + LEAD):
            continue  # 다른 효과음과 겹친 것은 뺀다
        x = sfx[max(0, int((at - LEAD) * SR)):int((end + LEAD) * SR)].mean(axis=1)
        per.setdefault(name, []).append(v2.a_weighted_db(x))
    means = {k: float(np.mean(v)) for k, v in per.items()}
    target = float(np.mean([means[k] for k in ("lane", "jump", "slide")]))
    gap = target - music_db
    peak = float(np.abs(mix).max())
    clipped = int((np.abs(mix) >= 32767 / 32768).sum())
    rms = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)))
    lines = ["# 소리 크기 측정 (음악 vs 효과음)", "", "30초 녹화(Movie Maker)의 소리를 쟀다. 같은 장면을 음악만·효과음만 켜서 따로 녹음했고, 잰 함수는 후보 보고서와 같은 `a_weighted_db`.", "",
             "| 소리 | 재생 횟수(겹치지 않은 것) | A 가중 크기 |", "|---|---|---|"]
    for k in ("lane", "jump", "slide", "land", "crash"):
        if k in per:
            lines.append(f"| {k} | {len(per[k])} | {means[k]:.1f}dB |")
    lines += [f"| **lane·jump·slide 평균** | | **{target:.1f}dB** |", f"| **음악** (첫 입력부터, 낮아진 1초 제외) | | **{music_db:.1f}dB** |", "",
              f"**음악이 효과음보다 {gap:.2f}dB 작다** (목표 2~3dB).", "",
              f"피크: 음악+효과음 전체 녹화 {20 * np.log10(peak):.2f}dBFS, 잘린 표본 {clipped}개.",
              f"참고: A 가중 없는 RMS는 음악 {rms(music[keep].mean(axis=1)):.1f}dB. A 가중은 저음을 크게 깎아, 저음이 많은 음악이 숫자보다 크게 느껴질 수 있다.", "",
              "값 바꾸는 곳: `scripts/audio_manager.gd`의 `MUSIC_DB`, `SFX_DB`.", ""]
    Path(out).write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    return 0 if 2.0 <= gap <= 3.0 and clipped == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
