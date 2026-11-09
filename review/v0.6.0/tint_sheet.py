#!/usr/bin/env python3
"""진하기 시트: 같은 장면 t = 0 / 0.5 / 1 × 컬러 / 흑백 / 적록색약. 사용: tint_sheet.py <art_sheet 결과 폴더> <결과.png>"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Machado 2009 deuteranomaly 심도 1.0 (선형 RGB에 곱한다)
DEUTAN = np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]])
FONT = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 26)
CROP = (40, 300, 680, 1040)


def to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def deutan(img):
    a = to_linear(np.asarray(img.convert("RGB"), float) / 255.0)
    return Image.fromarray((to_srgb(a @ DEUTAN.T) * 255).astype("uint8"))


def mean_saturation(img):
    a = np.asarray(img.convert("RGB"), float) / 255.0
    hi, lo = a.max(axis=2), a.min(axis=2)
    return float(np.where(hi > 0, (hi - lo) / np.maximum(hi, 1e-6), 0.0).mean())


def main(src, out):
    values = {n: mean_saturation(Image.open(Path(src) / f"tint_{n}.png").convert("RGB").crop(CROP)) for n in (0, 50, 100)}
    print("평균 채도 " + ", ".join(f"t={n / 100:g}: {v:.3f}" for n, v in values.items()) + f", t=1 - t=0: {values[100] - values[0]:+.3f}")
    cell = (384, 444)
    sheet = Image.new("RGB", (150 + cell[0] * 3, 60 + cell[1] * 3), (12, 8, 32))
    draw = ImageDraw.Draw(sheet)
    rows = [("컬러", lambda i: i), ("흑백", lambda i: i.convert("L").convert("RGB")), ("적록색약", deutan)]
    for col, (name, label) in enumerate([("tint_0", "t = 0"), ("tint_50", "t = 0.5"), ("tint_100", "t = 1")]):
        draw.text((150 + cell[0] * col + 150, 16), label, font=FONT, fill="white")
        shot = Image.open(Path(src) / f"{name}.png").convert("RGB").crop(CROP)
        for row, (title, fn) in enumerate(rows):
            sheet.paste(fn(shot).resize(cell, Image.LANCZOS), (150 + cell[0] * col, 60 + cell[1] * row))
            if col == 0:
                draw.text((14, 60 + cell[1] * row + 200), title, font=FONT, fill="white")
    sheet.save(out)


main(sys.argv[1], sys.argv[2])
