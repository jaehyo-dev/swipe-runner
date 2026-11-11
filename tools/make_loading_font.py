#!/usr/bin/env python3
"""웹 로딩 화면의 제목 글자용 Poppins ExtraLight 조각을 web/shell.html에 넣는다 (fonttools 필요).

로딩 화면은 엔진이 오기 전에 바로 보여야 하므로 글꼴을 따로 받지 않고 HTML 안에 넣는다.
"SWIPE PULSE"에 쓰는 글자만 남겨(약 3KB) 첫 화면이 늦어지지 않게 한다. 글꼴은 SIL OFL 1.1 (CREDITS.md).
사용: python3 tools/make_loading_font.py   (fonttools가 없으면 pip install fonttools)
"""
import base64
import io
import re
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "assets/fonts/Poppins-ExtraLight.ttf"
SHELL = ROOT / "web/shell.html"
TEXT = "SWIPE PULSE"
MARK = re.compile(r"(/\*FONT\*/url\(data:font/woff;base64,)[A-Za-z0-9+/=]*(\))")


def make() -> str:
    font = TTFont(FONT)
    options = subset.Options()
    options.flavor = "woff"
    options.layout_features = []
    options.name_IDs = [0, 1, 2]  # 저작권·이름만 남긴다 (OFL: 저작권 표시 유지)
    sub = subset.Subsetter(options)
    sub.populate(text=TEXT)
    sub.subset(font)
    out = io.BytesIO()
    font.flavor = "woff"
    font.save(out)
    return base64.b64encode(out.getvalue()).decode()


def main() -> int:
    data = make()
    html = SHELL.read_text(encoding="utf-8")
    if not MARK.search(html):
        print("web/shell.html에 /*FONT*/ 자리가 없음", file=sys.stderr)
        return 1
    SHELL.write_text(MARK.sub(lambda m: m.group(1) + data + m.group(2), html), encoding="utf-8")
    print(f"글꼴 조각 {len(data) * 3 // 4} 바이트 → {SHELL.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
