#!/usr/bin/env python3
"""이전 버전 목록 페이지(versions/index.html)를 만든다.

배포 워크플로가 이전 버전들을 빌드한 뒤 호출한다.
  python3 tools/versions_page.py <출력 파일> <현재 버전> [이전 버전 ...]
"""
import html
import sys
from pathlib import Path


def render(current, older):
    """현재 버전과 이전 버전 목록(최신순)으로 HTML을 만든다."""
    if older:
        items = "\n".join(
            f'      <li><a href="v{html.escape(v)}/">v{html.escape(v)}</a></li>' for v in older
        )
        body = f"    <ul>\n{items}\n    </ul>"
    else:
        body = "    <p>아직 이전 버전이 없습니다.</p>"
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>스와이프 러너 - 이전 버전</title>
  <style>
    body {{ background: #0a0f2e; color: #dfe6ff; font-family: sans-serif; margin: 0; padding: 24px 16px; }}
    main {{ max-width: 480px; margin: 0 auto; }}
    h1 {{ color: #7fe0c8; font-size: 1.4rem; }}
    a {{ color: #b9a6ff; }}
    li {{ margin: 8px 0; font-size: 1.1rem; }}
  </style>
</head>
<body>
  <main>
    <h1>스와이프 러너 - 이전 버전</h1>
    <p><a href="../">최신 버전(v{html.escape(current)})으로 돌아가기</a></p>
{body}
  </main>
</body>
</html>
"""


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("사용법: python3 tools/versions_page.py <출력 파일> <현재 버전> [이전 버전 ...]\n")
        return 2
    out = Path(argv[0])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(argv[1], argv[2:]), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
