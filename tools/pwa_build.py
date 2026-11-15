#!/usr/bin/env python3
"""웹 내보내기 결과를 홈 화면 앱(PWA)으로 마무리한다 (v0.12.0). 내보내기와 music/ 복사 뒤에 실행한다.

  python3 tools/pwa_build.py build/web

1) web/pwa/의 아이콘·시작 화면 그림을 <폴더>/pwa/로 복사, 아이폰 홈 화면 아이콘(index.apple-touch-icon.png)을 젤리 아이콘으로
2) Godot가 만든 index.manifest.json에 짧은 이름·테마 색·범위·192·maskable 아이콘을 더한다
3) Godot 서비스 워커를 web/pwa/sw.js로 바꾼다: 캐시 이름에 게임 버전, 저장 목록 = 폴더 맨 위 파일 + music/*.ogg
표준 라이브러리만 쓴다.
"""
import json
import shutil
import sys
from pathlib import Path

import changelog

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "web" / "pwa"
NAME = "SWIPE PULSE"
COLOR = "#05040D"
SW = "index.service.worker.js"
SKIP = {SW, "index.offline.html", ".gdignore", ".nojekyll"}  # 오프라인 안내 페이지는 쓰지 않는다 (전부 저장)


def cached_files(out):
    """서비스 워커가 설치 때 받아 둘 파일 (폴더 기준 경로, 이름순). pwa/ 그림은 설치할 때 OS가 받으므로 넣지 않는다."""
    top = sorted(p.name for p in out.iterdir() if p.is_file() and p.name not in SKIP)
    music = sorted("music/" + p.name for p in (out / "music").glob("*.ogg"))
    return top + music


def manifest(base):
    """Godot가 만든 manifest에 필요한 값을 덮어쓴다. scope는 ./ (versions/ 아래 옛 버전은 서비스 워커·셸이 따로 뺀다)."""
    base = dict(base)
    base.update({
        "name": NAME,
        "short_name": NAME,
        "id": "./",
        "start_url": "./",
        "scope": "./",
        "display": "standalone",
        "orientation": "portrait",
        "background_color": COLOR,
        "theme_color": COLOR,
        "icons": [
            {"src": "pwa/icon_192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "pwa/icon_512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "pwa/icon_maskable_512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
    })
    return base


def service_worker(version, files):
    text = (SRC / "sw.js").read_text(encoding="utf-8")
    assert "__VERSION__" in text and "__FILES__" in text
    return text.replace("__VERSION__", version).replace("__FILES__", json.dumps(files))


def main(argv):
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(argv[0])
    path = out / "index.manifest.json"
    if not path.is_file() or not (out / "index.html").is_file():
        print(f"{out}: Godot PWA 내보내기 결과(index.html, index.manifest.json)가 없음", file=sys.stderr)
        return 1
    (out / "pwa").mkdir(exist_ok=True)
    for png in SRC.glob("*.png"):
        shutil.copy2(png, out / "pwa" / png.name)
    shutil.copy2(SRC / "icon_180.png", out / "index.apple-touch-icon.png")  # Godot 링크는 프로젝트 아이콘(icon.svg)으로 만든다
    path.write_text(json.dumps(manifest(json.loads(path.read_text(encoding="utf-8"))), indent=1), encoding="utf-8")
    version = changelog.godot_version((ROOT / "project.godot").read_text(encoding="utf-8"))
    files = cached_files(out)
    (out / SW).write_text(service_worker(version, files), encoding="utf-8")
    print(f"PWA v{version}: 저장 파일 {len(files)}개")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
