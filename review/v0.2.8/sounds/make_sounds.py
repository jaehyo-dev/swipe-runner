#!/usr/bin/env python3
"""스와이프 러너 소리 후보를 처음부터 합성한다 (외부 음원 없음, 시드 고정이라 항상 같은 결과).

사용: python3 make_sounds.py   (numpy, ffmpeg 필요)
결과: sfx/*.wav, bgm/*.flac, audio_data.js(듣기 페이지용)
기준: ART_BIBLE.md 9번. 차분하고 몽환적, 유리·물·젤리 질감, 날카로운 고음·8비트 소리 금지.
"""
import base64
import json
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 44100
HERE = Path(__file__).resolve().parent
TOP_HZ = 6000.0  # 이보다 높은 소리는 부드럽게 깎는다 (날카로운 고음 금지)


# ---------- 기본 재료 ----------

def times(sec):
    return np.arange(int(sec * SR)) / SR


def glide(f0, f1, sec, curve=1.0):
    """f0에서 f1로 미끄러지는 사인파 (위상을 누적해 끊기지 않음)."""
    u = np.linspace(0.0, 1.0, int(sec * SR), endpoint=False)
    freq = f0 * (f1 / f0) ** (u ** curve)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def decay(sec, tau):
    return np.exp(-times(sec) / tau)


def band(signal, low, high):
    """FFT로 주파수 대역만 남긴다. 경계는 부드럽게 (원형이라 루프에도 이음새가 없음)."""
    spec = np.fft.rfft(signal, axis=0)
    f = np.fft.rfftfreq(signal.shape[0], 1 / SR)
    gain = np.clip((f - low * 0.7) / max(low * 0.3, 1.0), 0, 1) * np.clip((high * 1.3 - f) / (high * 0.3), 0, 1)
    if signal.ndim == 2:
        gain = gain[:, None]
    return np.fft.irfft(spec * gain, signal.shape[0], axis=0)


def noise(rng, sec):
    return rng.standard_normal(int(sec * SR))


def mix(length_sec, *parts):
    """(시작 초, 소리) 목록을 합친다."""
    out = np.zeros(int(length_sec * SR))
    for start, sig in parts:
        i = int(start * SR)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out


def finish(sig, peak):
    """고음을 깎고 앞뒤를 살짝 줄여 '틱' 소리를 없앤 뒤 크기를 맞춘다."""
    sig = band(sig, 30.0, TOP_HZ)
    fade_in, fade_out = int(0.002 * SR), int(0.012 * SR)
    sig[:fade_in] *= np.linspace(0, 1, fade_in)
    sig[-fade_out:] *= np.linspace(1, 0, fade_out)
    return sig / np.max(np.abs(sig)) * peak


# ---------- 효과음: 종류마다 A/B/C ----------

def sfx_all():
    r = np.random.default_rng(2808)
    s = {}
    # 레인 이동: 부드러운 물방울 "뽁"
    s["lane_a"] = finish(glide(480, 900, 0.12, 0.6) * decay(0.12, 0.035), 0.45)
    s["lane_b"] = finish((glide(300, 720, 0.15, 0.5) + 0.2 * glide(600, 1440, 0.15, 0.5)) * decay(0.15, 0.04), 0.45)
    s["lane_c"] = finish(glide(420, 640, 0.1, 0.7) * decay(0.1, 0.028) + 0.1 * glide(1400, 1500, 0.1) * decay(0.1, 0.02), 0.42)
    # 점프: 올라가는 "뿅"
    s["jump_a"] = finish((glide(260, 720, 0.22, 0.8) + 0.15 * glide(520, 1440, 0.22, 0.8)) * decay(0.22, 0.09), 0.5)
    wob = 1 + 0.25 * np.sin(2 * np.pi * 22 * times(0.18))
    s["jump_b"] = finish(glide(330, 990, 0.18, 0.7) * decay(0.18, 0.07) * wob, 0.5)
    s["jump_c"] = finish(mix(0.24, (0, glide(340, 520, 0.1) * decay(0.1, 0.05)),
                             (0.08, glide(520, 800, 0.16) * decay(0.16, 0.06))), 0.5)
    # 슬라이드: 말랑한 미끄러짐
    s["slide_a"] = finish(band(noise(r, 0.38), 300, 1200) * 0.6 * np.sin(np.pi * np.linspace(0, 1, int(0.38 * SR))) ** 1.5
                          + glide(190, 110, 0.38) * decay(0.38, 0.16) * 0.8, 0.45)
    trem = 1 + 0.35 * np.sin(2 * np.pi * 17 * times(0.4))
    s["slide_b"] = finish(glide(250, 130, 0.4, 0.8) * decay(0.4, 0.18) * trem, 0.45)
    swoosh = band(noise(r, 0.45), 350, 1500) * np.sin(np.pi * np.linspace(0, 1, int(0.45 * SR))) ** 2
    s["slide_c"] = finish(swoosh + 0.3 * glide(170, 100, 0.45) * decay(0.45, 0.2), 0.42)
    # 착지: 작은 "철퍽"
    wet = band(noise(r, 0.14), 200, 1500) * decay(0.14, 0.03)
    s["land_a"] = finish(glide(140, 70, 0.16) * decay(0.16, 0.06) + 0.45 * mix(0.16, (0, wet)), 0.55)
    s["land_b"] = finish(glide(120, 60, 0.18) * decay(0.18, 0.07) + 0.4 * glide(320, 150, 0.18) * decay(0.18, 0.04), 0.55)
    wet2 = band(noise(r, 0.12), 350, 2200) * decay(0.12, 0.022)
    s["land_c"] = finish(0.7 * glide(170, 90, 0.12) * decay(0.12, 0.04) + 0.5 * wet2, 0.5)
    # 충돌: 유리 "팅" + 젤리 "철썩"
    def glass(freqs, sec, tau):
        return sum(a * np.sin(2 * np.pi * f * times(sec)) * decay(sec, tau * d) for f, a, d in freqs)
    splat = band(noise(r, 0.3), 120, 1000) * decay(0.3, 0.07)
    s["crash_a"] = finish(mix(0.7, (0, glide(120, 50, 0.3) * decay(0.3, 0.11)), (0, 0.7 * splat),
                              (0, 0.3 * glass([(1320, 1, 1), (2310, 0.5, 0.7), (3170, 0.25, 0.5)], 0.7, 0.2))), 0.7)
    splat2 = band(noise(r, 0.34), 90, 750) * decay(0.34, 0.09)
    s["crash_b"] = finish(mix(0.8, (0, 0.35 * glass([(880, 1, 1), (1540, 0.6, 0.7), (2450, 0.3, 0.5)], 0.8, 0.25)),
                              (0.02, glide(100, 42, 0.34) * decay(0.34, 0.13)), (0.02, 0.8 * splat2)), 0.7)
    slurp = glide(300, 90, 0.6, 0.7) * np.sin(np.pi * np.linspace(0, 1, int(0.6 * SR))) ** 2
    splat3 = band(noise(r, 0.22), 150, 1200) * decay(0.22, 0.05)
    s["crash_c"] = finish(mix(0.85, (0, 0.8 * splat3), (0, glide(110, 55, 0.22) * decay(0.22, 0.08)),
                              (0, 0.22 * glass([(1760, 1, 1), (2640, 0.4, 0.6)], 0.5, 0.12)), (0.14, 0.35 * slurp)), 0.68)
    return s


# ---------- 배경 음악: 원형 버퍼에 쌓아 끝과 처음이 저절로 이어진다 ----------

BPM = 100.0
BEAT = 60.0 / BPM
BARS = 16  # 16마디 x 4박 x 0.6초 = 38.4초


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


class Loop:
    def __init__(self):
        self.n = int(round(BARS * 4 * BEAT * SR))
        self.buf = np.zeros((self.n, 2))

    def put(self, beat, sig, gain=1.0, pan=0.0):
        """beat(박)에 소리를 넣는다. 끝을 넘치면 맨 앞으로 이어진다."""
        i = int(round(beat * BEAT * SR)) % self.n
        idx = (i + np.arange(len(sig))) % self.n
        np.add.at(self.buf[:, 0], idx, sig * gain * (1 - max(pan, 0)))
        np.add.at(self.buf[:, 1], idx, sig * gain * (1 + min(pan, 0)))


def kick(gain=1.0):
    return glide(95, 42, 0.32, 0.5) * decay(0.32, 0.11) * gain


def rim(rng):
    return band(rng.standard_normal(int(0.14 * SR)), 500, 2600) * decay(0.14, 0.03) * 0.7


def shaker(rng):
    return band(rng.standard_normal(int(0.07 * SR)), 2200, 5500) * decay(0.07, 0.016) * 0.5


def bass(note, beats, soft=1.0):
    sec = beats * BEAT
    t = times(sec)
    f = midi(note)
    sig = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) + 0.08 * np.sin(6 * np.pi * f * t)
    env = np.minimum(t / 0.012, 1) * np.exp(-t / (sec * 0.8 * soft)) * np.minimum((sec - t) / 0.04, 1)
    return sig * env


def pad(notes, beats):
    """부드러운 패드: 살짝 어긋난 음 여러 개 + 느린 등장·퇴장. 왼쪽·오른쪽을 다르게 어긋나 넓게 들린다."""
    sec = beats * BEAT
    t = times(sec)
    env = np.sin(np.pi * t / sec) ** 0.8
    l = sum(np.sin(2 * np.pi * midi(n) * 0.998 * t) + 0.25 * np.sin(4 * np.pi * midi(n) * 1.002 * t) for n in notes)
    r = sum(np.sin(2 * np.pi * midi(n) * 1.002 * t) + 0.25 * np.sin(4 * np.pi * midi(n) * 0.998 * t) for n in notes)
    return l * env, r * env


def bell(note, sec=1.2):
    t = times(sec)
    f = midi(note)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.15)) * np.exp(-t / 0.4) * np.minimum(t / 0.004, 1)


def pluck(note, sec=0.5):
    t = times(sec)
    f = midi(note)
    return (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.07)) * np.exp(-t / 0.14) * np.minimum(t / 0.003, 1)


def space(buf, rng, tau=1.1, wet=0.16):
    """잔향: 원형 합성곱이라 꼬리가 맨 앞으로 넘어가 루프 이음새가 없다."""
    n = buf.shape[0]
    t = np.arange(n) / SR
    out = buf.copy()
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / tau)
        ir = band(ir, 200, 4000)
        ir /= np.sqrt(np.sum(ir ** 2))
        out[:, ch] = buf[:, ch] + wet * np.fft.irfft(np.fft.rfft(buf[:, ch]) * np.fft.rfft(ir), n)
    return out


def master(buf, target_rms=0.11):
    buf = band(buf - buf.mean(axis=0), 28.0, TOP_HZ)
    buf *= target_rms / np.sqrt(np.mean(buf ** 2))
    return np.tanh(buf * 1.2) / 1.2 * 0.95  # 부드럽게 눌러 찌그러짐 없이 피크를 막는다


def stereo(loop, beat, l, r, gain):
    i = int(round(beat * BEAT * SR)) % loop.n
    idx = (i + np.arange(len(l))) % loop.n
    np.add.at(loop.buf[:, 0], idx, l * gain)
    np.add.at(loop.buf[:, 1], idx, r * gain)


def bgm_1():
    """Deep Glass (라단조, 네 박 고른 킥): 앞 8마디 북·베이스, 뒤 8마디에 패드·유리 종."""
    r = np.random.default_rng(101)
    L = Loop()
    roots = [45, 41, 36, 43]  # A F C G
    chords = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
    for bar in range(BARS):
        b = bar * 4
        root = roots[bar % 4]
        for k in range(4):
            L.put(b + k, kick(), 0.9)
            L.put(b + k + 0.5, shaker(r), 0.16, pan=0.2)
        L.put(b + 1, rim(r), 0.16, pan=-0.15)
        L.put(b + 3, rim(r), 0.16, pan=-0.15)
        for off, length in [(0, 1.4), (1.5, 0.45), (2, 1.4), (3.5, 0.45)]:
            L.put(b + off, bass(root, length), 0.5)
        if bar >= 8:
            l, rr = pad(chords[bar % 4], 4.2)
            stereo(L, b, l, rr, 0.055)
            if bar % 2 == 0:
                for off, note in zip([0, 1.5, 3], [chords[bar % 4][2] + 12, chords[bar % 4][1] + 12, chords[bar % 4][0] + 12]):
                    L.put(b + off, bell(note), 0.09, pan=0.3 if off else -0.3)
    return master(space(L.buf, r))


def bgm_2():
    """Slow Tide (라단조, 느슨한 하프타임): 킥 1박·림 3박, 물결 같은 베이스, 뒤에서 패드와 플럭."""
    r = np.random.default_rng(202)
    L = Loop()
    roots = [38, 34, 43, 45]  # D Bb G A
    chords = [[62, 65, 69], [58, 62, 65], [55, 62, 67], [57, 61, 64]]
    for bar in range(BARS):
        b = bar * 4
        root = roots[bar % 4]
        L.put(b, kick(), 1.0)
        L.put(b + 2.5, kick(), 0.6)
        L.put(b + 2, rim(r), 0.28, pan=0.1)
        for k in range(8):
            L.put(b + k * 0.5, shaker(r), 0.07 + 0.05 * (k % 2), pan=-0.2)
        for off, length, n in [(0, 1.8, root), (2, 0.9, root), (3, 0.45, root + 7), (3.5, 0.45, root + 12)]:
            L.put(b + off, bass(n, length), 0.5)
        if bar >= 8:
            l, rr = pad(chords[bar % 4], 4.2)
            stereo(L, b, l, rr, 0.06)
            for k, off in enumerate([0.5, 1.5, 2.25, 3.25]):
                note = chords[bar % 4][k % 3] + 12
                L.put(b + off, pluck(note), 0.075, pan=-0.35 + 0.23 * k)
                L.put(b + off + 0.75, pluck(note), 0.03, pan=0.35 - 0.23 * k)  # 메아리
    return master(space(L.buf, r, tau=1.4, wet=0.2))


def bgm_3():
    """Jelly Pulse (마단조, 뒤박 베이스로 통통 튐): 킥 사이사이 베이스가 말랑하게, 뒤에서 패드가 펌핑."""
    r = np.random.default_rng(303)
    L = Loop()
    roots = [40, 36, 45, 47]  # E C A B
    chords = [[64, 67, 71], [60, 64, 67], [57, 60, 64], [59, 63, 66]]
    for bar in range(BARS):
        b = bar * 4
        root = roots[bar % 4]
        for k in range(4):
            L.put(b + k, kick(), 0.85)
            L.put(b + k + 0.5, bass(root, 0.46, soft=0.7), 0.55)
            L.put(b + k + 0.75, shaker(r), 0.09, pan=0.25)
        L.put(b + 1.75, bass(root + 12, 0.22, soft=0.6), 0.25)
        L.put(b + 3, rim(r), 0.2)
        if bar >= 8:
            l, rr = pad(chords[bar % 4], 4.1)
            pump = 0.45 + 0.55 * np.abs(np.sin(np.pi * np.arange(len(l)) / (BEAT * SR)))  # 킥에 맞춰 숨 쉼
            stereo(L, b, l * pump, rr * pump, 0.06)
            if bar % 2 == 1:
                for off, note in [(0.5, chords[bar % 4][2] + 12), (1.0, chords[bar % 4][1] + 12), (2.5, chords[bar % 4][0] + 12)]:
                    L.put(b + off, bell(note, 0.9), 0.08, pan=0.25)
    return master(space(L.buf, r, tau=0.9, wet=0.14))


# ---------- 저장과 자체 확인 ----------

def to_pcm(sig):
    return (np.clip(sig, -1, 1) * 32767).astype(np.int16)


def save_wav(path, sig):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(to_pcm(sig).tobytes())


def save_flac(path, sig):
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "pipe:0",
                    "-compression_level", "12", str(path)], input=to_pcm(sig).tobytes(), check=True)


def decoded_frames(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "s16le", "-ac", "2", "pipe:1"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).reshape(-1, 2)


def high_share(sig, hz=6500.0):
    power = np.abs(np.fft.rfft(sig, axis=0)) ** 2
    f = np.fft.rfftfreq(sig.shape[0], 1 / SR)
    return power[f > hz].sum() / power.sum()


def main():
    data = {}
    for name, sig in sfx_all().items():
        assert 0.3 < np.max(np.abs(sig)) <= 0.75, name
        assert high_share(sig) < 0.001, f"{name} 고음이 많음"
        path = HERE / "sfx" / f"{name}.wav"
        save_wav(path, sig)
        print(f"{name:8s} {len(sig) / SR:5.2f}초 피크 {np.max(np.abs(sig)):.2f}")
        data[f"sfx/{name}.wav"] = base64.b64encode(path.read_bytes()).decode()
    for i, make in enumerate([bgm_1, bgm_2, bgm_3], 1):
        sig = make()
        path = HERE / "bgm" / f"bgm_{i}.flac"
        save_flac(path, sig)
        back = decoded_frames(path)
        assert len(back) == len(sig), "FLAC 길이가 원본과 달라 루프가 어긋남"
        # 이음새 확인: 끝→처음의 표본 차이가 곡 안의 평범한 표본 차이 수준인가
        steps = np.abs(np.diff(back, axis=0)).max(axis=1)
        seam = np.abs(back[0].astype(int) - back[-1].astype(int)).max()
        assert seam <= np.percentile(steps, 99.9), f"bgm_{i} 이음새 {seam}"
        assert np.max(np.abs(sig)) < 1.0
        print(f"bgm_{i}   {len(sig) / SR:5.2f}초 피크 {np.max(np.abs(sig)):.2f} RMS {np.sqrt(np.mean(sig ** 2)):.3f} "
              f"이음새 {seam} (곡 안 99.9% {np.percentile(steps, 99.9):.0f}) {path.stat().st_size / 1e6:.1f}MB")
        data[f"bgm/bgm_{i}.flac"] = base64.b64encode(path.read_bytes()).decode()
    (HERE / "audio_data.js").write_text("// make_sounds.py가 만든 파일. 더블클릭으로 열면 브라우저가 파일을 직접 못 읽어서(file://) 소리를 여기에 담아 둔다\n"
                                        "window.SOUND_DATA = " + json.dumps(data) + ";\n", encoding="utf-8")
    print("audio_data.js", f"{(HERE / 'audio_data.js').stat().st_size / 1e6:.1f}MB")


if __name__ == "__main__":
    main()
