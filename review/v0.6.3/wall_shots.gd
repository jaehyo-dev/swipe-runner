extends Node
## 2칸 벽 확인 장면 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다.
##   godot --path . --resolution 720x1280 res://wall_shots.tscn -- <결과 폴더>
## 레인 쌍 × 거리, 벽 뒤에 오는 장애물, 멀리서 안개 속에 나타나는 모습을 찍는다.

const K := ObstacleField.Kind
const PAIRS := {"left": [0, 1], "right": [1, 2], "ends": [0, 2]}
var _main: Node3D
var _out: String
var _id := 9000


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://wall_shots_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.field.items.clear()
	for pair: String in PAIRS:
		for z: float in [-10.0, -25.0, -45.0]:
			_clear()
			for lane: int in PAIRS[pair]:
				_put(lane, 1.0, z, K.BLOCK)
			await _shot("wall_%s_z%d" % [pair, int(-z)])
	# 벽 뒤에 오는 장애물: 앞 벽을 통해 비쳐 보이는가
	for kind: K in [K.LOW, K.HIGH, K.BLOCK]:
		_clear()
		_put(0, 1.0, -9.0, K.BLOCK)
		_put(1, 1.0, -9.0, K.BLOCK)
		_put(1, 2.0, -18.0, kind)
		await _shot("behind_%s" % _main.KINDS[kind])
	# 멀리서 서서히 나타나기: 왼쪽부터 z -84, -72, -60 (색이 진해 안개가 잘 보이는 160BPM)
	_main._apply_tint(1.0)
	_clear()
	_put(0, 1.0, -84.0, K.LOW)
	_put(1, 2.0, -72.0, K.LOW)
	_put(2, 3.0, -60.0, K.LOW)
	await _shot("far_fade")
	# 시야각 비교: 같은 장면을 t = 0과 t = 1로
	for t: float in [0.0, 1.0]:
		_main._apply_tint(t)
		_clear()
		_put(0, 1.0, -14.0, K.BLOCK)
		_put(1, 1.0, -14.0, K.BLOCK)
		_put(2, 2.0, -28.0, K.HIGH)
		await _shot("fov_%d" % int(_main._camera.fov))
	get_tree().quit()


func _clear() -> void:
	_main.clear_pieces()


func _put(lane: int, beat: float, z: float, kind: K) -> void:
	_id += 1
	_main._spawn_node({"id": _id, "lane": lane, "beat": beat, "z": z, "kind": kind})


func _shot(name_: String) -> void:
	_main._sync_pieces()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
