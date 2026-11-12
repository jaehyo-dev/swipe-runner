"""점수 생존 곡선 그림 (v0.10.1): tools/score_report.gd가 만든 CSV → PNG.
사용: python3 tools/plot_survival.py review/v0.10.1/curve_after.csv review/v0.10.1/survival.png [비교용_이전.csv]
"""
import csv
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

COLORS = {"보통": "#2a78d6", "잘함": "#eb6834"}  # 범주 1·2번 색 (고정 순서)
plt.rcParams["font.family"] = ["AppleGothic", "Noto Sans CJK KR", "DejaVu Sans"]


def load(path):
    with open(path, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return [int(r["score"]) for r in rows], {k: [float(r[k]) for r in rows] for k in COLORS}


def main():
    after, out = sys.argv[1], sys.argv[2]
    x, ys = load(after)
    fig, ax = plt.subplots(figsize=(9, 5), dpi=120)
    if len(sys.argv) > 3:  # 이전(옛 모델·고비 없음)은 점선
        bx, bys = load(sys.argv[3])
        for k, c in COLORS.items():
            ax.plot(bx, bys[k], color=c, lw=1.5, ls=(0, (4, 3)), alpha=0.55, label=f"{k} 모델 (v0.10.0)")
    for k, c in COLORS.items():
        ax.plot(x, ys[k], color=c, lw=2, marker="o", ms=4, label=f"{k} 모델 (v0.10.1)")
    for v, name in [(5000, "고비 5000"), (8000, "8000"), (10000, "10000")]:
        ax.axvline(v, color="#999999", lw=1, ls=":")
        ax.text(v + 80, 101, name, color="#555555", fontsize=9, va="bottom")
    ax.set_xlim(0, 12000)
    ax.set_ylim(0, 108)
    ax.set_xlabel("점수")
    ax.set_ylabel("이 점수에 도달한 판 (%)")
    ax.set_title("점수 생존 곡선 (사람 모델, 시드 50)", loc="left")
    ax.grid(axis="y", color="#e5e5e5", lw=0.8)
    for side in ["top", "right"]:
        ax.spines[side].set_visible(False)
    ax.legend(frameon=False, fontsize=9, loc="lower left")
    fig.tight_layout()
    fig.savefig(out)


if __name__ == "__main__":
    main()
