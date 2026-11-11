extends Node
## 화면 확인 기록용 자동 플레이 (웹 빌드에 들어가지 않음). 결과는 RESULT 줄로 찍는다.
##   박자 측정: godot --path . res://tools/playthrough.tscn -- accuracy 265  (100BPM부터 130BPM 두 바퀴까지 약 265초)
##   녹화: godot --path . --write-movie x.avi --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- clean 66 all 105
##     (clean = 안 부딪힘, movie = 12초쯤 일부러 부딪힘. 세 번째 값 Music|SFX면 그 버스만 들림, 네 번째 값은 시작 BPM)
##   환경 변수 BEST=숫자: 예전 최고 기록을 이 값으로 두고 시작 (새 기록 장면 녹화), SEED=숫자: 장애물 배치
##   사람 모델이 죽을 때까지: godot ... res://tools/playthrough.tscn -- human 300 all 100  (죽고 3초 뒤 끝). 환경 변수 MODEL=good이면 잘하는 모델, greedy면 욕심쟁이
##   음악 시계 시작 기록: 웹 주소에 ?mode=startup&secs=4 (첫 탭 뒤 프레임마다 재생 위치와 음악 시간)
## 웹 측정은 주소에 ?mode=accuracy&secs=265 (시작 BPM은 &bpm=115)

const SEED := 143  # 첫 장애물부터 허들·막대가 내 레인에 온다
const HUMAN_LINGER := 3.0  # human: 죽은 뒤 보여 주는 시간
const Dir := SwipeDetector.Dir
const FIRST_TAP := 0.5
const MOVIE_FIRST_TAP := 1.5  # 녹화는 시작 대기 화면을 보여 준다
const SEEK_AT := 12.0     # 녹화: 이 시각부터 장애물 쪽으로 가서 일부러 부딪힌다
const RESTART_AFTER := 0.7

var mode := "accuracy"
var secs := 180.0
var main: Node3D
var t := 0.0
var frame := 0
var _crash_t := -1.0
var _seek := false
var _start_usec := 0
var _last_z := {}      # id -> [z, 벽시계 초]
var _frame_err: Array[float] = []    # 도착 프레임의 음악 시간 - 가장 가까운 박
var _wall_err: Array[float] = []     # 벽시계로 보간한 도착 시각 - 박 격자
var _by_bpm := {}      # BPM -> {frame: [...], wall: [...]}. 도착한 박의 BPM별 오차
var _cross := {"frame": [], "wall": []}  # 경계를 넘어 도착한 장애물만
var _rows := {"frame": [], "wall": []}   # 박 물방울 줄이 주인공 자리에 닿은 시각 - 그 박
var _last_row := []    # [물방울 노드 z, 벽시계 초]
var _draws: Array[int] = []       # 프레임별 그리는 횟수
var _prims: Array[int] = []
var _born_step := {}   # id -> 처음 보였을 때의 사다리 단계
var _slow_frames := 0  # 33ms 넘는 프레임
var _wall_zero := INF
var _deltas: Array[float] = []
var _clock_steps: Array[float] = []  # 프레임마다 음악 시간이 간 양 - 프레임 시간 (세상 움직임의 들쭉날쭉함)
var _last_music := 0.0
var _force_slip := false  # ?off=slip: 음악 5~6.7초 동안 다음 곡 예약을 막아 경계를 4마디 미룬다 (review/v0.5.1/measure_slip.mjs)
var _max_time := 0.0
var _crashes := 0
var _input_usec := 0
var _input_frame := -1
var _input_name := ""
var events: Array[Dictionary] = []
var _gaps: Array[int] = []
var _trace := []  # startup: [탭 뒤 벽시계 ms, 재생 위치 ms, 음악 시간 ms]
var _tap_usec := 0
var _perf_to_now := 0.0  # 웹: performance.now 초에서 이 값을 빼면 _now() 기준이 된다
var _human: HumanPlayer
var _last_input := -INF


func _ready() -> void:
	process_priority = 100  # main이 이번 프레임의 z를 계산한 뒤에 잰다
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		mode = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mode') || 'accuracy'"))
		secs = float(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('secs') || 180")))
	elif args.size() >= 2:
		mode = args[0]
		secs = float(args[1])
	if args.size() >= 3 and args[2] in ["Music", "SFX"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX" if args[2] == "Music" else &"Music"), true)
	if args.size() >= 4:
		AudioManager.start_step = MusicLadder.step_of_bpm(int(args[3]))
		AudioManager.ladder = MusicLadder.new(AudioManager.start_step)
	if mode == "accuracy" and not OS.has_feature("web"):
		AudioServer.set_bus_mute(0, true)  # 3분 동안 소리가 나지 않게. 믹스와 재생 위치는 그대로 돈다
	main = load("res://scenes/main.tscn").instantiate()
	main.seed_value = int(OS.get_environment("SEED")) if OS.has_environment("SEED") else SEED
	if mode == "human":
		var models := {"good": HumanPlayer.GOOD, "greedy": HumanPlayer.GREEDY}
		_human = HumanPlayer.new(main.seed_value, models.get(OS.get_environment("MODEL"), HumanPlayer.NORMAL))
	main.best_path = "user://playthrough_best.txt"
	if not OS.get_environment("BEST").is_empty():
		var file := FileAccess.open(main.best_path, FileAccess.WRITE)
		file.store_string(OS.get_environment("BEST"))
		file.close()
	else:
		DirAccess.remove_absolute(main.best_path)
	add_child(main)
	_apply_measure_switches()
	AudioManager.played.connect(_on_played)
	_start_usec = Time.get_ticks_usec()
	if OS.has_feature("web"):
		_perf_to_now = float(JavaScriptBridge.eval("performance.now()")) / 1000.0


## 렉 측정: 주소의 ?off=msaa,glow,mirror,sky,drops,hero,streak 로 효과를 끄고 ?scale=0.7 로 3D 해상도를 바꿔 효과별 비용을 잰다 (review/v0.5.1/perf_mac.md)
func _apply_measure_switches() -> void:
	if not OS.has_feature("web"):
		return
	var off := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('off') || ''")).split(",")
	if bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('quiet')")):
		AudioManager.set_muted(true)  # 스피커로 소리를 내지 않되 AudioContext는 실제 장치로 돈다 (판이 바뀌어도 끈 채로)
	var scale := float(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('scale') || 0")))
	if "msaa" in off:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if "glow" in off:
		main._env.glow_enabled = false
	if "sky" in off:
		main.get_node("Sky").visible = false
	if "drops" in off:
		main._dashes.visible = false
	if "streak" in off:
		main.get_node("Streaks").visible = false
	if "hero" in off:
		main.runner.visible = false
	if "mirror" in off:
		for kind in main._kind_meshes:
			main._kind_meshes[kind]["reflect"].set_shader_parameter("reflect_on", 0.0)
		main.runner.set_reflection(false)
	if scale > 0.0:
		get_viewport().scaling_3d_scale = scale
	_force_slip = "slip" in off
	if "guard" in off:  # 비용을 잴 때는 자동 낮춤이 끼어들지 않게 한다
		main._quality.level = QualityGuard.LEVELS


## 기록 시각(초). 녹화는 실제 시간과 무관하게 프레임 단위로 흐르므로 게임 시간을 쓴다.
func _now() -> float:
	if _recording():
		return t
	return (Time.get_ticks_usec() - _start_usec) / 1000000.0


func _recording() -> bool:
	return mode == "movie" or mode == "clean" or mode == "human"


func _on_played(sound: StringName, pitch: float) -> void:
	var usec := Time.get_ticks_usec()
	var row := {"type": "sound", "sound": String(sound), "at": _now(), "frame": frame, "pitch": snappedf(pitch, 0.001), "music": AudioManager.music_time}
	if _input_frame == frame:
		row["from_input"] = _input_name
		row["gap_usec"] = usec - _input_usec
		_gaps.append(usec - _input_usec)
	events.append(row)


## 진짜 입력 경로(뷰포트 → main._input)로 스와이프를 넣는다
func _swipe(dir: int) -> void:
	var from := Vector2(360, 700)
	var offset: Vector2 = {Dir.LEFT: Vector2(-120, 0), Dir.RIGHT: Vector2(120, 0), Dir.UP: Vector2(0, -120), Dir.DOWN: Vector2(0, 120)}[dir]
	var press := InputEventScreenTouch.new()
	press.position = from
	press.pressed = true
	get_viewport().push_input(press)
	_mark_input(SwipeDetector.Dir.keys()[dir])  # 임계 거리를 넘는 드래그가 들어가는 순간
	var drag := InputEventScreenDrag.new()
	drag.position = from + offset
	get_viewport().push_input(drag)
	var release := InputEventScreenTouch.new()
	release.position = from + offset
	release.pressed = false
	get_viewport().push_input(release)


func _tap(label: String) -> void:
	_mark_input(label)
	var press := InputEventScreenTouch.new()
	press.position = Vector2(360, 700)
	press.pressed = true
	get_viewport().push_input(press)
	var release := InputEventScreenTouch.new()
	release.position = press.position
	release.pressed = false
	get_viewport().push_input(release)


func _mark_input(label: String) -> void:
	_input_usec = Time.get_ticks_usec()
	_input_frame = frame
	_input_name = label
	events.append({"type": "input", "input": label, "at": _now(), "frame": frame, "music": AudioManager.music_time})


func _process(delta: float) -> void:
	frame += 1
	t += delta
	_deltas.append(delta)
	if delta > 0.033 and main.prewarmed:
		_slow_frames += 1
	_max_time = maxf(_max_time, AudioManager.music_time)
	if _force_slip:
		AudioManager._blocked = AudioManager.music_time >= 5.0 and AudioManager.music_time < 6.7
	if main.started and not main.dead:
		_clock_steps.append(absf(AudioManager.music_time - _last_music - delta))
	_last_music = AudioManager.music_time
	_record_arrivals()
	_record_rows()
	_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if not main.started:
		if t >= (MOVIE_FIRST_TAP if _recording() else FIRST_TAP):
			_tap("첫 탭")
			_tap_usec = Time.get_ticks_usec()
		return
	if mode == "startup":
		_trace.append([(Time.get_ticks_usec() - _tap_usec) / 1000, int(AudioManager._raw_position() * 1000.0), int(AudioManager.music_time * 1000.0)])
	if main.dead:
		if _crash_t < 0.0:
			_crash_t = t
			_crashes += 1
			events.append({"type": "crash", "at": _now(), "frame": frame, "music": AudioManager.music_time})
		elif mode == "human":
			if t - _crash_t >= HUMAN_LINGER:
				_finish()
			return
		elif t - _crash_t >= RESTART_AFTER:
			_crash_t = -1.0
			_seek = false
			_tap("다시 시작 탭")
	elif mode == "movie" and _crashes == 0 and t >= SEEK_AT:
		_seek = true
		_seek_lane()
	else:
		var dir: int
		var seen := RunSim.visible_items(main.field.items, AudioManager.ladder, AudioManager.music_time)  # 안개 속 줄은 모른다
		if _human:
			dir = _human.decide(AudioManager.music_time, seen, main.lane, main.player, main.speed, RunSim.visible_items(main.field.orbs, AudioManager.ladder, main._music_t))
		else:
			dir = AutoPlayer.decide(seen, main.lane, main.player, main.speed, t - _last_input)
		if dir != Dir.NONE:
			_last_input = t
			_swipe(dir)
	if t >= secs + (MOVIE_FIRST_TAP if _recording() else FIRST_TAP):
		_finish()


## 일부러 부딪히려고 다음 장애물의 레인으로 간다
func _seek_lane() -> void:
	for item: Dictionary in main.field.items:
		if item["z"] < -3.0 and item["z"] > -20.0:
			if item["lane"] != main.lane:
				_swipe(Dir.LEFT if item["lane"] < main.lane else Dir.RIGHT)
			return


func _record_arrivals() -> void:
	var wall := _now()
	if main.field == null or main.dead:
		_last_z.clear()
		return
	var ladder: MusicLadder = AudioManager.ladder
	var music: float = AudioManager.music_time
	for item: Dictionary in main.field.items:
		var id: int = item["id"]
		if not _born_step.has(id):
			_born_step[id] = ladder.segment_at(music)["step"]
		if _last_z.has(id) and _last_z[id][0] < 0.0 and item["z"] >= 0.0:
			var beat_t := ladder.time_of_beat(item["beat"])
			# 프레임 기준: 도착이 보인 첫 프레임의 음악 시간 - 그 박의 시각 (프레임 간격만큼 늦을 수 있다)
			var frame_err: float = music - beat_t
			_frame_err.append(frame_err)
			# 보간 기준: 두 프레임 사이에서 z가 0이 된 벽시계 시각. 음악 시작 시각 + 출력 지연에서 박까지 잰다 (음악 시계와 독립)
			var crossed: float = _last_z[id][1] + (wall - _last_z[id][1]) * (0.0 - _last_z[id][0]) / (item["z"] - _last_z[id][0])
			if _wall_zero == INF:
				_wall_zero = crossed - beat_t
				if OS.has_feature("web"):
					_wall_zero = float(JavaScriptBridge.eval("(window.musicStart + 1000 * (gameAudioCtx.baseLatency + (gameAudioCtx.outputLatency || 0))) / 1000")) - _perf_to_now
			var wall_err: float = crossed - (_wall_zero + beat_t)
			_wall_err.append(wall_err)
			var step: int = ladder.segment_at(beat_t)["step"]
			var bpm: int = MusicLadder.info(step)["bpm"]
			if not _by_bpm.has(bpm):
				_by_bpm[bpm] = {"frame": [], "wall": []}
			_by_bpm[bpm]["frame"].append(frame_err)
			_by_bpm[bpm]["wall"].append(wall_err)
			if _born_step[id] != step:
				_cross["frame"].append(frame_err)
				_cross["wall"].append(wall_err)
			events.append({"type": "arrival", "at": crossed, "frame": frame, "beat": item["beat"], "kind": ObstacleField.Kind.keys()[item["kind"]], "music": music, "bpm": bpm})
		_last_z[id] = [item["z"], wall]


## 박 물방울 줄의 도착: 실제 MultiMesh에서 다음 박 줄의 z를 읽어 0을 지나는 순간을 잰다.
func _record_rows() -> void:
	if not main.started or main.dead:
		_last_row = []
		return
	var ladder: MusicLadder = AudioManager.ladder
	var music: float = AudioManager.music_time
	var now_beat := ladder.beat_at(music)
	var wall := _now()
	var beat := ceilf(now_beat - 0.5)  # 가장 가까운 박
	var slot := BeatRows.slot_of(beat) * 2
	var z: float = main._dashes.multimesh.get_instance_transform(slot).origin.z + main._dashes.position.z
	if not _last_row.is_empty() and _last_row[0] == beat and _last_row[1] < 0.0 and z >= 0.0:
		var beat_t := ladder.time_of_beat(beat)
		_rows["frame"].append(music - beat_t)
		var crossed: float = _last_row[2] + (wall - _last_row[2]) * (0.0 - _last_row[1]) / (z - _last_row[1])
		if _wall_zero != INF:  # 첫 장애물 도착에서 정한 음악 0초 기준과 같은 시계로 잰다
			_rows["wall"].append(crossed - (_wall_zero + beat_t))
	_last_row = [beat, z, wall]


static func _mean_max(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var total := 0
	var top := 0
	for v: int in values:
		total += v
		top = maxi(top, v)
	return {"mean": snappedf(float(total) / values.size(), 0.1), "max": top}


static func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var total := 0.0
	var worst := 0.0
	for v in values:
		total += absf(v)
		worst = maxf(worst, absf(v))
	return {"count": values.size(), "mean_abs_ms": snappedf(total / values.size() * 1000.0, 0.01), "max_abs_ms": snappedf(worst * 1000.0, 0.01)}


func _finish() -> void:
	set_process(false)
	var deltas := _deltas.duplicate()
	deltas.sort()
	var by_bpm := {}
	for bpm in _by_bpm:
		by_bpm[str(bpm)] = {"frame": _stats(_by_bpm[bpm]["frame"]), "wall": _stats(_by_bpm[bpm]["wall"])}
	var gap_max := 0
	for g in _gaps:
		gap_max = maxi(gap_max, g)
	_clock_steps.sort()
	var jitter := {"p50_ms": _clock_steps[_clock_steps.size() / 2] * 1000.0, "p99_ms": _clock_steps[int(_clock_steps.size() * 0.99)] * 1000.0, "max_ms": _clock_steps[-1] * 1000.0}
	print("RESULT ", JSON.stringify({
		"clock_jitter": jitter, "render_size": [get_viewport().get_visible_rect().size, get_viewport().scaling_3d_scale, DisplayServer.window_get_size()],
		"mode": mode, "wall_secs": _now(), "music_time": _max_time, "crashes": _crashes,
		"frames": frame, "fps": frame / maxf(t, 0.001), "delta_p50_ms": deltas[deltas.size() / 2] * 1000.0, "delta_max_ms": deltas[-1] * 1000.0,
		"frame_err": _stats(_frame_err), "wall_err": _stats(_wall_err), "by_bpm": by_bpm,
		"rows_frame": _stats(_rows["frame"]), "rows_wall": _stats(_rows["wall"]), "draw_calls": _mean_max(_draws), "primitives": _mean_max(_prims),
		"cross_frame": _stats(_cross["frame"]), "cross_wall": _stats(_cross["wall"]), "slow_frames": _slow_frames, "segments": AudioManager.ladder.segments,
		"input_sound_pairs": _gaps.size(), "input_sound_max_usec": gap_max,
		"output_latency": AudioServer.get_output_latency(), "trace": _trace}))
	if _recording():
		var file := FileAccess.open(OS.get_environment("EVENTS_JSON") if OS.has_environment("EVENTS_JSON") else "user://events.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(events))
		file.close()
	get_tree().quit()
