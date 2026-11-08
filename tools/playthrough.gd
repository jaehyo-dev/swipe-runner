extends Node
## 화면 확인 기록용 자동 플레이 (웹 빌드에 들어가지 않음). 결과는 RESULT 줄로 찍는다.
##   박자 측정: godot --path . res://tools/playthrough.tscn -- accuracy 180
##   30초 녹화: godot --path . --write-movie x.avi --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- movie 30
## 웹 측정은 주소에 ?mode=accuracy&secs=180

const SEED := 136
const Dir := SwipeDetector.Dir
## 30초 장면: [시각, 동작]. 처음 7초는 길이 비어 있어 동작을 차례로 보여 주고, 12초에 일부러 부딪힌 뒤 다시 달린다.
const SCRIPT := [
	[1.2, Dir.RIGHT], [2.0, Dir.LEFT], [2.8, Dir.LEFT], [3.6, Dir.UP],
	[4.6, Dir.DOWN], [5.6, Dir.UP], [5.85, Dir.DOWN],  # 공중 아래 스와이프
]
const FIRST_TAP := 0.5
const SEEK_AT := 12.0     # 이 시각부터 장애물 쪽으로 간다
const RESTART_AFTER := 0.7

var mode := "accuracy"
var secs := 180.0
var main: Node3D
var t := 0.0
var frame := 0
var _step := 0
var _crash_t := -1.0
var _seek := false
var _start_usec := 0
var _last_z := {}      # id -> [z, 벽시계 초]
var _frame_err: Array[float] = []    # 도착 프레임의 음악 시간 - 가장 가까운 박
var _wall_err: Array[float] = []     # 벽시계로 보간한 도착 시각 - 박 격자
var _wall_zero := INF
var _deltas: Array[float] = []
var _max_time := 0.0
var _crashes := 0
var _input_usec := 0
var _input_frame := -1
var _input_name := ""
var events: Array[Dictionary] = []
var _gaps: Array[int] = []


func _ready() -> void:
	process_priority = 100  # main이 이번 프레임의 z를 계산한 뒤에 잰다
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		mode = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mode') || 'accuracy'"))
		secs = float(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('secs') || 180")))
	elif args.size() >= 2:
		mode = args[0]
		secs = float(args[1])
	if mode == "accuracy" and not OS.has_feature("web"):
		AudioServer.set_bus_mute(0, true)  # 3분 동안 소리가 나지 않게. 믹스와 재생 위치는 그대로 돈다
	main = load("res://scenes/main.tscn").instantiate()
	main.seed_value = SEED
	add_child(main)
	AudioManager.played.connect(_on_played)
	_start_usec = Time.get_ticks_usec()


## 기록 시각(초). 녹화는 실제 시간과 무관하게 프레임 단위로 흐르므로 게임 시간을 쓴다.
func _now() -> float:
	if mode == "movie":
		return t
	return (Time.get_ticks_usec() - _start_usec) / 1000000.0


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
	_max_time = maxf(_max_time, AudioManager.music_time)
	_record_arrivals()
	if not main.started:
		if t >= FIRST_TAP:
			_tap("첫 탭")
		return
	if main.dead:
		if _crash_t < 0.0:
			_crash_t = t
			_crashes += 1
			events.append({"type": "crash", "at": _now(), "frame": frame, "music": AudioManager.music_time})
		elif t - _crash_t >= RESTART_AFTER:
			_crash_t = -1.0
			_seek = false
			_tap("다시 시작 탭")
	elif mode == "movie" and _step < SCRIPT.size():
		if t >= SCRIPT[_step][0]:
			_swipe(SCRIPT[_step][1])
			_step += 1
	elif mode == "movie" and _crashes == 0 and t >= SEEK_AT:
		_seek = true
		_seek_lane()
	else:
		var dir := AutoPlayer.decide(main.field.items, main.lane, main.player)
		if dir != Dir.NONE:
			_swipe(dir)
	if t >= secs + FIRST_TAP:
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
	for item: Dictionary in main.field.items:
		var id: int = item["id"]
		if _last_z.has(id) and _last_z[id][0] < 0.0 and item["z"] >= 0.0:
			var beat_t: float = item["beat"] * BeatClock.BEAT
			# 프레임 기준: 도착이 보인 첫 프레임의 음악 시간 - 가장 가까운 박 (프레임 간격만큼 늦을 수 있다)
			var music: float = AudioManager.music_time
			var nearest: float = roundf(music / BeatClock.BEAT) * BeatClock.BEAT
			_frame_err.append(music - nearest)
			# 보간 기준: 두 프레임 사이에서 z가 0이 된 벽시계 시각. 첫 도착을 기준으로 박 격자와 비교한다 (음악 시계와 독립)
			var crossed: float = _last_z[id][1] + (wall - _last_z[id][1]) * (0.0 - _last_z[id][0]) / (item["z"] - _last_z[id][0])
			if _wall_zero == INF:
				_wall_zero = crossed - beat_t
			_wall_err.append(crossed - (_wall_zero + beat_t))
			events.append({"type": "arrival", "at": crossed, "frame": frame, "beat": item["beat"], "kind": ObstacleField.Kind.keys()[item["kind"]], "music": music})
		_last_z[id] = [item["z"], wall]


static func _stats(values: Array[float]) -> Dictionary:
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
	var gap_max := 0
	for g in _gaps:
		gap_max = maxi(gap_max, g)
	print("RESULT ", JSON.stringify({
		"mode": mode, "wall_secs": _now(), "music_time": _max_time, "loops": int(_max_time / BeatClock.LOOP), "crashes": _crashes,
		"frames": frame, "fps": frame / maxf(t, 0.001), "delta_p50_ms": deltas[deltas.size() / 2] * 1000.0, "delta_max_ms": deltas[-1] * 1000.0,
		"frame_err": _stats(_frame_err), "wall_err": _stats(_wall_err),
		"frame_err_list": _frame_err.map(func(v): return snappedf(v * 1000.0, 0.1)), "wall_err_list": _wall_err.map(func(v): return snappedf(v * 1000.0, 0.1)),
		"input_sound_pairs": _gaps.size(), "input_sound_max_usec": gap_max,
		"output_latency": AudioServer.get_output_latency()}))
	if mode == "movie":
		var file := FileAccess.open(OS.get_environment("EVENTS_JSON") if OS.has_environment("EVENTS_JSON") else "user://events.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(events))
		file.close()
	get_tree().quit()
