class_name WebMusic
extends RefCounted
## 웹의 음악 재생. 엔진 샘플 재생은 곡을 표본 단위로 이어 줄 수 없고(반복 틈 5~27ms, 재생 위치 1초 지연) 곡을 한 번에 디코딩해 프레임이 막힌다.
## 그래서 Web Audio 노드를 직접 다룬다: 곡을 프레임마다 조금씩 디코딩해 AudioBuffer에 채우고, 경계 시각에 start(when)/stop(when)으로 잇는다.
## 브라우저 decodeAudioData는 쓰지 않는다: 오래된 Safari는 Vorbis를 못 푼다.
## 엔진의 AudioContext는 export_presets.cfg의 html/head_include가 window.gameAudioCtx로 남겨 둔다.
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
  let run = null, t0 = 0, cur = null;
  const source = (i, gain) => {
    const s = c.createBufferSource();
    s.buffer = bufs[i]; s.loop = true; s.loopEnd = ends[i]; s.fader = c.createGain();
    s.connect(s.fader); s.fader.connect(gain);
    return s;
  };
  return {
    bufs,
    // loopEnd: 다음 곡이 제때 준비되지 못하면 이 구간을 한 번 더 돈다 (0이면 버퍼 전체)
    alloc(i, frames, rate, loopEnd) { bufs[i] = c.createBuffer(2, frames, rate); ends[i] = loopEnd; filled[i] = 0; },
    drop(i) { delete bufs[i]; },
    feed(i, data) {
      const raw = atob(data), bytes = new Uint8Array(raw.length);
      for (let k = 0; k < raw.length; k++) bytes[k] = raw.charCodeAt(k);
      const f = new Float32Array(bytes.buffer), l = bufs[i].getChannelData(0), r = bufs[i].getChannelData(1), at = filled[i];
      for (let k = 0; k < f.length / 2; k++) { l[at + k] = f[2 * k]; r[at + k] = f[2 * k + 1]; }
      filled[i] = at + f.length / 2;
    },
    // 판을 시작한다. fade초 동안 이전 판의 곡과 겹치며 넘어간다 (예약돼 있던 다음 곡도 같이 사라진다)
    play(i, fade) {
      const now = c.currentTime + 0.02, next = c.createGain();  // 약간 앞: 읽는 사이 오디오 스레드가 지나가도 시작 시각이 어긋나지 않게
      next.connect(out);
      if (run && fade > 0) {
        run.gain.gain.setValueAtTime(1, now);
        run.gain.gain.linearRampToValueAtTime(0, now + fade);
        next.gain.setValueAtTime(0, now);
        next.gain.linearRampToValueAtTime(1, now + fade);
        run.sources.forEach(s => s.stop(now + fade));
      } else if (run) {
        run.sources.forEach(s => s.stop(now));
      }
      cur = source(i, next);
      run = { gain: next, sources: [cur] };
      t0 = now;
      cur.start(now);
      window.musicStart = performance.now() + 1000 * (now - c.currentTime);
      c.resume();
    },
    // at: 판 시작 뒤 시각 (4마디 경계). 그 표본에 다음 곡을 버퍼 안 offset초부터 시작한다. 두 곡의 파형 값이 달라 딸깍 소리가 나지 않게 짧게 겹친다 (앞 곡은 구간 뒤 꼬리로 이어진다)
    schedule(i, at, blend, offset) {
      const next = source(i, run.gain), t = t0 + at, leaving = cur;
      // 마지막 바퀴의 가운데에서 반복을 끈다: 경계가 미뤄졌으면 지금 끄면 첫 바퀴에서 소리가 끝난다. 끄고 나면 구간 뒤 꼬리로 이어진다
      setTimeout(() => { leaving.loop = false; }, Math.max(0, t - leaving.loopEnd * 0.5 - c.currentTime) * 1000);
      cur.fader.gain.setValueAtTime(1, t);
      cur.fader.gain.linearRampToValueAtTime(0, t + blend);
      next.fader.gain.setValueAtTime(0, t);
      next.fader.gain.linearRampToValueAtTime(1, t + blend);
      cur.stop(t + blend);
      next.start(t, offset);
      run.sources = run.sources.filter(s => s === cur);  // 이미 끝난 곡을 붙들지 않는다
      run.sources.push(next);
      cur = next;
    },
    position() { return c.currentTime - t0 - c.baseLatency - (c.outputLatency || 0); },
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
	# 첫 곡은 첫 입력에 바로 나와야 하므로 가림막 뒤(로딩 중)에 끝낸다
	for i in CHUNKS_MAX:  # 횟수 제한: 안에서 오류가 나도 페이지가 멈추지 않게
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
	_playback = AudioManager.open_track(AudioManager.TRACKS[step], _job_from)


## 프레임마다 부른다. 지금 곡을 budget 마이크로초만큼 디코딩한다.
func decode_slice(budget := SLICE_USEC) -> void:
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


func set_db(db: float) -> void:
	_js.setDb(db)
