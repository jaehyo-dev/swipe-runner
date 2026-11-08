#!/usr/bin/env python3
"""bgm_3 "Jelly Pulse"의 편곡 후보를 템포별로 다시 합성한다 (numpy, ffmpeg 필요). 게임에는 넣지 않는다.

리샘플이 아니라 합성을 다시 하므로 음 높이는 그대로이고 템포만 바뀐다. 원본의 음표·화음은 make_sounds.py의 bgm_3과 같다.
  원본: make_sounds.bgm_3()을 박 길이만 바꿔 그대로 실행 (100BPM은 원본 파일과 같은지 검사)
  A "Drive": 16분 하이햇, 단단한 킥, 베이스·패드 펌핑(사이드체인), 앞 8마디에 아주 작은 패드
  B "Drive+": A + 2마디마다 짧은 필인, 뒤 8마디 아르페지오

사용: python3 review/v0.3.1/music/make_music.py [BPM ...]  (기본 100 115 130, 기준을 못 맞추면 종료 코드 1)
결과: 같은 폴더의 data_*.js (더블클릭으로 열려고 소리를 js에 담음), report.md
"""
import base64
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "review/v0.2.8/sounds"))
sys.path.insert(0, str(ROOT / "review/v0.2.8/sounds_v2"))
import make_sounds as ms
import make_sounds_v2 as v2

SR = ms.SR
BPMS = [100, 115, 130]
ARRANGEMENTS = {"orig": "원본 Jelly Pulse", "a": "A Drive", "b": "B Drive+"}
SFX_NAMES = ["lane", "jump", "slide", "land", "crash"]
# 효과음 3차 원칙: 4kHz 위 에너지 5% 이하 (A 가중 기준)
HIGH_SHARE_LIMIT = 0.05
LEVEL_TOLERANCE_DB = 0.2
PUMP_DEPTH = 0.55     # 킥 순간 베이스·패드를 이만큼 누른다
PUMP_TAU_BEATS = 0.35 # 돌아오는 시간 (박 비율): 템포가 빨라져도 같은 숨쉬기
INTRO_PAD = 0.016     # 앞 8마디 패드 (뒤 8마디는 0.06)


def hard_kick(rng):
    """원본 킥보다 단단하게: 음높이가 더 빨리 떨어지고, 살짝 눌러 찌그러뜨리고, 아주 짧은 '탁'을 얹는다."""
    body = ms.glide(110, 44, 0.30, 0.45) * ms.decay(0.30, 0.12)
    body = np.tanh(2.2 * body) / np.tanh(2.2)
    click = ms.band(rng.standard_normal(int(0.010 * SR)), 900, 2800) * ms.decay(0.010, 0.003) * 0.18
    body[:len(click)] += click
    return body


def hat(rng):
    """부드러운 하이햇: 2.8~5.2kHz만 남겨 귀를 찌르지 않게 한다."""
    return ms.band(rng.standard_normal(int(0.05 * SR)), 2800, 5200) * ms.decay(0.05, 0.011)


def tom(rng, f0):
    """필인용 낮은 톰: 킥보다 높고 말랑하게."""
    return ms.glide(f0, f0 * 0.62, 0.16, 0.6) * ms.decay(0.16, 0.05)


def pump_curve(n):
    """박마다 눌렸다가 돌아오는 곡선. 원형이라 반복 지점에 이음새가 없다."""
    beat_pos = (np.arange(n) / SR / ms.BEAT) % 1.0
    return 1.0 - PUMP_DEPTH * np.exp(-beat_pos / PUMP_TAU_BEATS)[:, None]


def drive(plus):
    """A(plus=False)·B(plus=True). 조·멜로디·화음은 bgm_3과 같다."""
    r = np.random.default_rng(303)
    drums, ducked, top = ms.Loop(), ms.Loop(), ms.Loop()  # ducked만 킥에 눌린다
    roots = [40, 36, 45, 47]  # E C A B
    chords = [[64, 67, 71], [60, 64, 67], [57, 60, 64], [59, 63, 66]]
    accents = [1.0, 0.45, 0.7, 0.45]
    for bar in range(ms.BARS):
        b = bar * 4
        root, chord = roots[bar % 4], chords[bar % 4]
        for k in range(4):
            drums.put(b + k, hard_kick(r), 0.95)
            ducked.put(b + k + 0.5, ms.bass(root, 0.46, soft=0.7), 0.55)
        for s in range(16):
            drums.put(b + s / 4, hat(r), 0.075 * accents[s % 4], pan=0.2 if s % 2 else -0.2)
        ducked.put(b + 1.75, ms.bass(root + 12, 0.22, soft=0.6), 0.25)
        drums.put(b + 3, ms.rim(r), 0.2)
        l, rr = ms.pad(chord, 4.1)
        ms.stereo(ducked, b, l, rr, 0.06 if bar >= 8 else INTRO_PAD)
        if bar >= 8 and bar % 2 == 1:
            for off, note in [(0.5, chord[2] + 12), (1.0, chord[1] + 12), (2.5, chord[0] + 12)]:
                top.put(b + off, ms.bell(note, 0.9), 0.08, pan=0.25)
        if plus and bar % 2 == 1:  # 2마디 끝 필인
            drums.put(b + 3.5, tom(r, 190), 0.28, pan=-0.15)
            drums.put(b + 3.75, tom(r, 140), 0.32, pan=0.15)
        if plus and bar >= 8:  # 아르페지오: 화음을 8분음으로 오르내림
            for step, pick in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
                top.put(b + step / 2, ms.pluck(chord[pick] + 12, 0.32), 0.055, pan=0.3 if step % 2 else -0.3)
    mixed = drums.buf + ducked.buf * pump_curve(drums.n) + top.buf
    return ms.master(ms.space(mixed, r, tau=0.9, wet=0.14))


def render(arrangement, bpm):
    ms.BEAT = 60.0 / bpm  # make_sounds의 함수들이 이 값을 읽어 음표 자리를 정한다. 주파수는 그대로
    return ms.bgm_3() if arrangement == "orig" else drive(arrangement == "b")


def mono(x):
    return x.mean(axis=1)


def high_share(x, hz=4000.0):
    """A 가중 에너지 중 hz 위의 비율."""
    spec = np.abs(np.fft.rfft(mono(x))) ** 2
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 1.0)
    ra = (12194 ** 2 * f ** 4 / ((f ** 2 + 20.6 ** 2) * np.sqrt((f ** 2 + 107.7 ** 2) * (f ** 2 + 737.9 ** 2)) * (f ** 2 + 12194 ** 2))) ** 2
    return float((spec * ra)[f > hz].sum() / (spec * ra).sum())


def encode(x):
    """Vorbis로 줄인다 (게임과 같은 코덱). 원형이라 끝과 처음이 이어진다."""
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "m.ogg"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "pipe:0", "-map_metadata", "-1",
                        "-c:a", "libvorbis", "-q:a", "5", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], input=pcm, check=True)
        data = path.read_bytes()
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "s16le", "-acodec", "pcm_s16le", "-"], check=True, capture_output=True).stdout
    return data, np.frombuffer(raw, dtype=np.int16).reshape(-1, 2) / 32768.0


def game_gains():
    """게임과 같은 균형: AudioManager의 값을 그대로 읽는다."""
    src = (ROOT / "scripts/audio_manager.gd").read_text(encoding="utf-8")
    return {k: float(re.search(rf"const {k} := (-?[\d.]+)", src).group(1)) for k in ("MUSIC_DB", "SFX_DB", "DUCK_DB", "DUCK_TIME", "DUCK_FADE")}


def jump_time():
    return float(re.search(r"const JUMP_TIME := ([\d.]+)", (ROOT / "scripts/logic/player_action.gd").read_text(encoding="utf-8")).group(1))


def demo_events():
    """같이 듣기: 게임 패턴과 같은 규칙. 앞 8마디 2박마다 이동 위주, 뒤 8마디 1~2박마다 골고루, 큰 동작 뒤 2박. 끝에 충돌 한 번."""
    r = np.random.default_rng(136)
    events, beat, lane_dir = [], 4, 1
    while beat < 62:
        intro = beat < 32
        start = beat % 4 == 0
        big = r.random() < ((0.5 if start else 0.2) if intro else (0.8 if start else 2 / 3))
        if big:
            kind = "jump" if r.random() < 0.5 else "slide"
            events.append([beat, kind])
            gap = 2
        else:
            lane_dir = -lane_dir if r.random() < 0.6 else lane_dir
            events.append([beat, "lane+" if lane_dir > 0 else "lane-"])
            gap = 2 if intro else int(r.integers(1, 3))
        beat += gap
        if beat < 32 and beat % 2 == 1:
            beat += 1
    events.append([62, "crash"])
    return events


def self_test():
    """이 파일의 재료가 뜻대로 동작하는지, 템포만 바뀌는지 확인."""
    ms.BEAT = 0.6
    p = pump_curve(int(0.6 * SR))
    assert abs(p[0, 0] - (1 - PUMP_DEPTH)) < 1e-9 and p[-1, 0] > 0.9, "펌핑은 박 첫머리에서 가장 낮고 박 끝에서 돌아옴"
    tone = np.sin(2 * np.pi * 5000 * np.arange(SR) / SR)
    assert high_share(np.stack([tone, tone], axis=1)) > 0.99 and high_share(np.stack([tone * 0 + 0.1 * np.sin(2 * np.pi * 200 * np.arange(SR) / SR)] * 2, axis=1)) < 0.01
    assert len(demo_events()) > 20 and demo_events()[-1] == [62, "crash"]


def main():
    self_test()
    bpms = [int(a) for a in sys.argv[1:]] or BPMS
    gains = game_gains()
    errors, rows = [], []
    ms.BEAT = 0.6
    original = ms.bgm_3()
    flac = ms.decoded_frames(ROOT / "review/v0.2.8/sounds/bgm/bgm_3.flac") / 32768.0
    diff = np.abs(original - flac).max()
    if diff > 2 / 32768:
        errors.append(f"100BPM 재합성이 bgm_3.flac과 다름 (최대 차이 {diff:.5f})")
    target = v2.a_weighted_db(mono(original))
    crash_peak = 10 ** (-0.7 / 20) * 10 ** (gains["SFX_DB"] / 20)
    tracks = {}
    for arr in ARRANGEMENTS:
        for bpm in bpms:
            x = render(arr, bpm)
            x = x * 10 ** ((target - v2.a_weighted_db(mono(x))) / 20)  # 원본과 같은 A 가중 크기로
            data, back = encode(x)
            name = f"{arr}_{bpm}"
            (HERE / f"data_{name}.js").write_text(f'(window.MUSIC_DATA=window.MUSIC_DATA||{{}})["{name}"]="{base64.b64encode(data).decode()}";\n', encoding="utf-8")
            level = v2.a_weighted_db(mono(back))
            peak = float(np.abs(back).max())
            share = high_share(back)
            seam = np.abs(back[0] - back[-1]).max()
            step99 = np.quantile(np.abs(np.diff(back, axis=0)), 0.999)
            rows.append(dict(name=name, label=ARRANGEMENTS[arr], bpm=bpm, sec=len(back) / SR, level=level, peak=20 * np.log10(peak), share=share, seam=seam, step=step99, kb=len(data) // 1024, rms=20 * np.log10(np.sqrt(np.mean(back ** 2)))))
            if len(back) != len(x):
                errors.append(f"{name}: 디코딩 길이 {len(back)} != {len(x)}")
            if abs(level - target) > LEVEL_TOLERANCE_DB:
                errors.append(f"{name}: 크기 {level:.2f}dB, 기준 {target:.2f}dB")
            if peak * 10 ** (gains["MUSIC_DB"] / 20) + crash_peak > 1.0:
                errors.append(f"{name}: 게임 크기에서 음악 피크 + 충돌 피크가 1을 넘음")
            if share > HIGH_SHARE_LIMIT:
                errors.append(f"{name}: 4kHz 위 {share * 100:.1f}%")
            if seam > step99 * 2:
                errors.append(f"{name}: 반복 이음매 {seam:.4f}, 곡 안 99.9% {step99:.4f}")
            print(f"{name:9} {len(back) / SR:6.2f}초 A {level:6.2f}dB RMS {rows[-1]['rms']:6.1f}dB 피크 {rows[-1]['peak']:5.1f}dBFS 4kHz위 {share * 100:4.1f}% {len(data) // 1024}KB")
            tracks[name] = {"sec": len(back) / SR}
    sfx = {n: base64.b64encode((ROOT / f"assets/audio/sfx/{n}.wav").read_bytes()).decode() for n in SFX_NAMES}
    meta = dict(gains=gains, jump_time=jump_time(), events=demo_events(), bpms=bpms, arrangements=ARRANGEMENTS, beats=64)
    (HERE / "data_sfx.js").write_text("// make_music.py가 만든 파일. 더블클릭(file://)에서는 파일을 직접 못 읽어 js에 담는다\nwindow.SFX_DATA=" + json.dumps(sfx) + ";\nwindow.META=" + json.dumps(meta, ensure_ascii=False) + ";\n", encoding="utf-8")
    lines = ["# 배경 음악 후보 측정", "", f"`python3 review/v0.3.1/music/make_music.py`가 만든 파일을 다시 디코딩해 쟀다. 100BPM 원본 재합성과 bgm_3.flac의 최대 표본 차이 {diff:.6f}.",
             f"모두 원본과 같은 A 가중 크기({target:.1f}dB)로 맞췄고, 페이지는 게임과 같이 음악 {gains['MUSIC_DB']:+.0f}dB·효과음 {gains['SFX_DB']:+.0f}dB로 튼다.", "",
             "| 곡 | BPM | 길이 | A 가중 | RMS | 피크 | 4kHz 위 (A 가중, 기준 5% 이하) | 반복 이음매 (곡 안 99.9%) | 크기 |", "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['label']} | {r['bpm']} | {r['sec']:.2f}초 | {r['level']:.1f}dB | {r['rms']:.1f}dB | {r['peak']:.1f}dBFS | {r['share'] * 100:.1f}% | {r['seam']:.4f} ({r['step']:.4f}) | {r['kb']}KB |")
    (HERE / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    for e in errors:
        print("실패:", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
