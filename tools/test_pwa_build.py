"""홈 화면 앱 마무리 도구(tools/pwa_build.py) 테스트 (v0.12.0). 실행: python3 -m unittest discover -s tools -p "test_*.py" """
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import changelog
import pwa_build

ROOT = Path(__file__).resolve().parent.parent


class PwaBuildTest(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.out)
        for name in ["index.html", "index.js", "index.wasm", "index.pck", "index.offline.html", "index.service.worker.js"]:
            (self.out / name).write_text("x")
        (self.out / "index.manifest.json").write_text(json.dumps({"name": "SWIPE PULSE", "start_url": "./index.html", "icons": []}))
        (self.out / "music").mkdir()
        (self.out / "music" / "b.ogg").write_text("x")
        (self.out / "music" / "a.ogg").write_text("x")
        (self.out / "licenses").mkdir()
        (self.out / "licenses" / "x.txt").write_text("x")

    def test_빌드를_앱으로_마무리(self):
        self.assertEqual(pwa_build.main([str(self.out)]), 0)
        m = json.loads((self.out / "index.manifest.json").read_text())
        self.assertEqual((m["short_name"], m["theme_color"], m["background_color"], m["display"], m["scope"]), ("SWIPE PULSE", "#05040D", "#05040D", "standalone", "./"))
        self.assertEqual({i["sizes"] for i in m["icons"]}, {"192x192", "512x512"})
        self.assertEqual([i.get("purpose") for i in m["icons"]].count("maskable"), 1)
        for icon in m["icons"]:
            self.assertTrue((self.out / icon["src"]).is_file(), icon["src"])
        sw = (self.out / "index.service.worker.js").read_text()
        version = changelog.godot_version((ROOT / "project.godot").read_text())
        self.assertIn(f"const VERSION = '{version}';", sw, "캐시 이름에 게임 버전")
        files = json.loads(sw.split("const FILES = ")[1].split(";\n")[0])
        self.assertEqual(files, ["index.apple-touch-icon.png", "index.html", "index.js", "index.manifest.json", "index.pck", "index.wasm", "music/a.ogg", "music/b.ogg"],
                         "맨 위 파일 + 음악, 서비스 워커·오프라인 페이지·licenses/·pwa/ 그림은 뺌")

    def test_Godot_PWA_결과가_없으면_실패(self):
        (self.out / "index.manifest.json").unlink()
        self.assertEqual(pwa_build.main([str(self.out)]), 1)

    def test_셸의_시작_화면_목록과_그림이_같음(self):
        shell = (ROOT / "web" / "shell.html").read_text()
        for png in (ROOT / "web" / "pwa").glob("startup_*.png"):
            self.assertIn("pwa/" + png.name, shell)
        self.assertEqual(shell.count("apple-touch-startup-image"), len(list((ROOT / "web" / "pwa").glob("startup_*.png"))))

    @unittest.skipUnless(shutil.which("node"), "node 없음")
    def test_서비스_워커_문법(self):
        pwa_build.main([str(self.out)])
        subprocess.run(["node", "--check", str(self.out / "index.service.worker.js")], check=True)


if __name__ == "__main__":
    unittest.main()
