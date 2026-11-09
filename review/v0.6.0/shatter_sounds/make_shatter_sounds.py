#!/usr/bin/env python3
"""부서짐 소리 "칭" 후보 A·B·C를 합성하고 기준을 숫자로 검사한다 (효과음 3차 원칙).

재료는 lane_c와 같다: 사인 몸통 + 유리빛 층, 울림 없음. 높이는 귀를 찌르지 않게 낮춘다.
사용: python3 make_shatter_sounds.py  (numpy, scipy, matplotlib, ffmpeg 필요, 기준을 못 맞추면 종료 코드 1)
결과: shatter_a·b·c.wav, audio_data.js, report.md, spectrograms.png. 시드가 고정돼 있어 다시 실행해도 같다.
"""
import base64
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "review/v0.2.8/sounds_v3"))
import make_sounds_v3 as v3  # noqa: E402  voice(), finish(), air_to(), droplets()

v2 = v3.v2
SR = v3.SR
LANE = ROOT / "assets/audio/sfx/lane.wav"
LENGTH_RANGE = (0.12, 0.22)
MAX_CENTROID = 1300.0  # 3차의 "귀를 찌르지 않는 높이" (점프 1.2kHz 근처)
HIGH_RANGE = (1.0, 5.0)  # 4kHz 위 에너지 %
QUIETER_DB = 3.0       # lane보다 이만큼 작게
BARS = 8
BEATS_PER_BAR = 4


def shatter_a(rng):
    """맑은 칭: lane_c를 위로 옮긴 짧은 사인, 유리빛을 조금 더."""
    sec = 0.16
    x = v3.voice(sec, 880.0, 1175.0, tau=0.032, glass=0.3, glide_sec=0.03)
    return v3.air_to(x, rng, 0.03, 0.008)


def shatter_b(rng):
    """겹 칭: 낮은 음 뒤에 15ms 늦게 높은 음이 따라와 부서지는 느낌."""
    sec = 0.18
    x = v3.mix(sec, (0, v3.voice(sec, 740.0, 988.0, tau=0.03, glass=0.2, glide_sec=0.03)),
               (0.015, 0.65 * v3.voice(sec - 0.015, 988.0, 1319.0, tau=0.024, glass=0.25, glide_sec=0.02)))
    return v3.air_to(x, rng, 0.025, 0.008)


def shatter_c(rng):
    """흩어지는 칭: 조금 낮은 몸통 + 작은 조각 소리 5개가 흩어진다."""
    sec = 0.2
    x = v3.mix(sec, (0, v3.voice(sec, 659.0, 880.0, tau=0.03, glass=0.25, glide_sec=0.03)),
               (0, v3.droplets(rng, sec, 0.012, 0.11, 5, 900.0, 1350.0, 0.5)))
    return v3.air_to(x, rng, 0.03, 0.01)


CANDIDATES = {"a": shatter_a, "b": shatter_b, "c": shatter_c}


def measure(x):
    high = 100 * v2.band_energy(x, 4000, SR) / v2.band_energy(x, 0, SR)
    return {"len": len(x) / SR, "c": v2.centroid_hz(x), "high": high, "a": v2.a_weighted_db(x), "peak": 20 * np.log10(np.abs(x).max())}


def check(name, m, target):
    errors = []
    if not LENGTH_RANGE[0] <= m["len"] <= LENGTH_RANGE[1]:
        errors.append(f"{name}: 길이 {m['len']:.3f}초")
    if m["c"] > MAX_CENTROID:
        errors.append(f"{name}: 중심 {m['c']:.0f}Hz")
    if not HIGH_RANGE[0] <= m["high"] <= HIGH_RANGE[1]:
        errors.append(f"{name}: 4kHz 위 {m['high']:.1f}%")
    if abs(m["a"] - target) > 0.2:
        errors.append(f"{name}: A 가중 {m['a']:.1f}dB, 목표 {target:.1f}dB")
    if m["peak"] > -1.0:
        errors.append(f"{name}: 피크 {m['peak']:.1f}dBFS")
    return errors


def cut_bgm(track, beats, bpm):
    """같이 듣기용 8마디. 게임 곡의 앞부분을 표본 단위 길이로 자른다."""
    sec = beats * 60.0 / bpm
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(ROOT / "assets/audio/music" / track), "-t", f"{sec:.6f}", "-c:a", "libvorbis", "-q:a", "3", "-f", "ogg", "-"],
                          capture_output=True, check=True).stdout


def write_graph(sounds):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, len(sounds), figsize=(3 * len(sounds), 3), squeeze=False)
    for ax, (name, x) in zip(axes[0], sounds.items()):
        ax.specgram(x + 1e-9, NFFT=512, Fs=SR, noverlap=448, vmin=-120, vmax=-30, cmap="magma")
        ax.set_ylim(0, 8000)
        ax.set_title(name, fontsize=10)
        ax.set_xlabel("sec", fontsize=8)
    fig.tight_layout()
    fig.savefig(HERE / "spectrograms.png", dpi=90)


def main():
    lane = v2.load_wav(LANE)
    lane_m = measure(lane)
    target = lane_m["a"] - QUIETER_DB
    errors, rows, sounds = [], [], {"lane": lane}
    for letter, make in CANDIDATES.items():
        x = v3.finish(make(np.random.default_rng(600 + ord(letter))))
        x = x * 10 ** ((target - v2.a_weighted_db(x)) / 20)
        path = HERE / f"shatter_{letter}.wav"
        v2.save_wav(path, x)
        y = v2.load_wav(path)
        sounds[letter.upper()] = y
        m = measure(y)
        errors += check(letter.upper(), m, target)
        rows.append((letter.upper(), make.__doc__, m))
    data = {f"shatter_{k}": base64.b64encode((HERE / f"shatter_{k}.wav").read_bytes()).decode() for k in CANDIDATES}
    data["lane_c"] = base64.b64encode(LANE.read_bytes()).decode()
    data["bgm_100"] = base64.b64encode(cut_bgm("bgm_100_orig.ogg", BARS * BEATS_PER_BAR, 100)).decode()
    data["bgm_160"] = base64.b64encode(cut_bgm("bgm_160_b.ogg", BARS * BEATS_PER_BAR, 160)).decode()
    (HERE / "audio_data.js").write_text("window.SOUND_DATA = " + json.dumps(data) + ";\n", encoding="utf-8")
    write_graph(sounds)
    lines = ["# 부서짐 소리 후보 측정", "", "`python3 make_shatter_sounds.py`가 파일을 다시 읽어 잰 값. A 가중 크기·중심 주파수는 후보 3차와 같은 함수.",
             f"기준: 길이 {LENGTH_RANGE[0]}~{LENGTH_RANGE[1]}초, 중심 {MAX_CENTROID:.0f}Hz 이하, 4kHz 위 {HIGH_RANGE[0]}~{HIGH_RANGE[1]}%, A 가중 크기 lane보다 {QUIETER_DB:.0f}dB 작게, 울림 없음.", "",
             "| 소리 | 설명 | 길이 | 중심 | 4kHz 위 | A 가중 | 피크 |", "|---|---|---|---|---|---|---|",
             f"| lane (기준) | 게임의 레인 이동 | {lane_m['len']:.3f}초 | {lane_m['c']:.0f}Hz | {lane_m['high']:.1f}% | {lane_m['a']:.1f}dB | {lane_m['peak']:.1f}dBFS |"]
    for name, doc, m in rows:
        lines.append(f"| {name} | {doc} | {m['len']:.3f}초 | {m['c']:.0f}Hz | {m['high']:.1f}% | {m['a']:.1f}dB | {m['peak']:.1f}dBFS |")
    (HERE / "report.md").write_text("\n".join(lines) + "\n\n귀로 듣는 판단은 사용자 몫이다. 게임에는 일단 A가 들어간다.\n", encoding="utf-8")
    print("\n".join(lines[6:]))
    for e in errors:
        print("실패:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
