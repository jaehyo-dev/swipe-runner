extends Node
## v0.8.0 기록 장면 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다 (capture.sh).
##   godot --path . --fixed-fps 60 --resolution 720x1280 res://orb_shots.tscn -- <결과 폴더> <place|gif|ui>
## place: 방울 모양 넷(레인 이동 / 턱 위 포물선 / 막대 아래 / 장애물 옆)을 그 방울이 z -10, -25에 있을 때 한 장씩
## gif:   먹는 순간, 콤보 끊김(콤보 12에서 일부러 놓침), 아슬아슬 — 프레임 PNG를 폴더별로
## ui:    배수 ×3이 보이는 달리기, 게임 오버 (지금 창 크기로)

const SEED := 143
const Kind := ObstacleField.Kind
const DT := 1.0 / 60.0
var _main: Node3D
var _out: String
var _log: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = SEED
	_main.best_path = "user://orb_shots_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.set_process(false)  # 시간은 이 스크립트가 돌린다
	match args[1]:
		"place":
			await _place()
		"gif":
			await _gifs()
		"ui":
			await _ui()
	FileAccess.open("%s/%s.txt" % [_out, args[1]], FileAccess.WRITE).store_string("\n".join(_log) + "\n")
	get_tree().quit()


## 시드의 사다리·장애물·방울 줄을 end_beat까지 만든다 (tests/test_orbs.gd와 같은 방법)
func _plan(seed_value: int, end_beat: float) -> Dictionary:
	var ladder := MusicLadder.new()
	var field := ObstacleField.new(seed_value, ladder)
	field.keep_trails = true
	var items: Array = []
	var t := 0.0
	while ladder.beat_at(t) < end_beat:
		t += DT
		ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
		items.append_array(field.step(ladder.distance_at(t), ladder.spawn_distance_at(t))["spawned"])
	return {"ladder": ladder, "items": items, "trails": field.trails}


## 모양별 첫 줄과 그 모양 방울
func _find(plan: Dictionary, shape: String) -> Array:
	for trail: Dictionary in plan["trails"]:
		for o: Dictionary in trail["orbs"]:
			var hit := false
			match shape:
				"move":
					hit = absf(o["x"] - RunLogic.lane_x(o["lane"])) > 0.3
				"arc":
					hit = o["y"] > 1.5
				"under":
					hit = o["y"] < 0.3
				"beside":
					hit = plan["items"].any(func(it): return it["beat"] == o["beat"] and absi(it["lane"] - o["lane"]) == 1)
			if hit and trail["start"] > 8.0:
				return [trail, o]
	return []


## main을 그 판의 시각 t로 옮긴다. 주인공은 lane에. 앞 장면에서 부딪혔으면 먼저 다시 시작해 모양을 되돌린다
func _set_at(plan: Dictionary, t: float, at_lane: int) -> void:
	if _main.dead:
		_main.restart()
		for i in 30:
			await RenderingServer.frame_post_draw
	AudioManager.ladder = plan["ladder"]
	_main.clear_pieces()
	_main.dead = false
	_main.score = ScoreBoard.new()
	_main._show_multiplier(false)
	_main.field = ObstacleField.new(SEED, plan["ladder"])
	_main.lane = at_lane
	_main.runner.position.x = RunLogic.lane_x(at_lane)
	_main.started = true
	_main._music_t = t
	_main.advance(0.0, t)


## 시각 t에 주인공 자리 가까이(앞뒤 1.5) 장애물이 없는 레인. 원하는 레인부터 본다
func _safe_lane(plan: Dictionary, t: float, want: int) -> int:
	var ladder: MusicLadder = plan["ladder"]
	for lane in [want, 0, 1, 2]:
		var busy: bool = plan["items"].any(func(it): return it["lane"] == lane and absf(ladder.distance_at(t) - ladder.distance_of_beat(it["beat"])) < 1.5)
		if not busy:
			return lane
	return want


func _place() -> void:
	var plan := _plan(SEED, 200.0)
	for shape in ["move", "arc", "under", "beside"]:
		var found := _find(plan, shape)
		if found.is_empty():
			_log.append("%s: 못 찾음" % shape)
			continue
		var trail: Dictionary = found[0]
		var orb: Dictionary = found[1]
		var ladder: MusicLadder = plan["ladder"]
		for z in [10.0, 25.0]:
			var t: float = ladder.time_of_beat(orb["beat"]) - z / ladder.speed_at(ladder.time_of_beat(orb["beat"]))
			await _set_at(plan, t, _safe_lane(plan, t, trail["lane0"]))
			_log.append("%s z -%d: 줄 박 %.1f, 방울 박 %.1f 레인 %d 높이 %.2f, 시각 %.2f초, 죽음 %s" % [shape, z, trail["start"], orb["beat"], orb["lane"], orb["y"], t, _main.dead])
			await _shot("%s/place_%s_z%d.png" % [_out, shape, z])


## t_from부터 t_to까지 한 엔진 프레임에 1/60초씩 달린다 (주인공 트윈도 같은 속도). inputs: [[시각, 방향]].
## folder가 있으면 두 프레임마다 한 장(30fps). 결과 {dead, orbs, missed, close}
## auto: 입력 대신 완벽한 자동 플레이어(방울 무시)가 피한다
func _play(plan: Dictionary, at_lane: int, t_from: float, t_to: float, inputs: Array, folder: String, combo := 0, auto := false) -> Dictionary:
	await _set_at(plan, t_from, at_lane)
	_main.score.combo = combo
	_main._show_multiplier(false)
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
	var queue := inputs.duplicate()
	var t := t_from
	var last := -INF
	var n := 0
	while t < t_to:
		t += DT
		while not queue.is_empty() and queue[0][0] <= t:
			_main.apply_swipe(queue.pop_front()[1])
		if auto:
			var seen := RunSim.visible_items(_main.field.items, plan["ladder"], t)
			var dir := AutoPlayer.decide(seen, _main.lane, _main.player, _main.speed, t - last)
			if dir != SwipeDetector.Dir.NONE:
				last = t
				_main.apply_swipe(dir)
		_main.advance(DT, t)
		_main._sync_pieces()
		_main._sync_orbs()
		await RenderingServer.frame_post_draw
		if folder != "" and n % 2 == 0:
			get_viewport().get_texture().get_image().save_png("%s/%04d.png" % [folder, n / 2])
		n += 1
	return {"dead": _main.dead, "orbs": _main.score.orbs, "missed": _main.score.missed, "close": _main.score.close}


func _gifs() -> void:
	var plan := _plan(SEED, 120.0)
	var ladder: MusicLadder = plan["ladder"]
	var eat: Dictionary = _find(plan, "move")[0]
	var inputs: Array = eat["inputs"].map(func(i): return [ladder.time_of_beat(i[0]), i[1]])
	var t0 := ladder.time_of_beat(eat["start"] - 1.5)
	var t1 := ladder.time_of_beat(eat["orbs"][-1]["beat"] + 1.0)
	var r := await _play(plan, eat["lane0"], t0, t1, inputs, _out + "/eat", 8)
	_log.append("eat: %s" % r)
	# 콤보 끊김: 콤보 12(×2)에서 방울을 무시하는 완벽한 자동 플레이어(AutoPlayer)가 장애물만 피한다. 방울 줄을 지나치며 놓친다.
	# 부딪히지 않고 놓치는 줄·시작 레인을 먼저 달려 보고(그림 없이) 고른다
	var picked := false
	for trail: Dictionary in plan["trails"]:
		if picked or trail["orbs"][-1]["beat"] > 100.0:
			break
		for lane in 3:
			if lane == trail["lane0"]:
				continue
			var a := ladder.time_of_beat(trail["start"] - 1.5)
			var b := ladder.time_of_beat(trail["orbs"][-1]["beat"] + 1.0)
			r = await _play(plan, lane, a, b, [], "", 12, true)
			if not r["dead"] and r["missed"] > 0:
				r = await _play(plan, lane, a, b, [], _out + "/break", 12, true)
				_log.append("break: 줄 박 %.1f 시작 레인 %d, %s" % [trail["start"], lane, r])
				picked = true
				break
	# 아슬아슬: 기둥 하나가 내 레인에 오고 도착 0.15초 전에 비어 있는 옆 레인으로
	for it: Dictionary in plan["items"]:
		var row: Array = plan["items"].filter(func(o): return o["beat"] == it["beat"])
		if it["kind"] != Kind.BLOCK or row.size() != 1 or it["beat"] < 12.0:
			continue
		var arrive := ladder.time_of_beat(it["beat"])
		for to in [it["lane"] - 1, it["lane"] + 1]:
			if to < 0 or to > 2 or plan["items"].any(func(o): return o["lane"] == to and absf(o["beat"] - it["beat"]) <= 2.0):
				continue
			var dir := SwipeDetector.Dir.LEFT if to < it["lane"] else SwipeDetector.Dir.RIGHT
			r = await _play(plan, it["lane"], arrive - 1.0, arrive + 0.6, [[arrive - 0.15, dir]], _out + "/close")
			_log.append("close: 박 %.1f, %s" % [it["beat"], r])
			return


func _ui() -> void:
	var plan := _plan(SEED, 120.0)
	var trail: Dictionary = _find(plan, "move")[0]
	var ladder: MusicLadder = plan["ladder"]
	var t := ladder.time_of_beat(trail["start"] - 1.0)
	await _set_at(plan, t, _safe_lane(plan, t, trail["lane0"]))
	_main.score.combo = 24
	_main.score.points = 640
	_main._show_multiplier(false)
	for i in 30:  # 말랑 커졌다 돌아올 때까지
		await get_tree().process_frame
	_main.advance(0.0, t)
	await _shot("%s/ui_run.png" % _out)
	_main.score.orbs = 123
	_main.score.close = 7
	var item: Dictionary = _main.field.items[0]
	_main._game_over(item)
	for i in 40:
		_main.advance(DT)
		await get_tree().process_frame
	await _shot("%s/ui_gameover.png" % _out)
	_log.append("ui: 점수 %s" % _main._score_label.text)


func _shot(path: String) -> void:
	_main._sync_pieces()
	_main._sync_orbs()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
