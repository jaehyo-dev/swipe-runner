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
        (self.out / "versions" / "v0.11.3").mkdir(parents=True)  # 배포 사이트의 옛 버전 (v0.12.1: 저장·가로채기 모두 제외)
        (self.out / "versions" / "v0.11.3" / "index.html").write_text("x")

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
                         "맨 위 파일 + 음악, 서비스 워커·오프라인 페이지·licenses/·pwa/ 그림·versions/는 뺌")

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

    @unittest.skipUnless(shutil.which("node"), "node 없음")
    def test_서비스_워커는_versions_요청을_가로채지_않음(self):
        """sw.js를 가짜 서비스 워커 환경에서 돌려, 어떤 요청에 respondWith를 부르는지 본다 (v0.12.1)"""
        pwa_build.main([str(self.out)])
        harness = """
const handlers = {}, base = 'https://x.github.io/swipe-runner/';
globalThis.self = { location: base + 'index.service.worker.js', registration: {}, clients: {}, addEventListener: (k, f) => { handlers[k] = f; } };
globalThis.caches = { open: async () => ({ match: async () => null }) };
globalThis.fetch = async () => null;  // 캐시에 없으면 네트워크로: 여기서는 아무것도 받지 않는다
require(process.argv[1]);  // node -e 뒤 인자는 argv[1]부터
const out = {};
for (const path of process.argv.slice(2)) {
  let hit = false;
  handlers.fetch({ request: { method: 'GET', url: base + path, mode: path.endsWith('/') || path === '' ? 'navigate' : 'no-cors' }, respondWith: () => { hit = true; } });
  out[path] = hit;
}
console.log(JSON.stringify(out));
"""
        paths = ["", "index.wasm", "music/a.ogg", "versions/", "versions/v0.11.3/", "versions/v0.11.3/index.html", "versions/v0.11.3/index.wasm", "licenses/x.txt"]
        run = subprocess.run(["node", "-e", harness, str(self.out / "index.service.worker.js"), *paths], check=True, capture_output=True, text=True)
        hit = json.loads(run.stdout)
        self.assertEqual([p for p in paths if hit[p]], ["", "index.wasm", "music/a.ogg"], "지금 버전 파일만 캐시에서, versions/·licenses/는 네트워크 그대로")


if __name__ == "__main__":
    unittest.main()
