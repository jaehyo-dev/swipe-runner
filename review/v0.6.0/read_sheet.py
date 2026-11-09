#!/usr/bin/env python3
"""장애물 읽기 시트: 세 거리(z -10, -25, -45) × 컬러 / 흑백 / 적록색약. 사용: read_sheet.py <캡처 폴더> <결과.png>"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Machado 2009 deuteranomaly 심도 1.0 (선형 RGB에 곱한다)
DEUTAN = np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]])
FONT = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 26)
FAR_CROP = {10: (60, 440, 660, 960), 25: (200, 470, 520, 747), 45: (280, 490, 440, 629)}


def to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def deutan(img):
    a = to_linear(np.asarray(img.convert("RGB"), float) / 255.0)
    return Image.fromarray((to_srgb(a @ DEUTAN.T) * 255).astype("uint8"))


def main(src, out):
    cell = (420, 364)
    sheet = Image.new("RGB", (170 + cell[0] * 3, 70 + cell[1] * 3), (12, 8, 32))
    draw = ImageDraw.Draw(sheet)
    rows = [("컬러", lambda i: i), ("흑백", lambda i: i.convert("L").convert("RGB")), ("적록색약", deutan)]
    for col, z in enumerate(FAR_CROP):
        draw.text((170 + cell[0] * col + 150, 20), f"z -{z}", font=FONT, fill="white")
        shot = Image.open(f"{src}/sheet_z{z}.png").convert("RGB").crop(FAR_CROP[z])
        for row, (name, fn) in enumerate(rows):
            sheet.paste(fn(shot).resize(cell, Image.LANCZOS), (170 + cell[0] * col, 70 + cell[1] * row))
            if col == 0:
                draw.text((18, 70 + cell[1] * row + 160), name, font=FONT, fill="white")
    sheet.save(out)


main(sys.argv[1], sys.argv[2])
