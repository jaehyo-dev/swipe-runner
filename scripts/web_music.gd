class_name WebMusic
extends RefCounted
## 웹의 음악 재생. 엔진 샘플 재생은 곡을 표본 단위로 이어 줄 수 없고(반복 틈 5~27ms, 재생 위치 1초 지연) 곡을 한 번에 디코딩해 프레임이 막힌다.
## 그래서 Web Audio 노드를 직접 다룬다: 곡을 프레임마다 조금씩 디코딩해 AudioBuffer에 채우고, 경계 시각에 start(when)/stop(when)으로 잇는다.
## 브라우저 decodeAudioData는 쓰지 않는다: 오래된 Safari는 Vorbis를 못 푼다.
## 엔진의 AudioContext는 export_presets.cfg의 html/head_include가 window.gameAudioCtx로 남겨 둔다.
## v0.11.2 head_include: 휴대폰은 출력 버퍼를 20ms(latencyHint 0.02)로 조금 늘린다(오디오 스레드가 잠깐 밀려도 버틴다. 늘어난 지연은 position()이 빼고,
## 보고하지 않는 브라우저여도 20ms 안). 엔진이 효과음마다 붙이는 위치 워클릿(128표본마다 메시지)은 게임이 쓰지 않아 빈 노드로 바꾼다.
## 메모리(아이폰 대비): 곡마다 실제로 쓸 4마디 구간만 푼다. 들고 있는 것은 재시작용 첫 곡과 다음 곡뿐이고, 지금 곡은 재생 노드가 붙들고 있다가 끝나면 사라진다.

const CHUNK_FRAMES := 2048
## 한 프레임에 디코딩에 쓰는 시간 (마이크로초). 느린 기기는 더 오래 걸릴 뿐 프레임이 막히지 않는다.
const SLICE_USEC := 3000
const CHUNKS_MAX := 5000
const TAIL := 0.02  # 구간 뒤에 더 푸는 시간(초): 경계에서 다음 곡과 겹치는 동안 앞 곡이 이어진다

const JS := """
window.gameMusic = (() => {
  const c = window.gameAudioCtx, out = c.createGain(), bufs = {}, ends = {}, filled = {};
  out.connect(c.destination);
  let run = null, t0 = 0, cur = null, unloops = [], top = -Infinity, stampOk = false, held = false, fading = [];
  // v0.11.3 일시정지: AudioContext는 재우지 않는다 (아이폰 WebKit은 suspend → resume 뒤 출력 지연이 바뀌어 음악·효과음이 밀린다).
  // 곡 노드만 세우고 멈춘 자리를 기억했다가, 이어 할 때 그 자리부터 정확한 시계 시각에 다시 예약하고 기준점 t0도 같은 만큼 옮긴다.
  let pausedAt = null, saved = [], resumeAt = null;  // 멈춘 자리를 내던 시계 값, 그때 살아 있던 노드와 위치, 다시 트는 시각
  // v0.11.1: 디코드한 묶음마다 새 배열을 만들지 않고 같은 바이트 배열을 다시 쓴다 (아이폰 WebKit 가비지 수집 멈춤 줄이기)
  let bytes = new Uint8Array(0), floats = new Float32Array(0);
  const lat = () => (c.baseLatency || 0) + (c.outputLatency || 0);
  // 노드 하나: 다시 만들 수 있게 버퍼·시작 시각·버퍼 안 위치·반복·페이드를 노드에 적어 둔다
  const source = (buf, end, gain, at, offset, loop) => {
    const s = c.createBufferSource();
    s.buffer = buf; s.loop = loop; s.loopEnd = end; s.fader = c.createGain();
    s.connect(s.fader); s.fader.connect(gain);
    Object.assign(s, { at, offset, looping: loop, unloopAt: null, end: Infinity, fadeIn: null, fadeOut: null, blend: 0 });
    s.start(at, offset);
    return s;
  };
  const fadeIn = (s, t, blend) => {
    s.fadeIn = t; s.blend = blend;
    s.fader.gain.setValueAtTime(0, t);
    s.fader.gain.linearRampToValueAtTime(1, t + blend);
  };
  const fadeOut = (s, t, blend) => {
    s.fadeOut = t; s.blend = blend; s.end = t + blend;
    s.fader.gain.setValueAtTime(1, t);
    s.fader.gain.linearRampToValueAtTime(0, t + blend);
    s.stop(t + blend);
  };
  // 시계 T에 노드가 읽고 있는 버퍼 안 위치(초). 반복은 0 ~ loopEnd(0이면 버퍼 끝)를 돈다. 반복을 끈 뒤로는 곧게 간다
  const pos = (s, T) => {
    const L = s.loopEnd || s.buffer.duration, u = s.unloopAt;
    if (!s.looping) return s.offset + T - s.at;
    if (u === null || T <= u) return (s.offset + T - s.at) % L;
    return (s.offset + u - s.at) % L + (T - u);
  };
  return {
    bufs,
    // loopEnd: 다음 곡이 제때 준비되지 못하면 이 구간을 한 번 더 돈다 (0이면 버퍼 전체)
    alloc(i, frames, rate, loopEnd) { bufs[i] = c.createBuffer(2, frames, rate); ends[i] = loopEnd; filled[i] = 0; },
    drop(i) { delete bufs[i]; },
    feed(i, data) {
      const raw = atob(data), n = raw.length;
      if (bytes.length < n) { bytes = new Uint8Array(n); floats = new Float32Array(bytes.buffer); }
      for (let k = 0; k < n; k++) bytes[k] = raw.charCodeAt(k);
      const frames = n / 8, l = bufs[i].getChannelData(0), r = bufs[i].getChannelData(1), at = filled[i];
      for (let k = 0; k < frames; k++) { l[at + k] = floats[2 * k]; r[at + k] = floats[2 * k + 1]; }
      filled[i] = at + frames;
    },
    // 판을 시작한다. fade초 동안 이전 판의 곡과 겹치며 넘어간다 (예약돼 있던 다음 곡도 같이 사라진다)
    play(i, fade) {
      const now = c.currentTime + 0.02, next = c.createGain();  // 약간 앞: 읽는 사이 오디오 스레드가 지나가도 시작 시각이 어긋나지 않게
      next.connect(out);
      fading = [];
      if (run && fade > 0) {
        run.gain.gain.setValueAtTime(1, now);
        run.gain.gain.linearRampToValueAtTime(0, now + fade);
        next.gain.setValueAtTime(0, now);
        next.gain.linearRampToValueAtTime(1, now + fade);
        run.sources.forEach(s => s.stop(now + fade));
        fading = run.sources;
      } else if (run) {
        run.sources.forEach(s => s.stop(now));
      }
      cur = source(bufs[i], ends[i], next, now, 0, true);
      run = { gain: next, sources: [cur] };
      unloops = [];
      pausedAt = null; saved = []; resumeAt = null; held = false;
      t0 = now;
      window.musicStart = performance.now() + 1000 * (now - c.currentTime);
      c.resume();
    },
    // at: 판 시작 뒤 시각 (4마디 경계). 그 표본에 다음 곡을 버퍼 안 offset초부터 시작한다. 두 곡의 파형 값이 달라 딸깍 소리가 나지 않게 짧게 겹친다 (앞 곡은 구간 뒤 꼬리로 이어진다)
    schedule(i, at, blend, offset) {
      const t = t0 + at, leaving = cur;
      // 마지막 바퀴의 가운데에서 반복을 끈다: 경계가 미뤄졌으면 지금 끄면 첫 바퀴에서 소리가 끝난다. 끄고 나면 구간 뒤 꼬리로 이어진다
      // 오디오 시계로 잰다 (setTimeout은 일시정지 동안에도 흘러 너무 일찍 끈다): tick이 프레임마다 확인한다
      unloops.push({ s: leaving, at: t - leaving.loopEnd * 0.5 });
      fadeOut(cur, t, blend);
      const next = source(bufs[i], ends[i], run.gain, t, offset, true);
      fadeIn(next, t, blend);
      run.sources = run.sources.filter(s => s === cur);  // 이미 끝난 곡을 붙들지 않는다
      run.sources.push(next);
      cur = next;
    },
    tick() {
      if (unloops.length) unloops = unloops.filter(u => { if (c.currentTime < u.at) return true; u.s.loop = false; u.s.unloopAt = c.currentTime; return false; });
      if (held || c.state !== 'running' || !c.getOutputTimestamp) { stampOk = false; return; }
      const s = c.getOutputTimestamp();
      if (s.performanceTime > 0) top = Math.max(top, s.contextTime * 1000 - s.performanceTime);
    },
    // v0.11.2 끊김 추정(AudioGapMeter): 지난 호출 뒤 (오디오 출력 시각 − 실제 시각)의 최댓값(ms). 멈춤이 끼었거나 값이 없으면 null
    peak() { const p = stampOk && top > -Infinity ? top : null; top = -Infinity; stampOk = true; return p; },
    info() { return c.sampleRate + ',' + lat(); },
    position() { return c.currentTime - t0 - lat(); },
    // 지금 귀에 들리는 오디오 시계(초). 3·2·1을 이 시계로 센다
    now() { return c.currentTime - lat(); },
    // 일시정지: 곡 노드를 지금 세우고 멈춘 자리를 기억한다. 다시 틀기를 예약해 둔 숫자 세기 중이면 그 예약을 거두고 멈춘 자리는 그대로 둔다
    // 풀기(on = false): 다시 틀기를 예약하지 않고 풀면(HOME 등) 바로 이어 튼다
    // at: 멈출 판 시간(초, position과 같은 기준). 화면이 멈춘 음악 시간을 넘기면 이어 할 때 화면과 소리가 같은 자리에서 출발한다. 없으면 지금 들리는 자리
    hold(on, at) {
      if (!on) { if (pausedAt !== null) this.resumeIn(0); held = false; return; }
      held = true;
      if (pausedAt !== null) return;
      // 출력 버퍼에 남은 몇십 ms는 이어 할 때 다시 들린다
      const heard = at === undefined || at === null ? c.currentTime - lat() : t0 + at;
      pausedAt = resumeAt !== null && resumeAt > heard ? resumeAt : heard;
      resumeAt = null;
      fading.forEach(s => s.stop()); fading = [];
      if (!run) return;
      saved = run.sources.filter(s => s.end > pausedAt).map(s => ({ s, p: s.at <= pausedAt ? pos(s, pausedAt) : null }));
      run.sources.forEach(s => s.stop());
    },
    // 이어 하기: 들리는 시계로 delay초 뒤에 멈춘 자리부터 다시 들리게 예약한다. 숫자 세기의 시작 시각(now 기준)을 돌려준다
    resumeIn(delay) {
      c.resume();  // 탭 전환 때 브라우저가 재웠으면 깨운다
      const now = c.currentTime, R = Math.max(now + 0.01, now - lat() + delay);
      if (pausedAt === null) return now - lat();
      const shift = R - pausedAt, made = new Map();
      if (run) {
        run.sources = saved.map(({ s, p }) => {
          const n = source(s.buffer, s.loopEnd, run.gain, p === null ? s.at + shift : R, p === null ? s.offset : p, s.loop);
          if (s.fadeIn !== null && s.fadeIn > pausedAt) fadeIn(n, s.fadeIn + shift, s.blend);
          if (s.fadeOut !== null) fadeOut(n, Math.max(s.fadeOut + shift, R), s.blend);
          made.set(s, n);
          return n;
        });
        cur = made.get(cur) || cur;
        unloops = unloops.filter(u => made.has(u.s)).map(u => ({ s: made.get(u.s), at: u.at + shift }));
        t0 += shift;
        window.musicStart += 1000 * shift;
      }
      pausedAt = null; saved = []; resumeAt = R;
      return R - delay;
    },
    running() { return !held && c.state === 'running'; },
    setDb(db) { out.gain.setTargetAtTime(Math.pow(10, db / 20), c.currentTime, 0.01); },
  };
})();
"""

var _js: JavaScriptObject
var _first: int          # 재시작 때 바로 틀어야 하는 곡: 버리지 않는다
var _have := {}          # 단계 -> 풀어 둔 구간의 곡 안 시작 위치(초)
var _job_step := -1      # 지금 푸는 곡
var _job_from := 0.0
var _playback: AudioStreamPlayback
var _left := 0


func _init(start_step: int) -> void:
	JavaScriptBridge.eval(JS, true)
	_js = JavaScriptBridge.get_interface("gameMusic")
	_first = start_step
	want(start_step, 0.0)
	# 첫 곡은 첫 입력에 바로 나와야 하므로 가림막 뒤(로딩 중)에 끝낸다. 아직 받지 못한 곡(개발용 ?bpm)은 받은 뒤 프레임마다 푼다
	for i in (CHUNKS_MAX if _playback else 0):  # 횟수 제한: 안에서 오류가 나도 페이지가 멈추지 않게
		if is_ready(start_step, 0.0):
			break
		decode_slice()


## 맨 위 단계는 경계 없이 곡 전체를 돌므로 처음부터 한 바퀴를 푼다
static func _is_top(step: int) -> bool:
	return step == MusicLadder.STEPS.size() - 1


static func _key(step: int, from: float) -> float:
	return 0.0 if _is_top(step) else from


func is_ready(step: int, from: float) -> bool:
	return _have.has(step) and is_equal_approx(_have[step], _key(step, from))


## 이 곡의 from초 위치 구간을 풀어 둔다. 첫 곡이 아닌 다른 곡은 버린다.
func want(step: int, from: float) -> void:
	if not AudioManager.has_track(step):  # 아직 받는 중: 받으면 다음 프레임에 다시 불린다
		return
	if is_ready(step, from) or (_job_step == step and is_equal_approx(_job_from, _key(step, from))):
		return
	for held: int in _have.keys():
		if held != _first:
			_js.drop(held)
			_have.erase(held)
	if _job_step >= 0 and _job_step != _first:  # 풀다 만 곡도 들고 있지 않는다
		_js.drop(_job_step)
	var rate := AudioServer.get_mix_rate()
	var span := MusicLadder.lap_time(step) if _is_top(step) else MusicLadder.span_time(step)
	_left = roundi(span * rate) + (0 if _is_top(step) else roundi(TAIL * rate))
	_js.alloc(step, _left, rate, 0.0 if _is_top(step) else span)
	_job_step = step
	_job_from = _key(step, from)
	_playback = AudioManager.open_track(AudioManager.tracks[step], _job_from)


## 프레임마다 부른다. 지금 곡을 budget 마이크로초만큼 디코딩한다.
func decode_slice(budget := SLICE_USEC) -> void:
	_js.tick()
	var from := Time.get_ticks_usec()
	while _playback != null and Time.get_ticks_usec() - from < budget:
		var n := mini(CHUNK_FRAMES, _left)
		_js.feed(_job_step, Marshalls.raw_to_base64(_playback.mix_audio(1.0, n).to_byte_array()))
		_left -= n
		if _left == 0:
			_have[_job_step] = _job_from
			_job_step = -1
			_playback = null


func play(step: int, fade: float) -> void:
	_js.play(step, fade)


## from: 곡 안 위치(초). 버퍼는 구간 시작부터 들어 있으므로 그만큼 뺀다.
func schedule(step: int, at: float, from: float) -> void:
	_js.schedule(step, at, AudioManager.SWITCH_BLEND, from - _have[step])


func position() -> float:
	return float(_js.position())


## at: 멈출 판 시간(초, position 기준). 화면이 멈춘 음악 시간
func hold(on: bool, at: float) -> void:
	_js.hold(on, at)


## 이어 하기: 들리는 시계로 delay초 뒤 멈춘 자리부터 다시 들리게 예약한다. 숫자 세기 시작 시각(now 기준)
func resume_in(delay: float) -> float:
	return float(_js.resumeIn(delay))


## 지금 귀에 들리는 오디오 시계(초)
func now() -> float:
	return float(_js.now())


func running() -> bool:
	return bool(_js.running())


## 지난 호출 뒤 출력 시계 최댓값(ms) 또는 null (AudioGapMeter.push)
func peak() -> Variant:
	return _js.peak()


## [출력 표본율 Hz, 출력 지연 초]
func info() -> PackedFloat64Array:
	var parts := str(_js.info()).split(",")
	return PackedFloat64Array([parts[0].to_float(), parts[1].to_float()])


func set_db(db: float) -> void:
	_js.setDb(db)
