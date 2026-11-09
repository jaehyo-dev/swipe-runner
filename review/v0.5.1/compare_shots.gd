extends Node
## 전후 비교 캡처: 같은 장면을 v0.5.0과 v0.5.1에서 찍는다 (웹 빌드에 들어가지 않음). 두 버전의 폴더에 복사해 실행한다.
##   godot --path <프로젝트> --resolution 720x1280 res://compare_shots.tscn -- <결과 폴더>

const K := ObstacleField.Kind
var _main: Node3D


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://compare_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_clear()
	await _scene(out + "/bar.png", [[K.HIGH, 1, -3.2], [K.HIGH, 0, -9.0]])
	await _scene(out + "/pillars.png", [[K.BLOCK, 0, -6.0], [K.BLOCK, 0, -14.0], [K.BLOCK, 0, -22.0]])
	await _scene(out + "/double.png", [[K.BLOCK, 0, -7.0], [K.BLOCK, 2, -7.0], [K.BLOCK, 0, -15.0], [K.BLOCK, 1, -15.0], [K.LOW, 1, -23.0], [K.HIGH, 2, -23.0]])
	get_tree().quit()


func _clear() -> void:
	if _main.has_method("clear_pieces"):
		_main.clear_pieces()
	else:
		for id in _main._obstacles:
			_main._obstacles[id].queue_free()
		_main._obstacles.clear()


func _scene(path: String, pieces: Array) -> void:
	var id := 9000
	for p: Array in pieces:
		_main._spawn_node({"id": id, "kind": p[0], "lane": p[1], "z": p[2]})
		id += 1
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	_clear()
	await get_tree().process_frame
