extends Node
## 아트 확인용 캡처 (웹 빌드에 들어가지 않음). 세 종류 장애물을 같은 z에 놓고 찍는다. 창이 있는 실행에서만 동작한다.
##   godot --path . res://tools/art_sheet.tscn -- <결과 폴더>
##   결과: sheet_z<거리>.png 3장, near.png, jump.png(점프 꼭대기), sparkle_off.png·sparkle.png(박 줄이 주인공 옆, 반짝임 끔·켬), flash.png(단계 빛남)

var _main: Node3D


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://art_sheet_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	for id in _main._obstacles:
		_main._obstacles[id].queue_free()
	_main._obstacles.clear()
	_main.field.items.clear()
	var i := 0
	for z in [-10.0, -25.0, -45.0]:
		for kind in ObstacleField.Kind.values():
			_main._spawn_node({"id": 5000 + i, "lane": kind, "z": z, "kind": kind})
			i += 1
		await _shot("%s/sheet_z%d.png" % [out, int(-z)])
		for id in _main._obstacles:
			_main._obstacles[id].queue_free()
		_main._obstacles.clear()
	# 가까운 세 종류와 주인공 반사 (바로 앞 레인에 막대, 점프)
	for kind in ObstacleField.Kind.values():
		_main._spawn_node({"id": 6000 + kind, "lane": kind, "z": -4.0, "kind": kind})
	await _shot("%s/near.png" % out)
	_main.player.jump()
	for f in 18:
		_main.player.step(1.0 / 60.0)
		_main.runner.lift = _main.player.height()
		await get_tree().process_frame
	await _shot("%s/jump.png" % out)
	for id in _main._obstacles:
		_main._obstacles[id].queue_free()
	_main._obstacles.clear()
	var row: ShaderMaterial = _main._droplet_material
	_main.runner.visible = false  # 주인공 옆 줄이 가리지 않게
	_main._droplets.position.z = 0.0  # 박 줄이 주인공 옆
	await _shot("%s/sparkle_off.png" % out)
	row.set_shader_parameter("sparkle_on", 1.0)
	await _shot("%s/sparkle.png" % out)
	_main._set_flash(1.0)
	await _shot("%s/flash.png" % out)
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
