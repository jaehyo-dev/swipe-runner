#!/usr/bin/env python3
"""기둥을 통해 본 뒤 장애물의 밝기 비율과 컬러·흑백 시트. 사용: see_through_report.py <사진 폴더> <결과 폴더>
재는 자리: 기호(테두리)를 검게 칠한 사진과 달라지는 화소 중 앞 기둥 몸통 안(앞 기둥 테두리 자리 제외).
화면 값은 그 부위의 가장 센 채널, sRGB 8비트. 다음 둘을 적는다.
- 보이는 비율 = 앞 기둥을 통해 본 값 / 앞 기둥이 없을 때 값 (파란 몸통의 색까지 포함)
- 순 비율 = (통해 본 값 - 그 자리의 몸통 값) / (없을 때 값 - 그 자리의 배경 값): 뒤 장애물의 빛이 몸통 위로 얼마나 올라오는가"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

src, out = Path(sys.argv[1]), Path(sys.argv[2])
load = lambda n: np.asarray(Image.open(src / f"{n}.png").convert("RGB"), dtype=float)
rows, crops = [], {}
for z in ("z10", "z25"):
    empty, front, front_noedge = load(f"empty_{z}"), load(f"front_{z}"), load(f"front_noedge_{z}")
    silhouette = np.abs(front - empty).max(axis=2) > 6
    inside = silhouette & (np.abs(front - front_noedge).max(axis=2) < 40)  # 앞 기둥 몸통만 (테두리 관 제외, 번짐은 넓어서 둔다)
    for kind, parts in (("low", ("mark", "edge")), ("high", ("mark", "edge")), ("block", ("edge",))):
        tag = f"{kind}_{z}"
        both, back = load(f"both_{tag}"), load(f"back_{tag}")
        for part in parts:
            lit = np.abs(back - load(f"back_no{part}_{tag}")).max(axis=2)
            mask = (lit > 40) & inside
            if part == "edge" and kind != "block":  # 번짐이 기호에 섞이지 않게
                mask &= np.abs(back - load(f"back_nomark_{tag}")).max(axis=2) < 20
            n = int(mask.sum())
            if not n:
                rows.append((z, kind, part, 0, 0, 0, float("nan"), float("nan")))
                continue
            ch = np.argmax((back - empty)[mask].sum(axis=0))  # 부위의 가장 센 채널 하나로 재서 색이 달라도 비교가 된다
            a, b, f, e = (x[mask][:, ch].mean() for x in (back, both, front, empty))
            rows.append((z, kind, part, n, a, b, b / a, (b - f) / (a - e)))
names = {"low": "턱", "high": "막대", "block": "기둥"}
parts = {"mark": "기호", "edge": "테두리"}
table = ["| 앞 기둥 z | 뒤 장애물 | 부위 | 잰 화소 | 앞 기둥 없을 때 | 앞 기둥을 통해 | 보이는 비율 | 순 비율 |", "|---|---|---|---|---|---|---|---|"]
for z, kind, part, n, a, b, r, t in rows:
    table.append(f"| -{z[1:]} | {names[kind]} | {parts[part]} | {n} | {a:.0f} | {b:.0f} | **{r*100:.0f}%** | {t*100:.0f}% |")
(out / "see_through.md").write_text("\n".join(table) + "\n", encoding="utf-8")
print("\n".join(table))
# 시트: 위 z -10, 아래 z -25. 왼쪽부터 턱, 막대, 기둥. 앞 기둥 주변을 잘라 같은 크기로 키운다
sheet = []
for z in ("z10", "z25"):
    both = {k: load(f"both_{k}_{z}") for k in ("low", "high", "block")}
    ys, xs = np.nonzero(np.abs(both["block"] - load(f"empty_{z}")).max(axis=2) > 12)
    cx, cy, half = int(np.median(xs)), int(np.median(ys)), max(xs.ptp(), ys.ptp()) // 2 + 30
    row = [Image.fromarray(v[cy - half:cy + half, cx - half:cx + half].astype(np.uint8)).resize((520, 520), Image.LANCZOS) for v in both.values()]
    sheet.append(np.concatenate([np.asarray(i) for i in row], axis=1))
color = np.concatenate(sheet, axis=0)
Image.fromarray(color).save(out / "see_through_color.png")
Image.fromarray(color).convert("L").save(out / "see_through_gray.png")
