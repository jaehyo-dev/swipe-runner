"""v0.11.0 스킨 시트·GIF·흑백 비교 만들기 (check_web.mjs 결과에서). 사용: python3 make_sheet.py <캡처 폴더> <결과 폴더>"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageOps

SKINS = ['mint', 'strawberry', 'lemon', 'grape', 'soda', 'night', 'aurora', 'gold']
SHOTS = ['menu', 'run', 'jump', 'crash']
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)

# 시트: 줄 = 스킨, 칸 = 메인/달리기/점프/충돌. 한 장은 390x844의 절반 크기
W, H = 195, 422
for q in ['q0', 'q4']:
    sheet = Image.new('RGB', (W * len(SHOTS), H * len(SKINS)), 'black')
    for r, skin in enumerate(SKINS):
        for c, shot in enumerate(SHOTS):
            img = Image.open(f'{src}/sheet_{q}/{skin}_{shot}.png').convert('RGB').resize((W, H), Image.LANCZOS)
            sheet.paste(img, (c * W, r * H))
    sheet.save(f'{dst}/skins_sheet_{q}.png')

# 젤리만 크게 보는 시트 (달리기 장면에서 젤리 둘레를 원래 크기로 잘라 8개 나란히) + 흑백
def jelly_strip(q, shot, box):
    tiles = [Image.open(f'{src}/sheet_{q}/{s}_{shot}.png').convert('RGB').crop(box) for s in SKINS]
    w, h = tiles[0].size
    strip = Image.new('RGB', (w * len(tiles), h))
    for i, t in enumerate(tiles):
        strip.paste(t, (i * w, 0))
    return strip

for q in ['q0', 'q4']:
    strip = jelly_strip(q, 'run', (95, 470, 295, 700))
    strip.save(f'{dst}/jelly_run_{q}.png')
    ImageOps.grayscale(strip).save(f'{dst}/jelly_run_{q}_gray.png')

# GIF: 프레임 폴더 → 게임 시간과 같은 빠르기의 GIF (check_web.json의 캡처 시간 × 시간 배율 ÷ 프레임 수)
import json
report = json.load(open(f'{src}/check_web.json'))
for name, key in [('gif_flip', 'flip'), ('gif_locked', 'locked')]:
    frames = [Image.open(p).convert('RGB').crop((0, 300, 390, 700)) for p in sorted(glob.glob(f'{src}/{name}/*.png'))]
    if frames and key in report:
        r = report[key]
        step = max(20, round(r['ms'] * r['slow'] / len(frames) / 10) * 10)
        frames[0].save(f'{dst}/{key}.gif', save_all=True, append_images=frames[1:], duration=step, loop=0)
        print(name, len(frames), '프레임', step, 'ms')
