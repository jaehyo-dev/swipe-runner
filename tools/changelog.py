#!/usr/bin/env python3
"""CHANGELOG.md에서 버전별 내용을 꺼내는 도구.

GitHub Actions 배포 워크플로와 자동 테스트가 함께 쓴다. 표준 라이브러리만 사용한다.
  python3 tools/changelog.py versions      → 기록된 버전 목록(최신순, 한 줄에 하나)
  python3 tools/changelog.py latest        → 가장 최신 버전 (project.godot 버전과 다르면 실패)
  python3 tools/changelog.py notes 0.1.0   → 해당 버전의 릴리스 설명
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# '## [1.2.0] - 2026-11-02' 형식의 버전 제목
HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\](?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$")
# project.godot의 게임 버전 줄
GODOT_VERSION = re.compile(r'^config/version="([^"]*)"\s*$', re.MULTILINE)


def parse_changelog(text):
    """변경 기록을 [{version, date, body}] 목록으로 나눈다 (파일에 적힌 순서 그대로)."""
    entries = []
    current = None
    for line in str(text).splitlines():
        match = HEADING.match(line)
        if match:
            current = {"version": match.group(1), "date": match.group(2), "lines": []}
            entries.append(current)
        elif line.startswith("## "):
            current = None  # 버전이 아닌 다른 제목은 어느 버전에도 넣지 않는다
        elif current is not None:
            current["lines"].append(line)
    return [
        {"version": e["version"], "date": e["date"], "body": "\n".join(e["lines"]).strip()}
        for e in entries
    ]


def release_notes(text, version):
    """특정 버전의 릴리스 설명. 없으면 None."""
    wanted = str(version).lstrip("v")
    for entry in parse_changelog(text):
        if entry["version"] == wanted:
            return entry["body"]
    return None


def godot_version(project_text):
    """project.godot 내용에서 게임 버전을 읽는다. 없으면 None."""
    match = GODOT_VERSION.search(project_text)
    return match.group(1) if match else None


def version_mismatches(changelog_text, game_version):
    """CHANGELOG 최신 버전과 게임 버전이 다른 점을 찾는다. 문제가 없으면 빈 목록.

    자동 태그가 잘못된 버전으로 붙지 않게 막는 데 쓴다.
    """
    entries = parse_changelog(changelog_text)
    if not entries:
        return ["CHANGELOG.md에 버전 항목이 없습니다."]
    latest = entries[0]["version"]
    if game_version != latest:
        return [f"project.godot의 config/version({game_version})이 CHANGELOG 최신 버전({latest})과 다릅니다."]
    return []


def main(argv, root=ROOT, out=sys.stdout, err=sys.stderr):
    """명령줄 실행. 종료 코드를 돌려준다."""
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    command = argv[0] if argv else ""
    if command == "versions":
        out.write("".join(e["version"] + "\n" for e in parse_changelog(text)))
        return 0
    if command == "latest":
        game = godot_version((root / "project.godot").read_text(encoding="utf-8"))
        problems = version_mismatches(text, game)
        if problems:
            err.write("\n".join(problems) + "\n")
            return 1
        out.write(parse_changelog(text)[0]["version"] + "\n")
        return 0
    if command == "notes" and len(argv) > 1:
        notes = release_notes(text, argv[1])
        if notes is None:
            err.write(f"CHANGELOG.md에 {argv[1]} 항목이 없습니다.\n")
            return 1
        out.write(notes + "\n")
        return 0
    err.write("사용법: python3 tools/changelog.py versions | latest | notes <버전>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
