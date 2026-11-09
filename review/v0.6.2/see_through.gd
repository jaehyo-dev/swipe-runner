extends Node
## 같은 레인에 "기둥 → 턱·막대·기둥"을 놓고 찍는다 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다.
##   godot --path . --resolution 1440x2560 res://see_through.tscn -- <결과 폴더>
## 밝기를 재려고 같은 장면을 앞 기둥 유무, 기호·테두리 유무로 나눠 찍는다.

const K := ObstacleField.Kind
const GAP := 7.2  # 100BPM 두 박 간격의 거리
const LANE := 1
var _main: Node3D
var _out: String


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://see_through_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.field.items.clear()
	_main.runner.visible = false  # 주인공이 가운데 레인을 가리지 않게
	for z in [-10.0, -25.0]:
		var name_z := "z%d" % int(-z)
		await _set_pieces(z, -1, false)
		await _shot("empty_" + name_z)
		await _set_pieces(z, -1, true)
		await _shot("front_" + name_z)
		_color("edge_color", K.BLOCK, Color.BLACK)
		await _shot("front_noedge_" + name_z)
		_main._apply_tint(1.0)
		_main._apply_tint(0.0)
		for kind: K in [K.LOW, K.HIGH, K.BLOCK]:
			var tag := "%s_%s" % [_main.KINDS[kind], name_z]
			await _set_pieces(z, kind, true)
			await _shot("both_" + tag)
			await _set_pieces(z, kind, false)
			await _shot("back_" + tag)
			_color("edge_color", kind, Color.BLACK)
			await _shot("back_noedge_" + tag)
			_main._apply_tint(1.0)
			_main._apply_tint(0.0)
			if kind != K.BLOCK:
				_color("mark_color", kind, Color.BLACK)
				await _shot("back_nomark_" + tag)
				_main._apply_tint(1.0)
				_main._apply_tint(0.0)
	get_tree().quit()


func _color(param: String, kind: K, c: Color) -> void:
	_main._kind_meshes[kind]["block"].set_shader_parameter(param, c)


## 앞 기둥(front)과 뒤 장애물(kind, -1이면 없음)
func _set_pieces(z: float, kind: int, front: bool) -> void:
	_main.clear_pieces()
	if front:
		_main._spawn_node({"id": 9001, "lane": LANE, "z": z, "kind": K.BLOCK})
	if kind >= 0:
		_main._spawn_node({"id": 9002, "lane": LANE, "z": z - GAP, "kind": kind})
	_main._sync_pieces()


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
