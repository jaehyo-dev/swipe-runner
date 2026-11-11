extends Node
## v0.9.1 메인 화면 캡처 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다 (menu_shot.sh).
## 젤리 빛 웅덩이·반사의 화면 아래 끝과 SWIPE TO START 자리를 함께 기록한다.

const DT := 1.0 / 60.0
var _main: Node3D


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = "user://menu_shot_best.txt"
	add_child(_main)
	AudioManager.set_muted(true)
	while not _main.warmed:
		await get_tree().process_frame
	_main.set_process(false)
	for i in 45:
		_main.advance(DT)
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + ".png")
	var size := get_viewport().get_visible_rect().size
	var start: Control = _main._title.start_label
	var cam: Camera3D = _main._camera
	var glow := cam.unproject_position(Vector3(0.0, 0.0, 1.1))  # 웅덩이 앞 끝 (바닥)
	var log := "창 %s  웅덩이 앞 끝 y %.0f (%.2f)  SWIPE TO START 위 %.0f 아래 %.0f (%.2f~%.2f)" % [str(size), glow.y, glow.y / size.y, start.get_global_rect().position.y, start.get_global_rect().end.y, start.get_global_rect().position.y / size.y, start.get_global_rect().end.y / size.y]
	print(log)
	FileAccess.open(out + ".txt", FileAccess.WRITE).store_string(log + "\n")
	get_tree().quit()
