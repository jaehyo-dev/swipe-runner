"""도구와 버전 관리 자동 테스트.

실행: python3 -m unittest discover -s tools -p "test_*.py" -v
"""
import io
import re
import unittest
from pathlib import Path

import changelog
import versions_page

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ChangelogTest(unittest.TestCase):
    SAMPLE = "# 기록\n\n## [2.0.0] - 2026-01-02\n\n- 새 것\n\n## [1.0.0] - 2026-01-01\n- 첫 것\n"

    def test_버전별_릴리스_설명을_잘라냄(self):
        self.assertEqual(changelog.release_notes(self.SAMPLE, "2.0.0"), "- 새 것")
        self.assertEqual(changelog.release_notes(self.SAMPLE, "v1.0.0"), "- 첫 것")
        self.assertIsNone(changelog.release_notes(self.SAMPLE, "3.0.0"))

    def test_버전이_다르면_알려_줌(self):
        self.assertEqual(changelog.version_mismatches(self.SAMPLE, "2.0.0"), [])
        self.assertEqual(len(changelog.version_mismatches(self.SAMPLE, "1.0.0")), 1)
        self.assertEqual(len(changelog.version_mismatches("버전 없음", "1.0.0")), 1)

    def test_명령줄_사용법이_틀리면_실패(self):
        self.assertEqual(changelog.main(["엉뚱한명령"], err=io.StringIO()), 2)


class RepoVersionTest(unittest.TestCase):
    def test_project_godot_버전이_CHANGELOG_최신_버전과_같음(self):
        game = changelog.godot_version(read("project.godot"))
        self.assertRegex(game, r"^\d+\.\d+\.\d+$")
        self.assertEqual(changelog.version_mismatches(read("CHANGELOG.md"), game), [])

    def test_CHANGELOG_버전은_모두_릴리스_설명이_있음(self):
        text = read("CHANGELOG.md")
        for entry in changelog.parse_changelog(text):
            self.assertTrue(entry["body"], entry["version"] + " 설명이 비어 있음")
        versions = [tuple(map(int, e["version"].split("."))) for e in changelog.parse_changelog(text)]
        self.assertEqual(versions, sorted(versions, reverse=True), "최신 버전이 맨 위여야 함")


class VersionsPageTest(unittest.TestCase):
    def test_이전_버전_링크를_만듦(self):
        page = versions_page.render("0.2.0", ["0.1.0"])
        self.assertIn('href="v0.1.0/"', page)
        self.assertIn("v0.2.0", page)

    def test_이전_버전이_없으면_안내_문구(self):
        self.assertIn("아직 이전 버전이 없습니다", versions_page.render("0.1.0", []))


class ThirdPartyTest(unittest.TestCase):
    def test_글꼴은_라이선스_파일과_CREDITS_기록이_있음(self):
        self.assertTrue((ROOT / "assets/fonts/LICENSE-OFL.txt").is_file())
        self.assertIn("Poppins", read("CREDITS.md"))

    def test_비밀_정보_파일은_gitignore에_있음(self):
        ignore = read(".gitignore")
        for pattern in [".env", "*.pem", "*.key"]:
            self.assertIn(pattern, ignore)


if __name__ == "__main__":
    unittest.main()
