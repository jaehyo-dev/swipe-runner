class_name WebMusic
extends RefCounted
## 웹의 음악 재생. 엔진 샘플 재생은 곡을 표본 단위로 이어 줄 수 없고(반복 틈 5~27ms, 재생 위치 1초 지연) 곡을 한 번에 디코딩해 프레임이 막힌다.
## 그래서 Web Audio 노드를 직접 다룬다: 곡을 프레임마다 조금씩 디코딩해 AudioBuffer에 채우고, 경계 시각에 start(when)/stop(when)으로 잇는다.
## 브라우저 decodeAudioData는 쓰지 않는다: 오래된 Safari는 Vorbis를 못 푼다.
## 엔진의 AudioContext는 export_presets.cfg의 html/head_include가 window.gameAudioCtx로 남겨 둔다.

const CHUNK_FRAMES := 2048
## 한 프레임에 디코딩에 쓰는 시간 (마이크로초). 느린 기기는 더 오래 걸릴 뿐 프레임이 막히지 않는다.
const SLICE_USEC := 3000
const CHUNKS_MAX := 5000

const JS := """
window.gameMusic = (() => {
  const c = window.gameAudioCtx, out = c.createGain(), bufs = {}, filled = {};
  out.connect(c.destination);
  let run = null, t0 = 0, cur = null;
  const source = (i, gain) => {
    const s = c.createBufferSource();
    s.buffer = bufs[i]; s.loop = true; s.fader = c.createGain();
    s.connect(s.fader); s.fader.connect(gain);
    return s;
  };
  return {
    bufs,
    alloc(i, frames, rate) { bufs[i] = c.createBuffer(2, frames, rate); filled[i] = 0; },
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
    // at: 판 시작 뒤 시각 (곡 반복 끝). 그 표본에 다음 곡이 시작한다. 두 곡의 파형 값이 달라 딸깍 소리가 나지 않게 짧게 겹친다 (앞 곡은 반복된 앞머리가 이어진다)
    schedule(i, at, blend) {
      const next = source(i, run.gain), t = t0 + at;
      cur.fader.gain.setValueAtTime(1, t);
      cur.fader.gain.linearRampToValueAtTime(0, t + blend);
      next.fader.gain.setValueAtTime(0, t);
      next.fader.gain.linearRampToValueAtTime(1, t + blend);
      cur.stop(t + blend);
      next.start(t);
      run.sources.push(next);
      cur = next;
    },
    position() { return c.currentTime - t0 - c.baseLatency - (c.outputLatency || 0); },
    setDb(db) { out.gain.setTargetAtTime(Math.pow(10, db / 20), c.currentTime, 0.01); },
  };
})();
"""

var _js: JavaScriptObject
var _steps: Array[int] = []  # 디코딩할 단계들, 앞에서부터
var _ready := {}
var _playback: AudioStreamPlayback
var _left := 0
var _tracks: Array


func _init(tracks: Array, start_step: int) -> void:
	JavaScriptBridge.eval(JS, true)
	_js = JavaScriptBridge.get_interface("gameMusic")
	_tracks = tracks
	for step in range(start_step, tracks.size()):
		_steps.append(step)
	# 첫 곡은 첫 입력에 바로 나와야 하므로 가림막 뒤(로딩 중)에 끝낸다
	for i in CHUNKS_MAX:  # 횟수 제한: 안에서 오류가 나도 페이지가 멈추지 않게
		if is_ready(start_step):
			break
		decode_slice()


func is_ready(step: int) -> bool:
	return _ready.has(step)


## 프레임마다 부른다. 다음 곡들을 budget 마이크로초만큼 디코딩한다.
func decode_slice(budget := SLICE_USEC) -> void:
	var from := Time.get_ticks_usec()
	while not _steps.is_empty() and Time.get_ticks_usec() - from < budget:
		var step: int = _steps[0]
		if _playback == null:
			var rate := AudioServer.get_mix_rate()
			_left = roundi(MusicLadder.lap_time(step) * rate)
			_js.alloc(step, _left, rate)
			_playback = AudioManager.open_track(_tracks[step])
		var n := mini(CHUNK_FRAMES, _left)
		_js.feed(step, Marshalls.raw_to_base64(_playback.mix_audio(1.0, n).to_byte_array()))
		_left -= n
		if _left == 0:
			_ready[step] = true
			_playback = null
			_steps.pop_front()


func play(step: int, fade: float) -> void:
	_js.play(step, fade)


func schedule(step: int, at: float) -> void:
	_js.schedule(step, at, AudioManager.SWITCH_BLEND)


func position() -> float:
	return float(_js.position())


func set_db(db: float) -> void:
	_js.setDb(db)
