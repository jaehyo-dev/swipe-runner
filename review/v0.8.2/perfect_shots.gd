extends Node
## v0.8.2 기록 장면 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다 (capture.sh).
##   godot --path . --fixed-fps 60 --resolution 720x1280 res://perfect_shots.tscn -- <결과 폴더> <gif|ui>
## gif: 도전 모델(tests/human_player.gd DARE)이 실제로 달리며 받은 PERFECT 한 번, 연속 ×3 장면
##      먼저 그림 없이 달려 장면 시각을 찾고, 같은 입력으로 다시 달리며 그 구간만 프레임 PNG로 남긴다
## ui:  BEST·배수 ×3·"PERFECT ×3  +300"이 함께 보이는 달리기 (지금 창 크기로)

const SEED := 143
const DARE_SEED := 46  # 도전 모델이 PERFECT ×3을 받는 시드 (헤드리스 시뮬레이션 63.8·72.9초. 시드 50개 중 ×3은 32번, 시드 143은 82초 동안 0번)
const DT := 1.0 / 60.0
const LIMIT := 150.0
var _main: Node3D
var _out: String
var _log: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AudioServer.set_bus_mute(0, true)
	var best := FileAccess.open("user://perfect_shots_best.txt", FileAccess.WRITE)
	best.store_string("99999")  # BEST 줄이 보이게 (PERFECT와 겹치는지 확인)
	best.close()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = SEED
	_main.best_path = "user://perfect_shots_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.set_process(false)  # 시간은 이 스크립트가 돌린다
	match args[1]:
		"gif":
			await _gifs()
		"ui":
			await _ui()
	FileAccess.open("%s/%s.txt" % [_out, args[1]], FileAccess.WRITE).store_string("\n".join(_log) + "\n")
	get_tree().quit()


func _plan(end_beat: float) -> MusicLadder:
	var ladder := MusicLadder.new()
	var t := 0.0
	while ladder.beat_at(t) < end_beat:
		t += DT
		ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
	return ladder


## 처음부터 사람 모델(또는 방울을 무시하는 완벽한 자동 플레이어 "auto")로 달린다. 결과 {events: [[시각, 연속 수]], misses: [시각], dead, time}
## frames: [[시작, 끝, 폴더, 몇 프레임마다]] 구간의 프레임을 남긴다
func _run(model: Variant, frames: Array, seed_value := SEED) -> Dictionary:
	if _main.dead:  # 앞 판에서 부딪혔으면 먼저 다시 시작해 모양을 되돌린다
		_main.restart()
		for i in 30:
			await RenderingServer.frame_post_draw
	var ladder := _plan(1200.0)
	AudioManager.ladder = ladder
	_main.clear_pieces()
	_main.dead = false
	_main.score = ScoreBoard.new()
	_main._hide_perfect()
	_main._show_multiplier(false)
	_main.field = ObstacleField.new(seed_value, ladder)
	_main.lane = RunLogic.START_LANE
	_main.runner.position.x = RunLogic.lane_x(_main.lane)
	_main.player = PlayerAction.new()
	_main.started = true
	_main._music_t = 0.0
	_main.advance(0.0, 0.0)
	var human: HumanPlayer = HumanPlayer.new(seed_value, model) if model is Dictionary else null
	var events := []
	var misses := []
	var closes := 0
	var missed := 0
	var t := 0.0
	var last := -INF
	var n := 0
	for f in frames:
		DirAccess.make_dir_recursive_absolute(f[2])
	while t < LIMIT and not _main.dead:
		t += DT
		var seen := RunSim.visible_items(_main.field.items, ladder, t)
		var dir: int
		if human:
			dir = human.decide(t, seen, _main.lane, _main.player, _main.speed, RunSim.visible_items(_main.field.orbs, ladder, t))
		else:
			dir = AutoPlayer.decide(seen, _main.lane, _main.player, _main.speed, t - last)
		if dir != SwipeDetector.Dir.NONE:
			last = t
			_main.apply_swipe(dir)
		_main.advance(DT, t)
		if _main.score.close > closes:
			closes = _main.score.close
			events.append([t, _main._perfect_chain])
		if _main.score.missed > missed:
			missed = _main.score.missed
			misses.append(t)
		var recording := false
		for f in frames:
			if t >= f[0] and t <= f[1]:
				recording = true
		if recording:
			_main._sync_pieces()
			_main._sync_orbs()
		await RenderingServer.frame_post_draw
		for f in frames:
			if t >= f[0] and t <= f[1] and n % f[3] == 0:
				get_viewport().get_texture().get_image().save_png("%s/%04d.png" % [f[2], int(round((t - f[0]) / DT)) / f[3]])
		n += 1
	return {"events": events, "misses": misses, "dead": _main.dead, "time": t}


func _gifs() -> void:
	var first := await _run(HumanPlayer.DARE, [], DARE_SEED)
	_log.append("도전 모델 시드 %d: %.1f초, PERFECT %d번, 죽음 %s" % [DARE_SEED, first["time"], first["events"].size(), first["dead"]])
	var single := -1.0
	var triple := -1.0
	var events: Array = first["events"]
	for i in events.size():
		var alone: bool = (i == 0 or events[i][0] - events[i - 1][0] > 1.0) and (i == events.size() - 1 or events[i + 1][0] - events[i][0] > 1.2)
		if single < 0.0 and alone and events[i][0] > 5.0:
			single = events[i][0]
		if triple < 0.0 and events[i][1] >= 3:
			triple = events[i][0]
	_log.append("한 번: %.2f초, 연속 ×3: %.2f초" % [single, triple])
	var frames := []
	if single > 0.0:
		frames.append([single - 1.0, single + 1.2, _out + "/perfect", 2])
	if triple > 0.0:
		frames.append([triple - 1.8, triple + 1.2, _out + "/perfect_x3", 2])
	var again := await _run(HumanPlayer.DARE, frames, DARE_SEED)
	_log.append("다시 달린 결과가 같음: %s" % str(again["events"] == first["events"]))

func _ui() -> void:
	var ladder := _plan(200.0)
	AudioManager.ladder = ladder
	_main.field = ObstacleField.new(SEED, ladder)
	var t := 20.0
	_main._apply_step(_main.field.step(ladder.distance_at(t), ladder.spawn_distance_at(t)))
	for lane in [1, 0, 2]:  # 주인공 앞뒤 2m 안에 장애물이 없는 레인
		if not _main.field.items.any(func(it): return it["lane"] == lane and absf(it["z"]) < 2.0):
			_main.lane = lane
			_main.runner.position.x = RunLogic.lane_x(lane)
			break
	_main._music_t = t
	_main.started = true
	_main.advance(0.0, t)
	_main.score.combo = 24
	_main.score.points = 1840
	_main._show_multiplier(false)
	var item := {"lane": 0}
	for points in [300, 300, 300]:  # 연속 PERFECT ×3, 마지막에 더해진 점수 +300 (100 × 배수 3)
		_main._on_close(item, points)
	for i in 30:  # 말랑 커졌다 돌아오고 점수가 다 올라갈 때까지 (머무는 0.6초 안). 세상은 멈춰 둔다
		_main._show_score(DT)
		await get_tree().process_frame
	_main._sync_pieces()
	_main._sync_orbs()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ui_run.png" % _out)
	var p: Label = _main._perfect_label
	_log.append("ui: PERFECT 줄 화면 비율 위 %.3f, 아래 %.3f (창 %s)" % [p.get_global_rect().position.y / get_viewport().get_visible_rect().size.y, p.get_global_rect().end.y / get_viewport().get_visible_rect().size.y, str(get_viewport().get_visible_rect().size)])
	_log.append("ui: 죽음 %s, 점수 %s, %s, 배수 %s, BEST 보임 %s" % [_main.dead, _main._score_label.text, _main._perfect_label.text, _main._mult_label.text, _main._best_label.visible])

