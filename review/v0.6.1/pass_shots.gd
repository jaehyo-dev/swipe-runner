extends Node
## 장애물이 주인공을 지나쳐 뒤로 가는 장면을 z 0~4에서 찍는다 (웹 빌드에 들어가지 않음).
##   godot --path <프로젝트> --resolution 720x1280 res://pass_shots.tscn -- <결과 폴더>
## 결과: pass_<종류>_z<거리>.png. 가운데 레인 주인공 기준으로 슬라이드 블록은 같은 레인(슬라이드로 지나감), 기둥과 점프 블록은 옆 레인.

const K := ObstacleField.Kind


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 143
	main.best_path = "user://pass_best.txt"
	add_child(main)
	main.set_process(false)
	while not main.prewarmed:
		await get_tree().process_frame
	for row: Array in [["block", K.BLOCK, 0], ["low", K.LOW, 2], ["high", K.HIGH, 1]]:
		for z: int in [0, 1, 2, 3, 4]:
			main.clear_pieces()
			main.field.items.clear()
			main._spawn_node({"id": 1, "lane": row[2], "z": float(z), "kind": row[1]})
			main.runner.crouch = 1.0 if row[1] == K.HIGH else 0.0
			main._sync_pieces()
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/pass_%s_z%d.png" % [out, row[0], z])
	get_tree().quit()
