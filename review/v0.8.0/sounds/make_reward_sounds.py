#!/usr/bin/env python3
"""v0.8.0 보상 소리 후보를 합성하고 기준을 숫자로 검사한다 (효과음 원칙: 한 가족, 귀 찌름 금지, 울림 없음).

  방울 "톡" orb_a·b·c: lane_c와 같은 재료(사인 몸통 + 유리빛 층). 기본 높이 E4. 게임은 줄 안에서 마단조 5음(E G A B D)을 따라 올린다.
                       크기는 lane보다 6dB 작게(A 가중).
  콤보 끊김 "툭" break_a·b·c: 아주 작고 낮게(lane보다 10dB 작게). 실망을 주되 거슬리지 않게.
  아슬아슬 "슉" close_a·b·c: lane_c 재료 + 부드러운 노이즈 바람(lane보다 4dB 작게).
사용: python3 review/v0.8.0/sounds/make_reward_sounds.py  (numpy, scipy, matplotlib, ffmpeg 필요, 기준을 못 맞추면 종료 코드 1)
결과: *.wav, audio_data.js, report.md, spectrograms.png. 시드가 고정돼 있어 다시 실행해도 같다.
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
import make_sounds_v3 as v3  # noqa: E402  voice(), finish(), air_to(), drop()

v2 = v3.v2
v1 = v3.v1
SR = v3.SR
LANE = ROOT / "assets/audio/sfx/lane.wav"
E4 = 329.63
# 종류: (lane보다 작게 dB, 길이 범위(초), 중심 주파수 상한 Hz, 4kHz 위 % 범위)
RULES = {
    "orb": (6.0, (0.06, 0.13), 1300.0, (0.0, 5.0)),
    "break": (10.0, (0.06, 0.16), 600.0, (0.0, 2.0)),
    "close": (4.0, (0.12, 0.24), 2200.0, (0.0, 12.0)),
}
BARS = 8
BEATS_PER_BAR = 4


def wind(rng, sec, low, high, attack, tau):
    """부드러운 바람: 걸러낸 노이즈가 attack초에 차오르고 tau로 사라진다."""
    t = np.arange(int(sec * SR)) / SR
    return v1.band(rng.standard_normal(len(t)), low, high) * (1 - np.exp(-t / attack)) * np.exp(-t / tau)


def orb_a(rng):
    """맑은 톡: lane_c 몸통을 E4에 짧게, 유리빛 조금 더."""
    return v3.voice(0.09, E4 * 0.94, E4, tau=0.018, glass=0.18, glide_sec=0.012)


def orb_b(rng):
    """방울 톡: E4 몸통 + 한 옥타브 위 작은 물방울이 바로 붙는다."""
    x = v3.voice(0.1, E4 * 0.94, E4, tau=0.018, glass=0.08, glide_sec=0.012)
    blip = np.zeros_like(x)
    d = v3.drop(E4 * 2, 0.06)
    blip[:len(d)] = 0.35 * d
    return x + blip


def orb_c(rng):
    """부드러운 톡: 유리빛 없이 몸통 + 옥타브 배음, 조금 더 길게."""
    t = np.arange(int(0.11 * SR)) / SR
    body = np.sin(2 * np.pi * E4 * t) + 0.3 * np.sin(2 * np.pi * 2 * E4 * t)
    return body * np.exp(-t / 0.024)


def break_a(rng):
    """내려가는 툭: E3 → C#3, 유리빛 없음."""
    return v3.voice(0.1, 164.8, 138.6, tau=0.03, glass=0.0, glide_sec=0.06)


def break_b(rng):
    """막힌 툭: 낮은 몸통 + 아주 작은 낮은 노이즈 (천에 막힌 느낌)."""
    x = v3.voice(0.09, 155.6, 146.8, tau=0.025, glass=0.0, glide_sec=0.03)
    return x + 0.25 * wind(rng, 0.09, 150, 600, 0.002, 0.02)


def break_c(rng):
    """두 번 툭: B3에서 E3로 짧게 두 번 (아쉬움)."""
    a = v3.voice(0.05, 246.9, 246.9, tau=0.014, glass=0.0)
    b = v3.voice(0.08, 164.8, 155.6, tau=0.025, glass=0.0)
    return v3.mix(0.13, (0, 0.7 * a), (0.05, b))


def close_a(rng):
    """스치는 슉: 1~3kHz 바람이 빠르게 차올라 사라짐 + 작은 lane_c 몸통."""
    sec = 0.18
    return v3.mix(sec, (0, wind(rng, sec, 1000, 3000, 0.02, 0.05)), (0.0, 0.5 * v3.voice(0.09, 420, 640)))


def close_b(rng):
    """지나가는 슉: 바람이 높은 쪽에서 낮은 쪽으로 (휙 지나감) + 몸통."""
    sec = 0.2
    hi = wind(rng, sec, 1800, 4000, 0.015, 0.035)
    lo = wind(rng, sec, 700, 1800, 0.04, 0.06)
    return v3.mix(sec, (0, 0.8 * hi), (0.02, lo), (0, 0.4 * v3.voice(0.09, 420, 640)))


def close_c(rng):
    """짧은 숨 슉: 더 짧고 부드럽게, 몸통이 앞에 선다."""
    sec = 0.14
    return v3.mix(sec, (0, 0.7 * wind(rng, sec, 900, 2500, 0.012, 0.035)), (0, 0.7 * v3.voice(0.09, 440, 660)))


CANDIDATES = {"orb": [orb_a, orb_b, orb_c], "break": [break_a, break_b, break_c], "close": [close_a, close_b, close_c]}


def measure(x):
    high = 100 * v2.band_energy(x, 4000, SR) / v2.band_energy(x, 0, SR)
    return {"len": len(x) / SR, "c": v2.centroid_hz(x), "high": high, "a": v2.a_weighted_db(x), "peak": 20 * np.log10(np.abs(x).max())}


def check(name, m, target, rule):
    _, length, top, high = rule
    errors = []
    if not length[0] <= m["len"] <= length[1]:
        errors.append(f"{name}: 길이 {m['len']:.3f}초")
    if m["c"] > top:
        errors.append(f"{name}: 중심 {m['c']:.0f}Hz > {top:.0f}")
    if not high[0] <= m["high"] <= high[1]:
        errors.append(f"{name}: 4kHz 위 {m['high']:.1f}%")
    if abs(m["a"] - target) > 0.2:
        errors.append(f"{name}: A 가중 {m['a']:.1f}dB, 목표 {target:.1f}dB")
    if m["peak"] > -1.0:
        errors.append(f"{name}: 피크 {m['peak']:.1f}dBFS")
    return errors


def cut_bgm(track, beats, bpm):
    """같이 듣기용 8마디. 게임 곡의 앞부분을 자른다."""
    sec = beats * 60.0 / bpm
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(ROOT / "assets/audio/music" / track), "-t", f"{sec:.6f}", "-c:a", "libvorbis", "-q:a", "3", "-f", "ogg", "-"],
                          capture_output=True, check=True).stdout


def write_graph(sounds):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, len(sounds), figsize=(2.4 * len(sounds), 3), squeeze=False)
    for ax, (name, x) in zip(axes[0], sounds.items()):
        ax.specgram(x + 1e-9, NFFT=512, Fs=SR, noverlap=448, vmin=-120, vmax=-30, cmap="magma")
        ax.set_ylim(0, 8000)
        ax.set_title(name, fontsize=10)
        ax.set_xlabel("sec", fontsize=8)
    fig.tight_layout()
    fig.savefig(HERE / "spectrograms.png", dpi=80)


def main():
    lane = v2.load_wav(LANE)
    lane_m = measure(lane)
    errors, sounds = [], {"lane": lane}
    lines = ["# v0.8.0 보상 소리 후보 측정", "", "`python3 make_reward_sounds.py`가 파일을 다시 읽어 잰 값. A 가중 크기·중심 주파수는 후보 3차와 같은 함수.", "",
             "| 소리 | 설명 | 길이 | 중심 | 4kHz 위 | A 가중 (목표) | 피크 |", "|---|---|---|---|---|---|---|",
             f"| lane (기준) | 게임의 레인 이동 | {lane_m['len']:.3f}초 | {lane_m['c']:.0f}Hz | {lane_m['high']:.1f}% | {lane_m['a']:.1f}dB | {lane_m['peak']:.1f}dBFS |"]
    for kind, makers in CANDIDATES.items():
        rule = RULES[kind]
        target = lane_m["a"] - rule[0]
        for i, make in enumerate(makers):
            letter = "abc"[i]
            name = f"{kind}_{letter}"
            x = v3.finish(make(np.random.default_rng(800 + 10 * i + len(kind))))
            x = x * 10 ** ((target - v2.a_weighted_db(x)) / 20)
            path = HERE / f"{name}.wav"
            v2.save_wav(path, x)
            y = v2.load_wav(path)
            sounds[name] = y
            m = measure(y)
            errors += check(name, m, target, rule)
            lines.append(f"| {name} | {make.__doc__} | {m['len']:.3f}초 | {m['c']:.0f}Hz | {m['high']:.1f}% | {m['a']:.1f}dB ({target:.1f}) | {m['peak']:.1f}dBFS |")
    data = {name: base64.b64encode((HERE / f"{name}.wav").read_bytes()).decode() for name in sounds if name != "lane"}
    data["lane_c"] = base64.b64encode(LANE.read_bytes()).decode()
    data["bgm_100"] = base64.b64encode(cut_bgm("bgm_100_orig.ogg", BARS * BEATS_PER_BAR, 100)).decode()
    data["bgm_160"] = base64.b64encode(cut_bgm("bgm_160_b.ogg", BARS * BEATS_PER_BAR, 160)).decode()
    (HERE / "audio_data.js").write_text("window.SOUND_DATA = " + json.dumps(data) + ";\n", encoding="utf-8")
    write_graph(sounds)
    lines += ["", "기준: 방울 lane보다 6dB, 끊김 10dB, 아슬아슬 4dB 작게(A 가중). 중심 주파수 상한 방울 1.3kHz(5음 위로 올려도 E4 → A5), 끊김 600Hz, 아슬아슬 2.2kHz. 울림 없음, 피크 -1dBFS 이하.",
              "", "귀로 듣는 판단은 사용자 몫이다. 게임에는 일단 A가 들어간다 (`tools/make_final_sounds.py`)."]
    (HERE / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[6:-4]))
    for e in errors:
        print("실패:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
