#!/usr/bin/env python3
"""소리 후보 2차: 점프·슬라이드·착지·충돌 각 3개를 만들고 기준 1~8을 숫자로 검사한다.

사용: python3 make_sounds_v2.py   (numpy, scipy, matplotlib, ffmpeg 필요)
결과: *.wav, audio_data.js, report.md, spectrograms.png. 기준을 못 맞춘 소리가 있으면 종료 코드 1.
A·B는 사인파와 걸러낸 노이즈로 직접 합성, C는 sources/의 Kenney CC0 소리를 가공했다.
시드가 고정돼 있어 다시 실행해도 같은 소리가 나온다.
"""
import base64
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, freqz, lfilter, resample_poly, sosfilt

SR = 44100
HERE = Path(__file__).resolve().parent
FIRST = HERE.parent / "sounds"
KINDS = ["jump", "slide", "land", "crash"]
KOREAN = {"jump": "점프", "slide": "슬라이드", "land": "착지", "crash": "충돌"}
NAMES = [f"{k}_{c}" for k in KINDS for c in "abc"]

# 마단조 음 이름과, 합성에 쓰는 음의 주파수
PITCH_CLASSES = {"E", "G", "A", "B", "D"}
NOTE = {"G4": 392.00, "A4": 440.00, "B4": 493.88, "G5": 783.99, "B5": 987.77, "E6": 1318.51, "B6": 1975.53,
        "D7": 2349.32, "E7": 2637.02, "G7": 3135.96, "A7": 3520.00, "B7": 3951.07, "D8": 4698.64, "E8": 5274.04}

# 기준 값
MAX_WET, MAX_REVERB_SEC = 0.15, 0.40
LENGTH_RANGE = {"jump": (0.23, 0.33), "slide": (0.30, 0.45), "land": (0.15, 0.25), "crash": (0.60, 0.90)}
HP_HZ = {"jump": 140.0, "slide": 150.0, "land": 140.0, "crash": 90.0}
CHECK_BELOW_HZ = {"jump": 120.0, "slide": 120.0, "land": 120.0, "crash": 90.0}
GLIDE_SEC = 0.08


# ---------- 재료 ----------

def times(sec):
    return np.arange(int(sec * SR)) / SR


def band(x, low, high, order=2):
    return sosfilt(butter(order, [low, high], "bandpass", fs=SR, output="sos"), x)


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "lowpass", fs=SR, output="sos"), x)


def highpass(x, hz, order=6):
    return sosfilt(butter(order, hz, "highpass", fs=SR, output="sos"), x)


def glide_path(f0, f1, sec):
    """앞 80ms 동안 f0→f1로 살짝 올라간 뒤 머문다. 반음 수는 호출하는 쪽에서 3~5로 정한다."""
    t = times(sec)
    u = np.minimum(t / GLIDE_SEC, 1.0)
    return f0 * (f1 / f0) ** (1 - (1 - u) ** 2)


def partials(path, parts):
    """사인 배음들의 합. parts = [(배수, 크기, 감쇠 시간)]. 사각파·톱니파는 쓰지 않는다."""
    t = np.arange(len(path)) / SR
    phase = 2 * np.pi * np.cumsum(path) / SR
    return sum(a * np.sin(r * phase) * np.exp(-t / tau) for r, a, tau in parts)


def bell(sec, notes):
    """고정 음 유리 종. notes = [(주파수, 크기, 감쇠 시간)]."""
    t = times(sec)
    return sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / tau) for f, a, tau in notes)


def resonant_sweep(x, hz, q):
    """공명 필터(상태 변수 필터)를 시간에 따라 움직인다. 물방울 블룹과 젖은 쓸림에 쓴다."""
    low = bp = 0.0
    out = np.zeros(len(x))
    g = 2 * np.sin(np.pi * hz / SR)
    for i, sample in enumerate(x):
        low += g[i] * bp
        high = sample - low - bp / q
        bp += g[i] * high
        out[i] = bp
    return out


def bloop(rng, f0, f1, sec, q=26.0):
    """짧은 잡음을 공명 필터에 넣어 '블룹'을 만든다. 스윕은 80ms 동안 f0→f1(한 옥타브 미만)."""
    hit = np.zeros(int(sec * SR))
    n = int(0.003 * SR)
    hit[:n] = rng.standard_normal(n) * np.hanning(n)
    out = resonant_sweep(hit, glide_path(f0, f1, sec), q)
    return out / np.max(np.abs(out))


def air(rng, sec, low, high, tau):
    """공기 터짐·젖은 터짐: 대역 노이즈가 지수로 사라진다."""
    return band(rng.standard_normal(int(sec * SR)), low, high) * np.exp(-times(sec) / tau)


def wet_flutter(rng, sec, rate, depth):
    """느린 무작위 떨림. 쓸림 소리를 젖고 울퉁불퉁하게 만든다."""
    n = int(sec * rate) + 3
    return 1 - depth + depth * np.interp(times(sec), np.arange(n) / rate, rng.random(n))


def mix(sec, *parts):
    out = np.zeros(int(sec * SR))
    for start, sig in parts:
        i = int(start * SR)
        m = min(len(sig), len(out) - i)
        out[i:i + m] += sig[:m]
    return out


def source(name):
    path = HERE / "sources" / f"{name}.ogg"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(float)


def warp(x, rate):
    """재생 속도를 시간에 따라 바꾼다. rate는 출력 표본마다의 속도 배열."""
    position = np.concatenate([[0.0], np.cumsum(rate[:-1])])
    return np.interp(position, np.arange(len(x)), x, right=0.0)


# ---------- 마감 (기준 1·2·4·6) ----------

def peaking(hz, q, db):
    """RBJ 피킹 필터 계수."""
    a = 10 ** (db / 40)
    w = 2 * np.pi * hz / SR
    alpha = np.sin(w) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w), 1 - alpha * a]
    d = [1 + alpha / a, -2 * np.cos(w), 1 - alpha / a]
    return np.array(b) / d[0], np.array(d) / d[0]


def reverb(x, rng, wet, tail):
    """짧은 울림: 고음 쪽 노이즈 잔향을 섞는다 (섞는 비율 15% 이하, 꼬리 0.4초 이하)."""
    assert wet <= MAX_WET and tail <= MAX_REVERB_SEC
    ir = highpass(rng.standard_normal(int(tail * SR)), 600.0, 2) * np.exp(-times(tail) / (tail / 6.9))
    ir /= np.sqrt(np.sum(ir ** 2))
    return (1 - wet) * x + wet * np.convolve(x, ir)[:len(x)]


def gated_rms_db(x):
    """평균 크기: 20ms 조각 중 가장 큰 조각보다 30dB 안쪽 조각만 평균 (꼬리 길이에 덜 흔들리게)."""
    size = int(0.02 * SR)
    power = np.array([np.mean(x[i:i + size] ** 2) for i in range(0, max(1, len(x) - size), size // 2)])
    return 10 * np.log10(np.mean(power[power >= power.max() / 1000]))


def band_energy(x, low, high):
    power = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.sum(power[(f >= low) & (f < high)])


def soft_limit(x, ceiling_db=-1.4):
    """공격 구간의 튀는 표본만 둥글게 눌러 피크 -1dBFS 아래로 맞춘다. 무릎 아래는 그대로 둔다."""
    ceiling = 10 ** (ceiling_db / 20)
    knee = 0.8 * ceiling
    over = np.abs(x) > knee
    out = x.copy()
    out[over] = np.sign(x[over]) * (knee + (ceiling - knee) * np.tanh((np.abs(x[over]) - knee) / (ceiling - knee)))
    return out


def master(x, kind, rng, sec, wet, tail, offset_db=0.0):
    """하이패스 → 울림 → 탁함 구간 EQ → 길이 맞춤 → 크기 맞춤. EQ 전후 200~400Hz 변화도 돌려준다."""
    out = mix(sec, (0.0, x))
    out = reverb(highpass(out, HP_HZ[kind]), rng, wet, tail)
    before = out
    out = lfilter(*peaking(283.0, 1.41, -5.5), out)
    eq_db = 10 * np.log10(band_energy(out, 200, 400) / band_energy(before, 200, 400))
    fade_in, fade_out = int(0.001 * SR), int(0.3 * len(out))  # 끝이 뚝 끊기지 않게 뒤 30%를 부드럽게 줄인다
    out[:fade_in] *= np.linspace(0, 1, fade_in)
    out[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    target = gated_rms_db(load_wav(FIRST / "sfx" / "lane_c.wav")) + offset_db
    for _ in range(6):  # 누르면 평균이 조금 줄어드니 되풀이해서 맞춘다
        out = soft_limit(out * 10 ** ((target - gated_rms_db(out)) / 20))
    return out, eq_db


# ---------- 후보 ----------

def jump_a(rng):
    """맑은 유리 퐁: B5→E6 (5반음)."""
    sec = 0.27
    path = glide_path(NOTE["B5"], NOTE["E6"], sec)
    tone = partials(path, [(1, 1.0, 0.055), (1.5, 0.30, 0.040), (2, 0.34, 0.030), (4, 0.62, 0.024)])
    return mix(sec, (0, tone), (0, 0.8 * bloop(rng, NOTE["B5"], NOTE["E6"], sec)),
               (0, 1.1 * air(rng, sec, 4200, 11000, 0.003))), sec, 0.08, 0.14


def jump_b(rng):
    """둥근 물방울 퐁: G5→B5 (4반음), 블룹이 앞에 나서고 유리 배음은 뒤에서 살짝."""
    sec = 0.30
    path = glide_path(NOTE["G5"], NOTE["B5"], sec)
    tone = partials(path, [(1, 0.55, 0.070), (2, 0.20, 0.040), (NOTE["E7"] / NOTE["B5"], 0.22, 0.032),
                           (NOTE["E8"] / NOTE["B5"], 0.46, 0.022)])
    return mix(sec, (0, tone), (0, 1.1 * bloop(rng, NOTE["G5"], NOTE["B5"], sec, 34.0)),
               (0, 1.0 * air(rng, sec, 4500, 12000, 0.003))), sec, 0.10, 0.16


def jump_c(rng):
    """CC0: drop_004(물방울) + pluck_002(유리 튕김)를 B5→E6로 끌어올린 뒤 공기 터짐을 얹는다."""
    sec = 0.28
    shape = glide_path(NOTE["B5"], NOTE["E6"], sec) / NOTE["E6"]
    drop = warp(source("drop_004"), shape * NOTE["E6"] / 1226.0)  # 원본 봉우리 613Hz를 E5로 (E6 유리 튕김의 한 옥타브 아래)
    pluck = warp(source("pluck_002"), shape * NOTE["E6"] / 1250.0)
    hold = partials(shape * NOTE["E6"], [(1, 0.35, 0.075), (4, 0.38, 0.022)])  # 원본 꼬리가 짧아 E6를 조금 늘려 준다
    return mix(sec, (0, 0.9 * drop), (0, 0.65 * pluck), (0, hold), (0, 0.9 * air(rng, sec, 4500, 12000, 0.003))), sec, 0.08, 0.14


def slide_a(rng):
    """젖은 쓸림: 5kHz→1.5kHz로 천천히 내려가는 공명 노이즈 + 200Hz 위의 짧은 몸통."""
    sec = 0.40
    n = int(sec * SR)
    hz = 4400 * (1500 / 4400) ** (np.arange(n) / n)
    wet = resonant_sweep(rng.standard_normal(n), hz, 5.0) * wet_flutter(rng, sec, 32, 0.55)
    env = np.minimum(times(sec) / 0.002, 1) * (1 - np.arange(n) / n) ** 0.7
    body = band(rng.standard_normal(n), 320, 700) * np.exp(-times(sec) / 0.028)
    wet = lowpass(wet, 5200.0)
    return mix(sec, (0, wet * env), (0, 0.35 * body)), sec, 0.08, 0.15


def slide_b(rng):
    """슈르륵 알갱이: 아주 짧은 물방울 수백 개의 높이가 D8에서 D7 쪽으로 내려간다 (마단조 음만 사용)."""
    sec = 0.42
    out = np.zeros(int(sec * SR))
    ladder = [NOTE[k] for k in ("D7", "E7", "G7", "A7", "B7", "D8")]
    for _ in range(170):
        start = rng.random() ** 1.15 * (sec - 0.03)
        progress = start / sec
        idx = np.clip(len(ladder) - 1 - progress * len(ladder) + rng.normal(0, 1.1), 0, len(ladder) - 1)
        length = int(0.014 * SR)
        t = np.arange(length) / SR
        grain = np.sin(2 * np.pi * ladder[int(idx)] * t) * np.exp(-t / 0.0035) * (1 - progress) ** 1.1
        i = int(start * SR)
        out[i:i + length] += grain * rng.uniform(0.4, 1.0)
    breath = band(rng.standard_normal(len(out)), 1500, 5000) * (1 - np.arange(len(out)) / len(out)) ** 1.6
    body = band(rng.standard_normal(len(out)), 300, 650) * np.exp(-times(sec) / 0.022)
    first = 0.9 * air(rng, sec, 1500, 6000, 0.012)
    return mix(sec, (0, out), (0, 0.8 * breath), (0, 0.8 * body), (0, first)), sec, 0.06, 0.12


def slide_c(rng):
    """CC0: footstep_snow_000을 40ms 알갱이로 잘라 빈틈없이 흩뿌린 뒤 공명 필터로 4.4kHz→1.5kHz로 끌어내린다."""
    sec = 0.42
    n = int(sec * SR)
    snow = highpass(source("footstep_snow_000"), 1200.0, 4)
    size = int(0.04 * SR)
    window = np.hanning(size)
    cloud = np.zeros(n + size)
    # 일정 간격이면 빗살 모양 음이 생기므로 간격을 흔든다
    for start in np.cumsum(rng.integers(int(0.003 * SR), int(0.009 * SR), int(sec / 0.003)))[:-1]:
        if start >= n:
            break
        at = rng.integers(0, len(snow) - size)
        grain = snow[at:at + size]
        cloud[start:start + size] += window * grain / (np.max(np.abs(grain)) + 1e-6) * rng.uniform(0.5, 1.0)
    hz = 4400 * (1500 / 4400) ** (np.arange(n) / n)
    wet = lowpass(resonant_sweep(cloud[:n], hz, 5.0), 5200.0) * wet_flutter(rng, sec, 30, 0.5)
    env = np.minimum(times(sec) / 0.002, 1) * (1 - np.arange(n) / n) ** 0.7
    return mix(sec, (0, wet * env), (0, 0.6 * air(rng, sec, 1500, 5000, 0.012))), sec, 0.08, 0.15


def land_a(rng):
    """톡: 2~4kHz 터짐 + B4 몸통 60ms 이내 + D7 물방울 핑."""
    sec = 0.19
    t = times(0.06)
    body = np.sin(2 * np.pi * NOTE["B4"] * t) * np.exp(-t / 0.013) * np.hanning(len(t) * 2)[len(t):] ** 0.3
    ping = bell(0.17, [(NOTE["D7"], 1.0, 0.026)])
    return mix(sec, (0, 1.5 * air(rng, sec, 2000, 4000, 0.005)), (0, 1.2 * air(rng, sec, 4200, 10000, 0.004)),
               (0, 0.45 * body), (0.016, 0.55 * ping)), sec, 0.06, 0.10


def land_b(rng):
    """찰팍: 두 번 튀는 젖은 터짐 + A4 몸통 + E7 물방울 핑."""
    sec = 0.23
    t = times(0.055)
    body = np.sin(2 * np.pi * NOTE["A4"] * t) * np.exp(-t / 0.012) * np.hanning(len(t) * 2)[len(t):] ** 0.3
    ping = bell(0.17, [(NOTE["E7"], 1.0, 0.022)])
    return mix(sec, (0, 1.4 * air(rng, sec, 2000, 4500, 0.006)), (0, 1.0 * air(rng, sec, 4500, 10000, 0.004)),
               (0.022, 1.0 * air(rng, 0.1, 2200, 7000, 0.006)), (0, 0.4 * body), (0.038, 0.55 * ping)), sec, 0.08, 0.12


def land_c(rng):
    """CC0: impactGeneric_light_000(몸통) + scratch_001(터짐) + drop_001(E7로 맞춘 핑)."""
    sec = 0.21
    body = highpass(source("impactGeneric_light_000"), 320.0, 4)[:int(0.06 * SR)]
    body = body * np.hanning(len(body) * 2)[len(body):]
    burst = highpass(source("scratch_001"), 1500.0, 4)[:int(0.10 * SR)]
    burst = burst * np.exp(-np.arange(len(burst)) / SR / 0.018)
    ping = resample_poly(source("drop_001"), 2055, round(NOTE["E7"]))  # 원본 2055Hz 봉우리를 E7로
    ping = ping * np.exp(-np.arange(len(ping)) / SR / 0.060)
    return mix(sec, (0, 0.30 * body), (0, 1.7 * burst), (0.020, 1.0 * ping), (0.020, 0.22 * bell(0.18, [(NOTE["E7"], 1.0, 0.035)]))), sec, 0.12, 0.20


def splash(rng, sec, tau, flutter):
    """젤리 철썩: 넓은 대역 노이즈. 저음을 넣지 않아 탁하지 않게."""
    return (band(rng.standard_normal(int(sec * SR)), 1100, 7000) * np.exp(-times(sec) / tau)
            * wet_flutter(rng, sec, flutter, 0.6))


def crash_a(rng):
    """맑은 팅 + 철썩: 배음 간격이 불규칙한 유리 종(E7·B7·D8·E8)과 짧은 몸통."""
    sec = 0.75
    glass = bell(sec, [(NOTE["E7"], 1.0, 0.15), (NOTE["B7"], 0.8, 0.12), (NOTE["D8"], 0.7, 0.095), (NOTE["E8"], 0.6, 0.07)])
    t = times(0.05)
    body = np.sin(2 * np.pi * 330 * t) * np.exp(-t / 0.012) * np.hanning(len(t) * 2)[len(t):] ** 0.3
    return mix(sec, (0, glass), (0, 1.8 * splash(rng, sec, 0.075, 42)), (0, 0.55 * body)), sec, 0.12, 0.30


def crash_b(rng):
    """넓게 깨지는 유리: 음을 살짝 어긋나게 겹친 종 + 두 번 튀는 철썩."""
    sec = 0.85
    glass = bell(sec, [(NOTE["D7"], 0.9, 0.17), (NOTE["G7"], 1.0, 0.14), (NOTE["G7"] * 1.003, 0.5, 0.11),
                       (NOTE["D8"], 0.75, 0.10), (NOTE["E8"], 0.65, 0.075), (NOTE["E8"] * 1.004, 0.3, 0.06)])
    return mix(sec, (0, glass), (0, 1.6 * splash(rng, sec, 0.07, 36)), (0.055, 0.9 * splash(rng, sec, 0.06, 50)),
               (0, 1.0 * air(rng, sec, 450, 1100, 0.016))), sec, 0.14, 0.34


def crash_c(rng):
    """CC0: impactGlass_light_000(유리 깨짐) + glass_004(E8로 낮춘 울림) + footstep_snow_000(철썩)."""
    sec = 0.85
    hit = highpass(source("impactGlass_light_000"), 500.0, 4)
    ring_e8 = resample_poly(source("glass_004"), 7337, round(NOTE["E8"]))  # 원본 7337Hz 울림을 E8과 B7로 내려 겹친다
    ring_b7 = resample_poly(source("glass_004"), 7337, round(NOTE["B7"]))
    ring = mix(sec, (0, ring_e8), (0, 1.2 * ring_b7)) * np.exp(-times(sec) / 0.42)
    wet = highpass(source("footstep_snow_000"), 900.0, 4) * 1.6
    return mix(sec, (0, hit), (0, 0.9 * ring), (0.01, wet), (0, 0.5 * air(rng, sec, 3000, 9000, 0.02))), sec, 0.12, 0.30


# ---------- 측정 ----------

def load_wav(path):
    with wave.open(str(path)) as f:
        data = np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16)
    return data / 32768.0


def save_wav(path, x):
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def centroid_hz(x):
    power = np.abs(np.fft.rfft(x)) ** 2
    return float(np.sum(np.fft.rfftfreq(len(x), 1 / SR) * power) / np.sum(power))


def share(x, low, high=SR):
    return float(band_energy(x, low, high) / band_energy(x, 0, SR))


def a_weighted_db(x):
    """A 가중치(귀의 민감도)를 곱한 평균 크기. 고음이 많으면 같은 RMS여도 더 크게 들리는 것을 본다."""
    spec = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 1.0)
    ra = 12194 ** 2 * f ** 4 / ((f ** 2 + 20.6 ** 2) * np.sqrt((f ** 2 + 107.7 ** 2) * (f ** 2 + 737.9 ** 2)) * (f ** 2 + 12194 ** 2))
    return gated_rms_db(np.fft.irfft(spec * ra * 10 ** (2.0 / 20), len(x)))


def true_peak_db(x):
    return float(20 * np.log10(np.max(np.abs(resample_poly(x, 4, 1)))))


def onset_ms(x):
    """피크보다 20dB 작은 크기에 처음 닿는 시각."""
    return float(np.argmax(np.abs(x) >= np.max(np.abs(x)) * 0.1) / SR * 1000)


def effective_sec(x):
    """가장 큰 20ms 조각보다 40dB 안쪽인 마지막 시각. 파일 끝이 무음으로 채워졌는지 본다."""
    size = int(0.02 * SR)
    starts = np.arange(0, max(1, len(x) - size), size // 2)
    power = np.array([np.mean(x[i:i + size] ** 2) for i in starts])
    return float((starts[np.nonzero(power >= power.max() * 1e-4)[0][-1]] + size) / SR)


def prominent_peaks(x, floor_db=-20.0, prominence_db=15.0):
    """음으로 들리는 선 스펙트럼을 찾는다: 최대값 -20dB 안쪽이고, 앞뒤 1/3옥타브 중앙값보다 15dB 이상 높은 봉우리."""
    nfft = max(1 << 17, len(x))
    db = 20 * np.log10(np.abs(np.fft.rfft(x * np.hanning(len(x)), nfft)) + 1e-12)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    usable = (f >= 200) & (f <= 12000)
    top = db[usable].max()
    found = []
    for i in np.nonzero(usable)[0]:
        if db[i] < top + floor_db or db[i] < db[i - 1] or db[i] <= db[i + 1]:
            continue
        lo, hi = np.searchsorted(f, [f[i] / 1.26, f[i] * 1.26])
        if db[i] - np.median(db[lo:hi]) >= prominence_db:
            found.append((float(f[i]), float(db[i] - top)))
    return found


def note_error(hz):
    """가장 가까운 음 이름과 어긋남(센트)."""
    midi = 69 + 12 * np.log2(hz / 440.0)
    nearest = round(midi)
    return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][nearest % 12], (midi - nearest) * 100


def track_pitch(x, low, high):
    """12ms 창으로 대역 안 가장 큰 봉우리를 따라가 (시작 음, 80~110ms 음)을 돌려준다."""
    size = int(0.012 * SR)
    window = np.hanning(size)
    f = np.fft.rfftfreq(1 << 15, 1 / SR)
    usable = (f >= low) & (f <= high)
    def peak(at):
        i = int(at * SR)
        return f[usable][np.argmax(np.abs(np.fft.rfft(x[i:i + size] * window, 1 << 15))[usable])]
    return float(peak(0.002)), float(np.median([peak(t) for t in np.arange(0.08, 0.11, 0.004)]))


def falling_ratio(x):
    """앞 30%와 뒤 30% 구간의 중심 주파수 비. 1보다 클수록 뚜렷하게 내려간다."""
    part = int(0.3 * len(x))
    return centroid_hz(x[:part]) / centroid_hz(x[-part:])


def has_square_or_saw_lines(peaks):
    """가장 강한 음의 3·5·7배에 뚜렷한 선이 모두 있으면 사각파·톱니파 모양이다."""
    if not peaks:
        return False
    f0 = max(peaks, key=lambda p: p[1])[0]
    return all(any(abs(f / (f0 * n) - 1) < 0.015 for f, _ in peaks) for n in (3, 5, 7))


def measure(x):
    return {
        "centroid": centroid_hz(x), "hi": share(x, 4000) * 100, "peak": true_peak_db(x), "rms": gated_rms_db(x),
        "a": a_weighted_db(x), "len": len(x) / SR, "mud": share(x, 200, 400) * 100,
    }


def check_sound(name, x, eq_db, wet, tail, reference):
    """기준 1~8과 종류별 길이·음 조건을 검사해 (항목, 통과, 값) 목록을 돌려준다."""
    kind = name.split("_")[0]
    m = measure(x)
    out = []

    def add(label, ok, value):
        out.append((label, bool(ok), value))

    below = share(x, 0, CHECK_BELOW_HZ[kind])
    add(f"1 {CHECK_BELOW_HZ[kind]:.0f}Hz 아래 비율 ≤1%", below <= 0.01, f"{below * 100:.2f}%")
    add("2 EQ가 200~400Hz를 -3~-6dB", -6 <= eq_db <= -3, f"{eq_db:.1f}dB")
    add("3 중심 ≥1.2kHz", m["centroid"] >= 1200, f"{m['centroid']:.0f}Hz")
    add("3 4kHz 위 ≥10%", m["hi"] >= 10, f"{m['hi']:.1f}%")
    add("4 피크 ≤-1dBFS", m["peak"] <= -1, f"{m['peak']:.1f}dBFS")
    diff = m["rms"] - reference
    low, high = (2, 3) if kind == "crash" else (-2, 2)
    add(f"4 lane_c 대비 {low:+d}~{high:+d}dB", low <= diff + 1e-3 and diff - 1e-3 <= high, f"{diff:+.1f}dB")
    tail_part = x[int(GLIDE_SEC * SR):] if kind == "jump" else x
    peaks = prominent_peaks(tail_part)
    off = [(f, note_error(f)) for f, _ in peaks if note_error(f)[0] not in PITCH_CLASSES or abs(note_error(f)[1]) > 40]
    add("5 뚜렷한 음이 마단조", not off, ", ".join(f"{f:.0f}Hz={n}{e:+.0f}c" for f, (n, e) in off) or f"봉우리 {len(peaks)}개 모두 안")
    add("6 울림 꼬리 ≤0.4초, 비율 ≤15%", tail <= MAX_REVERB_SEC and wet <= MAX_WET, f"{tail:.2f}초, {wet * 100:.0f}%")
    add("7 사각파·톱니파 선 없음", not has_square_or_saw_lines(peaks), f"봉우리 {len(peaks)}개")
    start_ms = onset_ms(x)
    add("8 첫 소리 ≤5ms", start_ms <= 5, f"{start_ms:.1f}ms")
    low, high = LENGTH_RANGE[kind]
    eff = effective_sec(x)
    add(f"길이 {low}~{high}초", low <= eff and m["len"] <= high, f"파일 {m['len']:.2f}초, 실효 {eff:.2f}초")
    if kind == "slide":
        ratio = falling_ratio(x)
        add("내려감: 앞/뒤 중심 비 ≥1.3", ratio >= 1.3, f"{ratio:.2f}배")
    if kind == "jump":
        end_hz = {"jump_a": NOTE["E6"], "jump_b": NOTE["B5"], "jump_c": NOTE["E6"]}[name]
        start, end = track_pitch(x, end_hz * 0.62, end_hz * 1.2)
        rise = 12 * np.log2(end / start)
        note, cents = note_error(end)
        add("7 올라가는 폭 3~5반음", 3 <= rise <= 5.05, f"{rise:.1f}반음")
        add("끝음 E 또는 B (±30센트)", note in "EB" and abs(cents) <= 30, f"{note}{cents:+.0f}c ({end:.0f}Hz)")
    return out, m


def self_test():
    """측정 함수가 맞는지 정답을 아는 신호로 확인한다."""
    t = times(0.5)
    tone = 0.5 * np.sin(2 * np.pi * 1000 * t)
    assert abs(centroid_hz(tone) - 1000) < 5
    assert share(tone, 4000) < 0.001 and share(0.5 * np.sin(2 * np.pi * 8000 * t), 4000) > 0.99
    assert abs(gated_rms_db(tone) - (20 * np.log10(0.5) - 3.01)) < 0.1
    assert abs(a_weighted_db(tone) - gated_rms_db(tone)) < 0.2  # A 가중치는 1kHz에서 0dB
    square = np.sign(np.sin(2 * np.pi * 500 * t))
    assert has_square_or_saw_lines(prominent_peaks(square, -30.0))
    assert not has_square_or_saw_lines(prominent_peaks(tone))
    assert note_error(NOTE["E6"])[0] == "E" and abs(note_error(NOTE["E6"])[1]) < 1
    _, response = freqz(*peaking(283.0, 1.41, -5.5), worN=[283.0], fs=SR)
    assert abs(20 * np.log10(abs(response[0])) + 5.5) < 0.1


# ---------- 결과물 ----------

def write_spectrograms(sounds):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LinearSegmentedColormap
    plt.rcParams["font.family"] = ["AppleGothic", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False
    # 크기를 나타내는 색은 한 색조로만: 밝을수록 작고 진할수록 크다
    cmap = LinearSegmentedColormap.from_list("mint", ["#ffffff", "#bfe9e6", "#3aa6a6", "#0b4f5c", "#04222b"])
    fig, axes = plt.subplots(5, 3, figsize=(12, 13.5), facecolor="white", layout="constrained")
    xlim = {"lane": 0.35, "jump": 0.35, "slide": 0.5, "land": 0.3, "crash": 0.95}
    image = None

    def draw(ax, x, title, limit):
        nonlocal image
        spec, freq, tm = plt.mlab.specgram(x, NFFT=512, Fs=SR, noverlap=448, window=np.hanning(512), mode="magnitude")[:3]
        db = 20 * np.log10(2 * spec + 1e-9)  # mlab이 이미 창 합으로 나눴다. 2배는 한쪽 스펙트럼 보정
        image = ax.pcolormesh(tm, freq, db, cmap=cmap, vmin=-70, vmax=-15, shading="auto", rasterized=True)
        ax.set_yscale("log")
        ax.set_ylim(100, 20000)
        ax.set_xlim(0, limit)
        ax.set_yticks([100, 400, 1000, 4000, 10000], ["100", "400", "1k", "4k", "10k"])
        ax.minorticks_off()
        ax.axhline(4000, color="#b4532a", linewidth=0.8, linestyle="--")
        ax.set_title(title, fontsize=11, loc="left", color="#222222")
        ax.tick_params(labelsize=8, colors="#555555")
        ax.set_xlabel("시간(초)", fontsize=8, color="#555555")
        ax.set_ylabel("Hz", fontsize=8, color="#555555")

    draw(axes[0, 0], load_wav(FIRST / "sfx" / "lane_c.wav"), "레인 이동 lane_c (확정, 기준)", xlim["lane"])
    axes[0, 1].axis("off")
    axes[0, 2].axis("off")
    axes[0, 1].text(0, 0.65, "아래는 새 후보 12개. 점선은 4kHz.\n같은 줄은 시간 축이 같다. 세로축은 로그.\n색이 진할수록 크다 (모든 칸이 같은 눈금).",
                    fontsize=11, va="center", color="#333333")
    for row, kind in enumerate(KINDS, start=1):
        for col, letter in enumerate("abc"):
            maker = "Kenney CC0 가공" if letter == "c" else "직접 합성"
            draw(axes[row, col], sounds[f"{kind}_{letter}"], f"{KOREAN[kind]} {letter.upper()} ({maker})", xlim[kind])
    fig.colorbar(image, ax=axes, label="크기(dBFS)", location="right", shrink=0.35, aspect=25)
    fig.savefig(HERE / "spectrograms.png", dpi=110)
    plt.close(fig)


def write_audio_data():
    """더블클릭(file://)으로 열어도 들리게 소리를 base64로 담는다."""
    data = {}
    for name in NAMES:
        data[name] = HERE / f"{name}.wav"
    for kind in KINDS:
        data[f"first_{kind}_a"] = FIRST / "sfx" / f"{kind}_a.wav"
    data["lane_c"] = FIRST / "sfx" / "lane_c.wav"
    data["bgm_3"] = FIRST / "bgm" / "bgm_3.flac"
    encoded = {key: base64.b64encode(path.read_bytes()).decode() for key, path in data.items()}
    (HERE / "audio_data.js").write_text("window.SOUND_DATA=" + json.dumps(encoded) + ";\n", encoding="utf-8")


def write_report(results, reference):
    lines = ["# 소리 후보 2차 측정 보고", "",
             "`python3 make_sounds_v2.py`가 만든 파일이다. 숫자는 저장된 wav를 다시 읽어서 쟀다.", "",
             "- **중심 주파수**: 파일 전체 파워 스펙트럼의 무게 중심.",
             "- **4kHz 위**: 전체 에너지 중 4kHz 위의 비율.",
             "- **피크**: 4배 오버샘플링한 트루 피크.",
             "- **평균 크기**: 20ms 조각 중 가장 큰 조각보다 30dB 안쪽만 평균한 RMS (게이트 RMS).",
             "- **A 가중**: 같은 값에 귀의 민감도를 곱한 값. 기준 판정에는 쓰지 않고 참고로 적었다.",
             "", f"기준 lane_c: 평균 크기 {reference['rms']:.1f}dB, A 가중 {reference['a']:.1f}dB, 중심 {reference['centroid']:.0f}Hz, "
             f"4kHz 위 {reference['hi']:.1f}%, 피크 {reference['peak']:.1f}dBFS, 길이 {reference['len']:.2f}초", ""]
    for kind in KINDS:
        lines += [f"## {KOREAN[kind]}", "",
                  "| 소리 | 중심(Hz) | 4kHz 위(%) | 피크(dBFS) | 평균 크기(dB) | lane_c 대비(dB) | A 가중 lane_c 대비(dB) | 200~400Hz(%) | 길이(초) |",
                  "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
        rows = [(f"1차 {kind}_{c}", measure(load_wav(FIRST / "sfx" / f"{kind}_{c}.wav"))) for c in "abc"]
        rows += [(f"**2차 {kind}_{c}**", results[f"{kind}_{c}"]["m"]) for c in "abc"]
        for label, m in rows:
            lines.append(f"| {label} | {m['centroid']:.0f} | {m['hi']:.1f} | {m['peak']:.1f} | {m['rms']:.1f} | "
                         f"{m['rms'] - reference['rms']:+.1f} | {m['a'] - reference['a']:+.1f} | {m['mud']:.1f} | {m['len']:.2f} |")
        lines.append("")
    lines += ["## 기준 1~8 검사", "", "소리마다 모든 항목을 검사한 값이다. 실패 항목이 있으면 **실패**로 표시한다.", ""]
    for name in NAMES:
        failed = [c for c in results[name]["checks"] if not c[1]]
        lines += [f"### {name}: {'모두 통과' if not failed else '못 맞춘 항목 ' + str(len(failed)) + '개'}", "", "| 항목 | 결과 | 값 |", "|---|---|---|"]
        lines += [f"| {label} | {'통과' if ok else '**실패**'} | {value} |" for label, ok, value in results[name]["checks"]]
        lines.append("")
    lines += ["## 검사 방법의 한계", "",
              "- 기준 7(사각파·톱니파 금지)은 코드에 해당 파형이 없고(A·B는 사인파+노이즈, C는 Digital Audio 팩을 쓰지 않음) 숫자로는 가장 강한 음의 3·5·7배 선을 함께 검사했다.",
              "- 기준 6의 꼬리·비율은 합성에 넣은 설정값이다. 소리 전체 길이는 파일과 실효 길이로 따로 쟀다.",
              "- 기준 5는 음이 어울리는지를 음 이름으로만 검사한다. bgm_3 위에서 듣기 좋은지는 사람 귀로 확인해야 한다. 봉우리 0개는 노이즈 위주라 음으로 잡히지 않았다는 뜻이다.",
              "- 점프의 '올라가는 폭'은 창 12ms로 잰 값이라 설계값(jump_a·c 5반음, jump_b 4반음)보다 조금 작게 나온다.",
              "- 평균 크기(RMS)는 기준을 맞췄지만 귀에는 고음이 더 크게 들린다. A 가중으로는 lane_c보다 일반 소리 +2~4dB, 충돌 +7dB다. 게임에 넣을 때 음량을 다시 조절할 수 있다.", ""]
    (HERE / "report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    self_test()
    reference_wave = load_wav(FIRST / "sfx" / "lane_c.wav")
    reference = measure(reference_wave)
    makers = {"jump_a": jump_a, "jump_b": jump_b, "jump_c": jump_c, "slide_a": slide_a, "slide_b": slide_b, "slide_c": slide_c,
              "land_a": land_a, "land_b": land_b, "land_c": land_c, "crash_a": crash_a, "crash_b": crash_b, "crash_c": crash_c}
    results, sounds = {}, {}
    for index, name in enumerate(NAMES):
        rng = np.random.default_rng(20261108 + index)
        raw, sec, wet, tail = makers[name](rng)
        kind = name.split("_")[0]
        out, eq_db = master(raw, kind, rng, sec, wet, tail, 2.4 if kind == "crash" else -1.0)  # 고음이 많아 같은 RMS여도 더 크게 들려 일반 소리는 1dB 낮춘다
        save_wav(HERE / f"{name}.wav", out)
        saved = load_wav(HERE / f"{name}.wav")
        sounds[name] = saved
        checks, m = check_sound(name, saved, eq_db, wet, tail, reference["rms"])
        results[name] = {"checks": checks, "m": m}
    write_spectrograms(sounds)
    write_audio_data()
    write_report(results, reference)
    failures = 0
    for name in NAMES:
        m = results[name]["m"]
        print(f"{name}: 중심 {m['centroid']:.0f} 4k위 {m['hi']:.1f}% 피크 {m['peak']:.1f} 크기차 {m['rms'] - reference['rms']:+.1f} A차 {m['a'] - reference['a']:+.1f} 길이 {m['len']:.2f}")
        for label, ok, value in results[name]["checks"]:
            if not ok:
                failures += 1
                print(f"  실패 {label}: {value}")
    print(f"못 맞춘 항목: {failures}개")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
