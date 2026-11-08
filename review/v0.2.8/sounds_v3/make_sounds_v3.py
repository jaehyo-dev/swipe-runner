#!/usr/bin/env python3
"""소리 후보 3차: 모든 효과음을 lane_c와 같은 재료로 만들고 새 기준을 숫자로 검사한다.

사용: python3 make_sounds_v3.py   (numpy, scipy, matplotlib, ffmpeg 필요)
결과: *.wav, audio_data.js, report.md, spectrograms.png. 기준을 못 맞춘 소리가 있으면 종료 코드 1.
1·2차 스크립트의 함수를 그대로 가져다 쓰므로 ../sounds, ../sounds_v2 폴더가 있어야 한다.
시드가 고정돼 있어 다시 실행해도 같은 소리가 나온다.
"""
import base64
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent / "sounds"), str(HERE.parent / "sounds_v2")]
import make_sounds as v1  # noqa: E402  lane_c를 만든 함수(finish)
import make_sounds_v2 as v2  # noqa: E402  측정 함수와 블룹·떨림

SR = v2.SR
FIRST, SECOND = v2.FIRST, HERE.parent / "sounds_v2"
KINDS, KOREAN, NAMES = v2.KINDS, v2.KOREAN, v2.NAMES
times, mix = v2.times, v2.mix
FS4, B4, E5, E6 = 369.99, 493.88, 659.26, 1318.51

# 기준 값 (추가 지시가 우선)
LENGTH_RANGE = {"jump": (0.23, 0.33), "slide": (0.30, 0.45), "land": (0.15, 0.25), "crash": (0.50, 0.80)}
RATIO_RANGE = (0.7, 2.0)
JUMP_MAX_HZ = 1200.0
HIGH_RANGE = (1.0, 5.0)  # 4kHz 위 에너지 %
MAX_TONAL_HZ = 1200.0
MAX_MUD = 25.0  # 200~400Hz 전체 대비 %
MAX_MUD_LATE = 1.0  # 80ms 뒤에 남은 200~400Hz, 전체 대비 %
MAX_SPIKE_DB = 6.0
A_RANGE = {"crash": (2.0, 4.0)}  # 나머지는 (-2, 2)
A_OFFSET = {"crash": 3.0}


# ---------- lane_c의 재료: 이 함수 하나로 모든 소리의 몸통을 만든다 ----------

def sweep(f0, f1, sec, glide_sec, curve):
    """f0→f1 사인파. glide_sec 뒤에는 f1에 머문다."""
    n = int(sec * SR)
    u = np.minimum(np.arange(n) / (glide_sec * SR), 1.0)
    return np.sin(2 * np.pi * np.cumsum(f0 * (f1 / f0) ** (u ** curve)) / SR)


def voice(sec, f0=420.0, f1=640.0, tau=0.028, body=1.0, glass=0.1, glide_sec=None):
    """사인 몸통(지수 감쇠) + 유리빛 층(1400→1500Hz, 크기 0.1, 감쇠 20ms). 기본값이 곧 lane_c다."""
    tone = sweep(f0, f1, sec, glide_sec or sec, 0.7) * v1.decay(sec, tau)
    return body * tone + glass * sweep(1400.0, 1500.0, sec, 0.1, 1.0) * v1.decay(sec, 0.02)


def finish(x):
    """lane_c와 같은 마감: 6kHz 위를 깎고(7.8kHz에서 0) 앞 2ms·뒤 12ms 페이드. lane_c처럼 울림은 넣지 않는다."""
    return v1.finish(x, 0.42)


def short(x, sec):
    """몸통을 sec 안에 끝낸다."""
    n = int(sec * SR)
    return x[:n] * np.hanning(2 * n)[n:] ** 0.5


def norm(x):
    return x / np.max(np.abs(x))


def air_to(x, rng, target, tau):
    """4kHz 위 비율이 target쯤 되도록 물기 노이즈를 더한다. 2.5~6kHz로 넓게 깔아 좁은 봉우리를 만들지 않는다.
    마감 필터가 6kHz 위를 한 번 더 깎아 실제 값은 target의 0.6배쯤 된다. 결과는 check_sound가 검사한다."""
    a = v1.band(rng.standard_normal(len(x)), 2500, 6000) * np.exp(-np.arange(len(x)) / SR / tau)
    hi, total = v2.band_energy(x, 4000, SR), v2.band_energy(x, 0, SR)
    need = (target * total - hi) / ((1 - target) * v2.band_energy(a, 4000, SR))
    return x + np.sqrt(max(need, 0.0)) * a


def spray(rng, sec, low, high, tau, flutter, depth=0.65):
    """물보라: 걸러낸 노이즈가 빠르게 차올라 사라지고, 떨림으로 물기를 준다."""
    t = times(sec)
    return (v2.band(rng.standard_normal(len(t)), low, high, 3) * (1 - np.exp(-t / 0.002)) * np.exp(-t / tau)
            * v2.wet_flutter(rng, sec, flutter, depth))


def balance(sec, *parts):
    """(시작, 소리, 에너지 몫)들을 몫대로 맞춰 섞는다. 게인이 아니라 실제 에너지로 비율을 정한다."""
    return mix(sec, *[(at, np.sqrt(part / np.sum(sig ** 2)) * sig) for at, sig, part in parts])


def drop(hz, sec=0.06):
    """작은 물방울: 위로 살짝 올라가며 빨리 사라지는 사인파."""
    t = times(sec)
    return sweep(hz, hz * 1.35, sec, 0.03, 1.0) * (1 - np.exp(-t / 0.001)) * np.exp(-t / 0.013)


def droplets(rng, sec, start, end, count, low, high, gain):
    """start~end에 물방울을 흩뿌린다. 뒤로 갈수록 작아진다."""
    parts = []
    for at in np.sort(rng.uniform(start, end, count)):
        fade = 1 - 0.7 * (at - start) / (end - start)
        parts.append((at, gain * fade * rng.uniform(0.6, 1.0) * drop(rng.uniform(low, high))))
    return mix(sec, *parts)


def recording(name, low, high, rate=1.0):
    """CC0 녹음: 앞 무음을 잘라 내고 재생 속도로 높이를 낮춘 뒤 대역을 거른다."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(HERE / "sources" / f"{name}.ogg"), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(float)
    x = x[np.argmax(np.abs(x) >= 0.1 * np.max(np.abs(x))):]
    n = int(len(x) / rate)
    return norm(v2.band(v2.warp(x, np.full(n, rate)), low, high, 4))


# ---------- 후보 ----------

def jump_a(rng):
    """lane_c의 뽁을 위로 늘린 퐁: B4→E5 (2차 jump_a를 한 옥타브 내림)."""
    sec = 0.27
    x = mix(sec, (0, voice(sec, B4, E5, tau=0.075, glide_sec=0.08)), (0, 0.5 * v2.bloop(rng, B4, E5, sec)))
    return air_to(x, rng, 0.025, 0.006)


def jump_b(rng):
    """더 낮고 둥근 퐁: F#4→B4 (jump_a에서 5반음 더 내림)."""
    sec = 0.29
    x = mix(sec, (0, voice(sec, FS4, B4, tau=0.085, glide_sec=0.08)), (0, 0.5 * v2.bloop(rng, FS4, B4, sec)))
    return air_to(x, rng, 0.02, 0.006)


def jump_c(rng):
    """물방울 퐁: B4→E5, 유리빛을 줄이고 블룹을 앞으로."""
    sec = 0.27
    x = mix(sec, (0, voice(sec, B4, E5, tau=0.065, body=0.55, glass=0.03, glide_sec=0.08)),
            (0, 1.3 * v2.bloop(rng, B4, E5, sec, 18.0)))
    return air_to(x, rng, 0.02, 0.006)


def slide_a(rng):
    """쭈욱: 늘어나는 lane_c 몸통 + 480→1150→520Hz로 미끄러지는 공명."""
    sec = 0.40
    n = int(sec * SR)
    u = np.arange(n) / n
    hz = 480 * (1150 / 480) ** np.sin(np.pi * u ** 0.8) ** 2 * (520 / 480) ** u
    stretch = norm(v2.resonant_sweep(rng.standard_normal(n), hz, 7.0)) * np.minimum(u / 0.01, 1) * (1 - u) ** 0.7
    x = mix(sec, (0, voice(sec, tau=0.13, body=0.8, glide_sec=0.2)), (0, 0.8 * stretch))
    return air_to(x, rng, 0.03, 0.015)


def slide_b(rng):
    """츄르륵: 1300→480Hz로 내려가는 젖은 노이즈 + 작은 거품 톡톡 + 짧은 lane_c 몸통."""
    sec = 0.42
    n = int(sec * SR)
    u = np.arange(n) / n
    hz = 1300 * (480 / 1300) ** u
    wet = norm(v2.lowpass(v2.resonant_sweep(rng.standard_normal(n), hz, 3.0), 2400.0, 2)) * v2.wet_flutter(rng, sec, 48, 0.8)
    x = mix(sec, (0, wet * np.minimum(u / 0.01, 1) * (1 - u) ** 0.7), (0, 0.9 * voice(sec)),
            (0, droplets(rng, sec, 0.04, sec - 0.05, 14, 550, 1150, 0.4)))
    return air_to(x, rng, 0.02, 0.015)


def slide_c(rng):
    """CC0 slime_13을 0.62배속으로 낮춘 뒤 lane_c 몸통과 합친다."""
    sec = 0.42
    n = int(sec * SR)
    slime = recording("slime_13", 300, 3000, 0.62)[:n]
    slime = slime * (1 - np.arange(len(slime)) / n) ** 0.6
    x = mix(sec, (0, slime), (0, 0.5 * voice(sec, tau=0.05)))
    return air_to(x, rng, 0.025, 0.015)


def land(rng, body_share):
    """찰팍: lane_c 몸통 '착'(420→600Hz, 60ms) + CC0 splash_10과 물보라로 만든 '팍'(0.6~2.5kHz)."""
    sec = 0.20
    n = int(sec * SR)
    water = recording("splash_10", 600, 2500)[:n]
    water = water * np.exp(-np.arange(len(water)) / SR / 0.08)
    wet = norm(mix(sec, (0, water), (0, 0.6 * spray(rng, sec, 600, 2500, 0.05, 60))))
    x = balance(sec, (0, short(voice(0.06, 420, 600, tau=0.02), 0.06), body_share), (0.006, wet, 1 - body_share))
    return air_to(x, rng, 0.03, 0.02)


def land_a(rng):
    """찰팍, 몸통 위주 (에너지 70:30)."""
    return land(rng, 0.7)


def land_b(rng):
    """찰팍, 반반 (에너지 50:50)."""
    return land(rng, 0.5)


def land_c(rng):
    """찰팍, 물보라 위주 (에너지 15:85)."""
    return land(rng, 0.15)


def chul(rng):
    """철: lane_c 몸통을 낮고 두껍게(210→320Hz) + 150~500Hz 노이즈, 80ms 안에 끝."""
    thick = voice(0.08, 210, 320, tau=0.035, body=1.0) + 0.5 * voice(0.08, 150, 230, tau=0.03, glass=0.0)
    return short(thick + 0.5 * v2.air(rng, 0.08, 150, 500, 0.03), 0.08)


def lane_thick(sec):
    """lane_c 몸통을 그대로 길게. 200~400Hz를 늘리지 않고 중심을 아래로 끌어 준다."""
    return voice(sec, tau=0.09, body=1.0, glass=0.0)


def seok(rng, sec, low, high, tau, flutter):
    """썩: 넓게 터지는 물. 물소리처럼 위로 갈수록 작아지게 기울인다."""
    return v2.lowpass(spray(rng, sec, low, high, tau, flutter), 1000.0, 1)


def crash_a(rng):
    """철썩: 몸통 + 넓게 터지는 물 + 물방울 꼬리. 유리 팅 없음."""
    sec = 0.66
    x = balance(sec, (0, chul(rng), 0.25), (0, lane_thick(sec), 0.25), (0.012, seok(rng, sec, 500, 2500, 0.13, 38), 0.50))
    tail = droplets(rng, sec, 0.2, 0.6, 9, 550, 1150, 0.28) * np.max(np.abs(x)) * 0.5
    return air_to(x + tail, rng, 0.02, 0.02)


def crash_b(rng):
    """철-써억: 물이 두 번 터져 더 넓다 + 아주 작은 유리 팅(E6) + 물방울 꼬리."""
    sec = 0.76
    x = balance(sec, (0, chul(rng), 0.25), (0, lane_thick(sec), 0.20), (0.012, seok(rng, sec, 500, 2500, 0.10, 34), 0.33),
                (0.085, seok(rng, sec, 450, 2200, 0.16, 44), 0.22))
    tail = (droplets(rng, sec, 0.3, 0.7, 10, 550, 1150, 0.22) + mix(sec, (0, 0.035 * v2.bell(0.5, [(E6, 1.0, 0.12)])))) * np.max(np.abs(x)) * 0.5
    return air_to(x + tail, rng, 0.02, 0.02)


def crash_c(rng):
    """CC0 splash_02를 0.68배속으로 낮춘 물소리 + lane_c 몸통."""
    sec = 0.72
    n = int(sec * SR)
    water = recording("splash_02", 450, 2200, 0.68)[:n]
    water = water * (1 - np.arange(len(water)) / n) ** 0.8
    x = balance(sec, (0, chul(rng), 0.25), (0, lane_thick(sec), 0.22), (0.006, water, 0.53))
    return air_to(x, rng, 0.02, 0.02)


MAKERS = {"jump_a": jump_a, "jump_b": jump_b, "jump_c": jump_c, "slide_a": slide_a, "slide_b": slide_b, "slide_c": slide_c,
          "land_a": land_a, "land_b": land_b, "land_c": land_c, "crash_a": crash_a, "crash_b": crash_b, "crash_c": crash_c}
SOURCE_NOTE = {"slide_c": "CC0 녹음", "crash_c": "CC0 녹음", "land_a": "합성+CC0", "land_b": "합성+CC0", "land_c": "합성+CC0"}


def level_to_target(x, target_a):
    """A 가중 평균 크기를 맞춘다. 피크는 부드럽게 눌러 -1dBFS 아래로."""
    for _ in range(8):
        x = v2.soft_limit(x * 10 ** ((target_a - v2.a_weighted_db(x)) / 20))
    return x


# ---------- 측정 ----------

def spike_db(x):
    """2~5kHz 1/6옥타브 대역 중 양옆 대역 평균보다 가장 많이 튀는 양(dB)."""
    centers = 1000 * 2 ** (np.arange(5, 15) / 6)  # 1.78~5.04kHz. 2~5kHz 양옆까지 포함
    edge = 2 ** (1 / 12)
    db = np.array([10 * np.log10(v2.band_energy(x, c / edge, c * edge) + 1e-12) for c in centers])
    return float(np.max(db[1:-1] - (db[:-2] + db[2:]) / 2))


def late_mud(x):
    """80ms 뒤에 남은 200~400Hz 에너지(전체 대비 %). 자른 경계의 번짐을 막으려 5ms 페이드를 준다."""
    tail = x[int(0.08 * SR):].copy()
    fade = int(0.005 * SR)
    tail[:fade] *= np.linspace(0, 1, fade)
    return float(v2.band_energy(tail, 200, 400) / v2.band_energy(x, 0, SR) * 100)


def strongest_tonal(x):
    peaks = v2.prominent_peaks(x)
    return max(peaks, key=lambda p: p[1])[0] if peaks else None


def describe(x, reference):
    m = v2.measure(x)
    m["ratio"] = m["centroid"] / reference["centroid"]
    m["a_diff"] = m["a"] - reference["a"]
    return m


def check_sound(name, x, reference):
    kind = name.split("_")[0]
    m = describe(x, reference)
    out = []

    def add(label, ok, value):
        out.append((label, bool(ok), value))

    below = v2.share(x, 0, v2.CHECK_BELOW_HZ[kind]) * 100
    add(f"{v2.CHECK_BELOW_HZ[kind]:.0f}Hz 아래 ≤1%", below <= 1, f"{below:.2f}%")
    low, high = RATIO_RANGE
    top = JUMP_MAX_HZ if kind == "jump" else high * reference["centroid"]
    add(f"중심 {low * reference['centroid']:.0f}~{top:.0f}Hz", low * reference["centroid"] <= m["centroid"] <= top, f"{m['centroid']:.0f}Hz ({m['ratio']:.2f}배)")
    add("4kHz 위 1~5%", HIGH_RANGE[0] <= m["hi"] <= HIGH_RANGE[1], f"{m['hi']:.1f}%")
    over = v2.share(x, 8000) * 100
    add("8kHz 위 ≤0.1% (6kHz 로우패스)", over <= 0.1, f"{over:.3f}%")
    spike = spike_db(x)
    add("2~5kHz 봉우리 ≤6dB", spike <= MAX_SPIKE_DB, f"{spike:.1f}dB")
    tonal = strongest_tonal(x)
    add("가장 큰 배음 ≤1.2kHz", tonal is None or tonal <= MAX_TONAL_HZ, "음 없음" if tonal is None else f"{tonal:.0f}Hz")
    add("200~400Hz ≤25%", m["mud"] <= MAX_MUD, f"{m['mud']:.1f}%")
    late = late_mud(x)
    add("200~400Hz 80ms 안에 끝남 (뒤 ≤1%)", late <= MAX_MUD_LATE, f"{late:.2f}%")
    add("피크 ≤-1dBFS", m["peak"] <= -1, f"{m['peak']:.1f}dBFS")
    low, high = A_RANGE.get(kind, (-2.0, 2.0))
    add(f"A 가중 lane_c 대비 {low:+.0f}~{high:+.0f}dB", low <= m["a_diff"] <= high, f"{m['a_diff']:+.1f}dB")
    add("사각파·톱니파 선 없음", not v2.has_square_or_saw_lines(v2.prominent_peaks(x)), "없음")
    start = v2.onset_ms(x)
    add("첫 소리 ≤5ms", start <= 5, f"{start:.1f}ms")
    low, high = LENGTH_RANGE[kind]
    eff = v2.effective_sec(x)
    add(f"길이 {low}~{high}초", low <= eff and m["len"] <= high, f"파일 {m['len']:.2f}초, 실효 {eff:.2f}초")
    if kind == "jump":
        end_hz = B4 if name == "jump_b" else E5
        begin, end = v2.track_pitch(x, end_hz * 0.62, end_hz * 1.2)
        rise = 12 * np.log2(end / begin)
        note, cents = v2.note_error(end)
        add("올라가는 폭 3~5반음", 3 <= rise <= 5.05, f"{rise:.1f}반음")
        want = "B" if name == "jump_b" else "E"
        add(f"끝음 {want} (±30센트)", note == want and abs(cents) <= 30, f"{note}{cents:+.0f}c ({end:.0f}Hz)")
    return out, m


def self_test():
    """재료가 진짜 lane_c와 같은지, 새 측정 함수가 맞는지 정답을 아는 신호로 확인한다."""
    lane = v2.load_wav(FIRST / "sfx" / "lane_c.wav")
    rebuilt = finish(voice(0.1))
    assert len(rebuilt) == len(lane) and np.max(np.abs(rebuilt - lane)) < 2 / 32768, "voice()가 lane_c와 다름"
    rng = np.random.default_rng(1)
    t = times(0.5)
    smooth = v2.lowpass(rng.standard_normal(len(t)), 6000.0)
    spiked = smooth + 0.6 * np.sin(2 * np.pi * 3000 * t)
    assert spike_db(smooth) < 3 and spike_db(spiked) > MAX_SPIKE_DB
    assert late_mud(np.sin(2 * np.pi * 300 * t)) > 50
    assert late_mud(mix(0.5, (0, short(np.sin(2 * np.pi * 300 * t), 0.06)))) < 1
    assert abs(v2.share(air_to(np.sin(2 * np.pi * 500 * t), rng, 0.03, 0.1), 4000) - 0.03) < 0.005


# ---------- 결과물 ----------

def write_spectrograms(sounds):
    """2차 그림과 같은 형식. 칸마다 4kHz 파선에 1.5kHz 점선을 더한다."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LinearSegmentedColormap
    plt.rcParams["font.family"] = ["AppleGothic", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False
    cmap = LinearSegmentedColormap.from_list("mint", ["#ffffff", "#bfe9e6", "#3aa6a6", "#0b4f5c", "#04222b"])
    fig, axes = plt.subplots(5, 3, figsize=(12, 13.5), facecolor="white", layout="constrained")
    xlim = {"lane": 0.35, "jump": 0.35, "slide": 0.5, "land": 0.3, "crash": 0.95}
    image = None

    def draw(ax, x, title, limit):
        nonlocal image
        spec, freq, tm = plt.mlab.specgram(x, NFFT=512, Fs=SR, noverlap=448, window=np.hanning(512), mode="magnitude")[:3]
        image = ax.pcolormesh(tm, freq, 20 * np.log10(2 * spec + 1e-9), cmap=cmap, vmin=-70, vmax=-15, shading="auto", rasterized=True)
        ax.set_yscale("log")
        ax.set_ylim(100, 20000)
        ax.set_xlim(0, limit)
        ax.set_yticks([100, 400, 1000, 1500, 4000, 10000], ["100", "400", "1k", "1.5k", "4k", "10k"])
        ax.minorticks_off()
        ax.axhline(4000, color="#b4532a", linewidth=0.8, linestyle="--")
        ax.axhline(1500, color="#b4532a", linewidth=0.8, linestyle=":")
        ax.set_title(title, fontsize=11, loc="left", color="#222222")
        ax.tick_params(labelsize=8, colors="#555555")
        ax.set_xlabel("시간(초)", fontsize=8, color="#555555")
        ax.set_ylabel("Hz", fontsize=8, color="#555555")

    draw(axes[0, 0], v2.load_wav(FIRST / "sfx" / "lane_c.wav"), "레인 이동 lane_c (확정, 기준)", xlim["lane"])
    axes[0, 1].axis("off")
    axes[0, 2].axis("off")
    axes[0, 1].text(0, 0.65, "아래는 3차 후보 12개. 파선은 4kHz, 점선은 1.5kHz.\n같은 줄은 시간 축이 같다. 세로축은 로그.\n색이 진할수록 크다 (모든 칸이 같은 눈금).",
                    fontsize=11, va="center", color="#333333")
    for row, kind in enumerate(KINDS, start=1):
        for col, letter in enumerate("abc"):
            name = f"{kind}_{letter}"
            draw(axes[row, col], sounds[name], f"{KOREAN[kind]} {letter.upper()} ({SOURCE_NOTE.get(name, '합성')})", xlim[kind])
    fig.colorbar(image, ax=axes, label="크기(dBFS)", location="right", shrink=0.35, aspect=25)
    fig.savefig(HERE / "spectrograms.png", dpi=110)
    plt.close(fig)


def write_audio_data():
    """더블클릭(file://)으로 열어도 들리게 소리를 base64로 담는다."""
    data = {name: HERE / f"{name}.wav" for name in NAMES}
    data["v2_jump_a"] = SECOND / "jump_a.wav"
    data["v2_land_c"] = SECOND / "land_c.wav"
    data["lane_c"] = FIRST / "sfx" / "lane_c.wav"
    data["bgm_3"] = FIRST / "bgm" / "bgm_3.flac"
    encoded = {key: base64.b64encode(path.read_bytes()).decode() for key, path in data.items()}
    (HERE / "audio_data.js").write_text("window.SOUND_DATA=" + json.dumps(encoded) + ";\n", encoding="utf-8")


def write_report(results, reference):
    lane = v2.load_wav(FIRST / "sfx" / "lane_c.wav")
    tonal = np.fft.rfftfreq(len(lane), 1 / SR)[np.argmax(np.abs(np.fft.rfft(lane)))]  # 0.1초로 짧아 봉우리 검사 대신 스펙트럼 최대점을 쓴다
    lines = ["# 소리 후보 3차 측정 보고", "",
             "`python3 make_sounds_v3.py`가 만든 파일이다. 숫자는 저장된 wav를 다시 읽어서 쟀다.", "",
             "## lane_c를 만든 재료", "",
             "`../sounds/make_sounds.py` 79번 줄을 분석했다. 스크립트의 `voice()`가 같은 소리를 다시 만들고, 실행할 때마다 저장된 lane_c.wav와 표본 단위로 비교한다(차이 2/32768 미만).", "",
             "| 항목 | 값 |", "|---|---|",
             "| 파형 | 사인파만 (사각파·톱니파 없음) |",
             "| 배음 | 몸통 1개 + 유리빛 층 1개. 정수배 배음은 없다 |",
             "| 몸통 음 높이 | 420→640Hz, 0.1초 동안 곡선 u^0.7로 상승 (7.3반음) |",
             "| 몸통 엔벨로프 | 지수 감쇠, 시간 상수 28ms |",
             "| 유리빛 층 | 1400→1500Hz 직선 상승, 크기 0.1 (몸통보다 -20dB), 시간 상수 20ms |",
             "| 필터 | FFT 대역 제한: 30Hz 위, 6kHz까지 그대로, 7.8kHz에서 0 |",
             "| 앞뒤 | 페이드 인 2ms, 페이드 아웃 12ms, 피크 0.42 |",
             "| 울림 | **없음** |",
             f"| 측정 | 중심 {reference['centroid']:.0f}Hz, 4kHz 위 {reference['hi']:.2f}%, A 가중 {reference['a']:.1f}dB, 피크 {reference['peak']:.1f}dBFS, 길이 {reference['len']:.2f}초, 스펙트럼 최대점 {tonal:.0f}Hz |", "",
             "## 같은 재료로 만든 방법", "",
             "12개 모두 `voice()`로 몸통과 유리빛 층을 만들고 `finish()`(lane_c와 같은 함수)로 마감했다. CC0 녹음(C 후보와 착지 물보라)도 같은 `finish()`를 거치고 lane_c 몸통과 섞인다. 울림은 lane_c에 없으므로 12개 모두 넣지 않았다(2차 기준 6 '울림 15% 이하, 꼬리 0.4초 이하'도 저절로 만족).", "",
             "소리마다 바꾼 것은 길이, 음 높이 움직임, 노이즈 양, 몸통 크기다. 4kHz 위 1~5%는 lane_c(0%)보다 높게 정해진 기준이라 2.5~6kHz 물기 노이즈(`air_to`)로 맞췄다. 이 층은 lane_c에 없는 유일한 재료다.", "",
             "## 지시 해석", "",
             "- 두 지시가 겹치는 곳은 추가 지시를 따랐다: 중심 330~950Hz(점프 1.2kHz), 4kHz 위 1~5%, 배음 1.2kHz 이하.",
             "- '5반음 낮춤(끝음 B4)'은 2차 끝음 E6에서 재면 B5가 되어 맞지 않는다. B4가 되는 'A(E5)에서 5반음 더 낮춤'으로 해석했다.",
             "- 충돌의 '유리 팅은 1개만'은 lane_c에서 온 유리빛 층(크기 0.1)과 별개로 봤다. 유리빛 층은 전부에 있고, 따로 더한 E6 팅은 crash_b에만 있다. 이 팅(1319Hz)은 배음 기준 1.2kHz를 넘지만 가장 큰 배음이 아니라 기준 안이다.",
             "- 2차 기준 5(마단조)는 유지 목록에 없고, 유리빛 층(1400~1500Hz)이 F~F#이라 '같은 재료'와 맞지 않아 검사에서 뺐다. 점프 끝음(E, B)은 지켰다.",
             "- 착지는 2차 land_c의 '몸통 + 터짐' 구조를 이었지만 재료는 바꿨다. 몸통은 Kenney 녹음 대신 lane_c 재료, 터짐은 scratch_001 대신 물 녹음 splash_10이다. '핑'은 lane_c의 유리빛 층만 남겼다.",
             "- 2차 기준 2(200~400Hz EQ)는 3차의 '탁함 기준 완화'로 바뀌어 EQ를 쓰지 않았다.", "",
             "## 수치표", "",
             "- **중심**: 파일 전체 파워 스펙트럼의 무게 중심. **lane_c 대비(배)**: 중심 ÷ lane_c 중심.",
             "- **A 가중**: 귀의 민감도를 곱해 20ms 조각 중 가장 큰 조각보다 30dB 안쪽만 평균한 크기.", ""]
    for kind in KINDS:
        lines += [f"### {KOREAN[kind]}", "",
                  "| 소리 | 중심(Hz) | lane_c 대비 중심(배) | 4kHz 위(%) | 피크(dBFS) | A 가중 lane_c 대비(dB) | 200~400Hz(%) | 길이(초) |",
                  "|---|---:|---:|---:|---:|---:|---:|---:|"]
        rows = [(f"1차 {kind}_{c}", describe(v2.load_wav(FIRST / "sfx" / f"{kind}_{c}.wav"), reference)) for c in "abc"]
        rows += [(f"2차 {kind}_{c}", describe(v2.load_wav(SECOND / f"{kind}_{c}.wav"), reference)) for c in "abc"]
        rows += [(f"**3차 {kind}_{c}**", results[f"{kind}_{c}"]["m"]) for c in "abc"]
        for label, m in rows:
            lines.append(f"| {label} | {m['centroid']:.0f} | {m['ratio']:.2f} | {m['hi']:.1f} | {m['peak']:.1f} | {m['a_diff']:+.1f} | {m['mud']:.1f} | {m['len']:.2f} |")
        lines.append("")
    land_body = [results[f"land_{c}"]["body"] for c in "abc"]
    lines += ["## 착지 몸통과 물보라 비율", "",
              f"몸통:물보라 에너지를 A 70:30 / B 50:50 / C 15:85로 섞었다(`balance()`). 물보라도 600Hz부터 시작하므로 완성된 소리의 800Hz 아래 비율은 A {land_body[0]:.0f}% / B {land_body[1]:.0f}% / C {land_body[2]:.0f}%다.", "",
              "## 새 기준 검사", ""]
    failed_total = 0
    for name in NAMES:
        failed = [c for c in results[name]["checks"] if not c[1]]
        failed_total += len(failed)
        lines += [f"### {name}: {'모두 통과' if not failed else '못 맞춘 항목 ' + str(len(failed)) + '개'}", "", "| 항목 | 결과 | 값 |", "|---|---|---|"]
        lines += [f"| {label} | {'통과' if ok else '**실패**'} | {value} |" for label, ok, value in results[name]["checks"]]
        lines.append("")
    lines += [f"못 맞춘 항목 합계: {failed_total}개", "", "## 검사 방법의 한계", "",
              "- 숫자는 기준을 맞췄는지만 보여 준다. 찰팍·철썩처럼 들리는지는 사람 귀로 확인해야 한다.",
              "- '2~5kHz 봉우리'는 1/6옥타브 대역을 양옆 평균과 비교한다. 이보다 좁은 봉우리는 대역 평균에 묻힐 수 있다.",
              "- '80ms 안에 끝남'은 80ms 뒤에 남은 200~400Hz 에너지가 전체의 1% 이하인지로 쟀다. 숫자 1%는 이번에 정한 값이다.",
              "- 점프의 '올라가는 폭'은 창 12ms로 잰 값이라 설계값 5반음보다 조금 작게 나온다.",
              "- '가장 큰 배음'은 최댓값 -20dB 안쪽이고 주변보다 15dB 이상 높은 봉우리 중 가장 큰 것이다. 노이즈 위주인 소리는 음 없음으로 나올 수 있다.", ""]
    (HERE / "report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    self_test()
    reference = v2.measure(v2.load_wav(FIRST / "sfx" / "lane_c.wav"))
    reference["ratio"], reference["a_diff"] = 1.0, 0.0
    results, sounds = {}, {}
    for index, name in enumerate(NAMES):
        rng = np.random.default_rng(20261109 + index)
        kind = name.split("_")[0]
        x = level_to_target(finish(MAKERS[name](rng)), reference["a"] + A_OFFSET.get(kind, 0.0))
        v2.save_wav(HERE / f"{name}.wav", x)
        saved = v2.load_wav(HERE / f"{name}.wav")
        sounds[name] = saved
        checks, m = check_sound(name, saved, reference)
        results[name] = {"checks": checks, "m": m, "body": v2.share(saved, 0, 800) * 100}
    write_spectrograms(sounds)
    write_audio_data()
    write_report(results, reference)
    failures = 0
    for name in NAMES:
        m = results[name]["m"]
        print(f"{name}: 중심 {m['centroid']:.0f} ({m['ratio']:.2f}배) 4k위 {m['hi']:.1f}% 피크 {m['peak']:.1f} A차 {m['a_diff']:+.1f} 200~400 {m['mud']:.1f}% 800아래 {results[name]['body']:.0f}% 길이 {m['len']:.2f}")
        for label, ok, value in results[name]["checks"]:
            if not ok:
                failures += 1
                print(f"  실패 {label}: {value}")
    print(f"못 맞춘 항목: {failures}개")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
