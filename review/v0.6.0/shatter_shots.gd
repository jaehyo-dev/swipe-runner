extends Node
## 부서짐 프레임을 찍는다 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다.
##   godot --path . --resolution 720x1280 res://shatter_shots.tscn -- <결과 폴더>
## 결과: <이름>_NNN.png. 주인공은 가운데 레인이라 옆 레인 장애물이 부서진다.

const K := ObstacleField.Kind
const STEP := 1.0 / 60.0
const ROWS := {
	"single": [[K.LOW, 2]],
	"double": [[K.BLOCK, 0], [K.HIGH, 2]],
	"over": [[K.LOW, 1], [K.BLOCK, 0]],
}
const FRAMES := 48

var _main: Node3D


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	AudioManager.start_step = MusicLadder.step_of_bpm(130)
	AudioManager.ladder = MusicLadder.new(AudioManager.start_step)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://shatter_best.txt"
	add_child(_main)
	_main.set_process(false)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.started = true
	_main.begin()
	var t := 0.0
	for name_: String in ROWS:
		_main.field.items.clear()
		_main.clear_pieces()
		var id := 9000
		var ahead: float = _main.speed * 0.25
		for row: Array in ROWS[name_]:
			var item := {"id": id, "lane": row[1], "z": -ahead, "kind": row[0], "beat": 0, "arrive": _main.travel + ahead}
			_main.field.items.append(item)
			_main._spawn_node(item)
			id += 1
		if name_ == "over":  # 점프로 넘는 장면
			_main.apply_swipe(SwipeDetector.Dir.UP)
		for f in FRAMES:
			t += STEP
			_main.field._coming["beat"] = 1000000.0  # 찍는 동안 다른 장애물이 나오지 않게
			_main.advance(STEP, t)
			_main._sync_pieces()
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%03d.png" % [out, name_, f])
	get_tree().quit()
