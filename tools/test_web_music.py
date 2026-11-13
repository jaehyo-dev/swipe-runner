"""웹 음악 JS(scripts/web_music.gd의 JS)의 일시정지·이어 하기를 가짜 AudioContext로 확인한다 (v0.11.3).

브라우저 없이 Node로 시계를 직접 움직인다. 확인: 이어 하기 뒤 재생 위치가 멈춘 자리에서 그대로 이어지는가(기준점 t0 갱신),
곡 경계 예약·반복 끄기도 같은 만큼 밀리는가, 숫자 세는 중 다시 멈춰도 자리가 그대로인가, 10번 반복해도 어긋남이 쌓이지 않는가.
"""
import json
import pathlib
import re
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

HARNESS = r"""
class Param { constructor() { this.ev = []; } setValueAtTime(v, t) { this.ev.push(['set', v, t]); } linearRampToValueAtTime(v, t) { this.ev.push(['ramp', v, t]); } setTargetAtTime() {} }
const made = [];
const ctx = {
  currentTime: 10, baseLatency: 0.02, outputLatency: 0.03, state: 'running', sampleRate: 48000, destination: {}, resumes: 0,
  createGain() { return { gain: new Param(), connect() {} }; },
  createBufferSource() { const s = { connect() {}, start(w, o) { this.started = [w, o]; }, stop(t) { this.stopped = t === undefined ? ctx.currentTime : t; } }; made.push(s); return s; },
  createBuffer(ch, frames, rate) { return { duration: frames / rate, getChannelData() { return new Float32Array(1); } }; },
  resume() { this.resumes++; return Promise.resolve(); },
};
globalThis.window = { gameAudioCtx: ctx };
globalThis.performance = { now: () => 0 };
eval(JS);
const m = window.gameMusic, out = {};
const lat = 0.05, live = () => made.filter(s => s.stopped === undefined);
m.alloc(0, 48000 * 10, 48000, 4.0);  // 4초 구간 반복(뒤 꼬리 포함 10초 버퍼)
m.alloc(1, 48000 * 10, 48000, 3.0);
m.play(0, 0);                          // t0 = 10.02
ctx.currentTime = 15.02 + lat;         // 들리는 위치 5초
out.before = m.position();
m.hold(true);
out.liveAfterHold = live().length;
ctx.currentTime = 40;                  // 일시정지 동안 시계는 흐른다 (재우지 않는다)
const start = m.resumeIn(1.5);
out.countStart = start; out.now = m.now();
const src = made[made.length - 1];
out.restart = src.started;             // [다시 트는 시각, 버퍼 안 위치]
ctx.currentTime = src.started[0] + lat; // 다시 튼 소리가 귀에 닿는 순간
out.after = m.position();
out.heardAt = m.now();

// 곡 경계 예약 뒤 멈춤: 다음 곡 시작·앞 곡 끄기·반복 끄기가 같은 만큼 밀린다
m.schedule(1, 12.0, 0.005, 0.5);        // 판 시작 뒤 12초에 곡 1을 0.5초 자리부터
const t0 = ctx.currentTime - lat - m.position();
out.edgeBefore = 12.0 - (ctx.currentTime - lat - t0);  // 지금부터 경계까지 들리는 시간
ctx.currentTime += 1.0;
m.hold(true);
ctx.currentTime += 20;
m.resumeIn(0.8);
const [a, b] = made.slice(-2);
out.edgeAfter = b.started[0] - a.started[0];           // 다시 튼 순간 → 다음 곡 시작
out.edgeOffset = b.started[1];
out.leavingStop = a.stopped === undefined ? null : a.stopped - a.started[0];

// 숫자 세는 중 다시 멈추면 자리가 그대로
ctx.currentTime = a.started[0] - 0.3;
const p0 = m.position();
m.hold(true);
ctx.currentTime += 5;
m.resumeIn(1.0);
const c = made[made.length - 2];
ctx.currentTime = c.started[0] + lat;
out.repause = [a.started[1], c.started[1]];

// 10번 반복: 매번 멈춘 자리와 이어 한 자리가 같다
out.drift = [];
for (let k = 0; k < 10; k++) {
  ctx.currentTime += 0.37;
  const p = m.position();
  m.hold(true);
  ctx.currentTime += 3 + k;
  ctx.currentTime = m.resumeIn(0.9) + 0.9 + lat;  // 숫자가 끝나 음악이 다시 들리는 순간
  out.drift.push(m.position() - p);
}
// 화면이 멈춘 판 시간을 넘기면 그 자리에서 멈추고 그 자리부터 이어진다 (화면과 소리가 같은 자리)
ctx.currentTime += 0.5;
const want = m.position() - 0.017;
m.hold(true, want);
ctx.currentTime += 4;
ctx.currentTime = m.resumeIn(0.9) + 0.9 + lat;
out.atPause = m.position() - want;
// 다시 틀기를 예약하지 않고 풀면(HOME) 바로 이어 튼다
m.hold(true);
const n = made.length;
m.hold(false);
out.releaseStarts = made.length > n;
out.running = m.running();
console.log(JSON.stringify(out));
"""


def web_music_js() -> str:
    text = (ROOT / "scripts" / "web_music.gd").read_text(encoding="utf-8")
    return re.search(r'const JS := """\n(.*?)"""', text, re.S).group(1)


@unittest.skipUnless(shutil.which("node"), "node 없음")
class WebMusicPauseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        script = "const JS = " + json.dumps(web_music_js()) + ";\n" + HARNESS
        done = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True)
        cls.r = json.loads(done.stdout)

    def test_이어_하면_멈춘_자리부터_들린다(self) -> None:
        r = self.r
        self.assertAlmostEqual(r["before"], 5.0, places=6)
        self.assertEqual(r["liveAfterHold"], 0, "멈추면 곡 노드가 모두 선다")
        self.assertAlmostEqual(r["restart"][1], 5.0 % 4.0, places=6, msg="4초 반복 안 1초 자리")
        self.assertAlmostEqual(r["after"], r["before"], places=6, msg="기준점 t0가 옮겨져 위치가 이어진다")

    def test_숫자_끝_시각_음악이_다시_들린다(self) -> None:
        r = self.r
        self.assertAlmostEqual(r["countStart"], r["now"], places=6)
        self.assertAlmostEqual(r["heardAt"] - r["countStart"], 1.5, places=6)

    def test_곡_경계와_반복_끄기도_같이_밀린다(self) -> None:
        r = self.r
        self.assertAlmostEqual(r["edgeAfter"], r["edgeBefore"] - 1.0, places=6, msg="멈추기 전 1초 흘렀으니 남은 시간만큼 뒤")
        self.assertAlmostEqual(r["edgeOffset"], 0.5, places=6)
        self.assertAlmostEqual(r["leavingStop"], r["edgeAfter"] + 0.005, places=6)

    def test_숫자_세는_중_다시_멈춰도_자리는_그대로(self) -> None:
        a, c = self.r["repause"]
        self.assertAlmostEqual(a, c, places=6)

    def test_10번_반복해도_어긋남이_쌓이지_않는다(self) -> None:
        for d in self.r["drift"]:
            self.assertLess(abs(d), 1e-6)

    def test_화면이_멈춘_시간을_넘기면_그_자리부터_이어진다(self) -> None:
        self.assertLess(abs(self.r["atPause"]), 1e-6)

    def test_예약_없이_풀면_바로_이어_튼다(self) -> None:
        self.assertTrue(self.r["releaseStarts"])
        self.assertTrue(self.r["running"])


if __name__ == "__main__":
    unittest.main()
