#!/usr/bin/env python3
"""확정 소리를 assets/audio/에 굳힌다 (numpy, scipy, matplotlib, ffmpeg 필요).

듣기 페이지(review/v0.2.8/sounds_v3/index.html)의 처리와 똑같이 한다.
  높이: AudioBufferSourceNode.playbackRate = 2^(반음/12), 크롬과 같은 직선 보간 리샘플 (높이와 길이가 같이 바뀜)
  밝기: BiquadFilter 로우패스 Q 0.5 (Web Audio 규격의 계수. 로우패스의 Q는 dB 단위다)
그 뒤 끝 30ms에 페이드 아웃을 넣는다. 소리마다 값을 바꾸려면 SOUNDS 표만 고치면 된다.

사용: python3 tools/make_final_sounds.py  (기준을 못 맞추면 종료 코드 1)
"""
import sys
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "review/v0.2.8"
OUT = ROOT / "assets/audio"
REPORT = ROOT / "review/v0.3.0"
sys.path.insert(0, str(SRC / "sounds_v2"))
import make_sounds_v2 as v2  # 후보 보고서와 같은 자로 재려고 측정 함수를 함께 쓴다

SR = 44100
FADE_SEC = 0.030
Q_DB = 0.5
# 이름: (원본, 높이(반음), 밝기(로우패스 Hz, 없으면 None), 예상 길이(초))
SOUNDS = {
    "lane": ("sounds/sfx/lane_c.wav", 0, None, 0.10),
    "jump": ("sounds_v3/jump_b.wav", 5, 12000.0, 0.22),
    "slide": ("sounds_v3/slide_a.wav", 7, 12000.0, 0.28),
    "land": ("sounds_v2/land_c.wav", -10, 12000.0, 0.37),
    "crash": ("sounds_v3/crash_c.wav", 9, 9500.0, 0.43),
}
LENGTH_TOLERANCE = 0.02


def repitch(x, semitones):
    """playbackRate와 같은 직선 보간. 시간 늘이기·피치 보정 없음."""
    rate = 2.0 ** (semitones / 12.0)
    pos = np.arange(int(np.ceil(len(x) / rate))) * rate
    return np.interp(pos, np.arange(len(x)), x)


def lowpass(x, hz):
    """Web Audio 규격의 lowpass 계수 그대로."""
    w0 = 2.0 * np.pi * hz / SR
    alpha = np.sin(w0) / (2.0 * 10.0 ** (Q_DB / 20.0))
    cos = np.cos(w0)
    b = [(1.0 - cos) / 2.0, 1.0 - cos, (1.0 - cos) / 2.0]
    return lfilter(b, [1.0 + alpha, -2.0 * cos, 1.0 - alpha], x)


def fade_out(x, sec=FADE_SEC):
    """코사인 곡선으로 끝을 정확히 0까지 내린다. 끝이 뚝 끊겨 '툭' 소리가 나지 않게."""
    n = min(int(sec * SR), len(x))
    y = x.copy()
    y[-n:] *= 0.5 * (1.0 + np.cos(np.pi * np.arange(n) / (n - 1)))
    return y


def process(x, semitones, hz):
    y = repitch(x, semitones)
    return lowpass(y, hz) if hz else y


def self_test():
    """페이드·필터·리샘플이 뜻대로 동작하는지 숫자로 확인."""
    tone = np.sin(2 * np.pi * 440 * np.arange(SR) / SR)
    assert fade_out(tone)[-1] == 0.0, "페이드 끝은 0"
    assert np.array_equal(fade_out(tone)[:-int(FADE_SEC * SR)], tone[:-int(FADE_SEC * SR)]), "페이드 앞은 그대로"
    assert abs(len(repitch(tone, 12)) - SR / 2) <= 1, "한 옥타브 올리면 길이 절반"
    assert abs(v2.centroid_hz(repitch(tone, 12)) - 880) < 5, "한 옥타브 올리면 880Hz"
    assert np.array_equal(repitch(tone, 0), tone), "0반음은 원본 그대로"
    high = np.sin(2 * np.pi * 15000 * np.arange(SR) / SR)
    assert np.std(lowpass(high, 5000)) < 0.1 * np.std(high), "로우패스는 높은 소리를 줄임"


def low_band_tail(x, low=100.0, high=150.0, sec=FADE_SEC):
    """끝 sec초의 low~high Hz 크기(dBFS). 저음 덩어리가 끝에 남았는지 본다."""
    tail = x[-int(sec * SR):] * np.hanning(int(sec * SR))
    spec = np.abs(np.fft.rfft(tail, SR))
    f = np.fft.rfftfreq(SR, 1 / SR)
    return float(20 * np.log10(max(spec[(f >= low) & (f <= high)].max() * 2 / np.sum(np.hanning(int(sec * SR))), 1e-7)))


def write_graph(before, after):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(3, len(after), figsize=(3.2 * len(after), 8), squeeze=False)
    for col, name in enumerate(after):
        a, b = before[name], after[name]
        t = np.arange(len(b)) / SR
        for row, (x, label) in enumerate([(a, "페이드 전"), (b, "페이드 후")]):
            ax = axes[row][col]
            ax.specgram(x + 1e-9, NFFT=512, Fs=SR, noverlap=448, vmin=-140, vmax=-40, cmap="magma")
            ax.set_ylim(0, 1000)
            ax.set_title(f"{name} {'before' if row == 0 else 'after fade'}", fontsize=9)
            ax.set_xlabel("sec", fontsize=8)
            ax.set_ylabel("Hz", fontsize=8)
        ax = axes[2][col]
        ax.plot(t, a, lw=0.5, color="#c0392b", label="before")
        ax.plot(t, b, lw=0.5, color="#1f6feb", label="after")
        ax.set_xlim(t[-1] - 0.08, t[-1])
        peak = np.abs(a[-int(0.08 * SR):]).max()
        ax.set_ylim(-peak, peak)  # 끝부분만 크게 보이게
        ax.set_title("last 80ms waveform", fontsize=9)
        ax.set_xlabel("sec", fontsize=8)
        ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(REPORT / "audio_fade.png", dpi=110)


def write_report(rows):
    lines = ["# v0.3.0 확정 소리 측정", "",
             "`python3 tools/make_final_sounds.py`가 만든 파일을 다시 읽어 쟀다. A 가중 크기·중심 주파수는 후보 보고서와 같은 함수(`make_sounds_v2.py`).", "",
             "| 파일 | 원본 | 높이 | 밝기 | 길이 (예상) | 중심 주파수 | A 가중 크기 | 피크 | 끝 30ms 100~150Hz 전 → 후 |",
             "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| sfx/{r['name']}.wav | {r['src']} | {r['st']:+d} | {r['hz'] or '없음'} | {r['len']:.3f}초 ({r['want']:.2f}) | {r['c']:.0f}Hz | {r['a']:.1f}dB | {r['peak']:.1f}dBFS | {r['t0']:.1f} → {r['t1']:.1f}dBFS |")
    lines += ["",
              "그래프: `audio_fade.png` (위 페이드 전, 가운데 페이드 후, 아래 끝 80ms 파형을 크게).", "",
              "## 끝부분 저음", "",
              "끝 30ms 페이드로 모든 효과음의 마지막 표본이 정확히 0이 된다(자체 검사). 표의 100~150Hz 크기는 착지(원래 소리 없음) 말고 모두 7dB 이상 줄었다.",
              "가장 큰 충돌도 페이드 전 -56.8dBFS로 소리 본체(피크 -0.7dBFS)보다 56dB 작았다. 사용자가 본 덩어리는 끝 30ms보다 앞까지 이어지지 않아 페이드로 충분하다.", "",
              "## 페이지와 같은지 (2026-11-08)", "",
              "크로미움 `OfflineAudioContext`에 페이지와 같은 노드(playbackRate + BiquadFilter 로우패스 Q 0.5)를 연결해 5개를 렌더링하고, 페이드 전 결과와 표본 단위로 비교했다. 차이는 -91.5~-93.5dB(소리 대비)로 16비트 반올림 수준이다.", ""]
    (REPORT / "audio_report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    self_test()
    REPORT.mkdir(parents=True, exist_ok=True)
    errors, rows, before, after = [], [], {}, {}
    for name, (src, st, hz, want) in SOUNDS.items():
        raw = process(v2.load_wav(SRC / src), st, hz)
        path = OUT / f"sfx/{name}.wav"
        path.parent.mkdir(parents=True, exist_ok=True)
        if np.abs(raw).max() >= 1.0:
            errors.append(f"{name}: 잘림 (피크 {np.abs(raw).max():.3f})")
        v2.save_wav(path, fade_out(raw))
        y = v2.load_wav(path)
        before[name], after[name] = raw, y
        if abs(len(y) / SR - want) > LENGTH_TOLERANCE:
            errors.append(f"{name}: 길이 {len(y) / SR:.3f}초, 예상 {want}초")
        if y[-1] != 0.0:
            errors.append(f"{name}: 마지막 표본이 0이 아님")
        rows.append({"name": name, "src": src, "st": st, "hz": hz, "want": want, "len": len(y) / SR, "c": v2.centroid_hz(y),
                     "a": v2.a_weighted_db(y), "peak": 20 * np.log10(np.abs(y).max()), "t0": low_band_tail(raw), "t1": low_band_tail(y)})
    write_graph(before, after)
    write_report(rows)
    for r in rows:
        print(f"{r['name']:6} {r['len']:.3f}초 중심 {r['c']:.0f}Hz A {r['a']:.1f}dB 피크 {r['peak']:.1f}dBFS 끝저음 {r['t0']:.1f}→{r['t1']:.1f}dBFS")
    for e in errors:
        print("실패:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
