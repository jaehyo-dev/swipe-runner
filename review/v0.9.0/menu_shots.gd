extends Node
## v0.9.0 기록 장면 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다 (capture.sh).
##   godot --path . --fixed-fps 60 --resolution 720x1280 res://menu_shots.tscn -- <결과 폴더> <menu|start|home|mark>
## menu:  메인 화면 첫 실행(조작 안내 있음)과 4판째 이후(안내 없음), BEST 7157 (지금 창 크기로)
## start: 시작 전환 프레임 (탭 0.3초 전 ~ 1.0초 뒤, 30fps)
## home:  게임 오버 → 집 버튼 → 메인 화면 프레임 (30fps)
## mark:  주황 ^ 블록을 z -45에 두고 게임 카메라로 (안개를 걷어 기호 모양만 본다)

const DT := 1.0 / 60.0
const BEST := "user://menu_shots_best.txt"
var _main: Node3D
var _out: String
var _log: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var best := FileAccess.open(BEST, FileAccess.WRITE)
	best.store_string("7157")
	best.close()
	DirAccess.remove_absolute(BEST.get_basename() + "_settings.cfg")  # 첫 실행처럼
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = 143
	_main.best_path = BEST
	add_child(_main)
	AudioManager.set_muted(true)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.set_process(false)  # 시간은 이 스크립트가 돌린다 (헤드리스는 음악 시계가 실제로 흐르지 않는다)
	match args[1]:
		"menu":
			await _menu()
		"start":
			await _start()
		"home":
			await _home()
		"mark":
			await _mark()
	FileAccess.open("%s/%s.txt" % [_out, args[1]], FileAccess.WRITE).store_string("\n".join(_log) + "\n")
	get_tree().quit()


## 한 프레임: 메인 화면이면 메뉴 시간, 게임 중이면 음악 시간 t로 진행하고 그린다
func _frame(t := NAN) -> void:
	_main.advance(DT, t)
	_main._sync_pieces()
	_main._sync_orbs()
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(("%s/%s" % [_out, name]).get_base_dir())
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _tap() -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(360, 700)
	_main._input(touch)


func _menu() -> void:
	for i in 45:  # 박 사이 숨쉬기가 가라앉은 순간 (0.75초 = 1.25박)
		await _frame()
	_shot("menu_first")
	var size := get_viewport().get_visible_rect().size
	for node: String in ["TitleLabel", "MenuBestLabel", "Guide", "StartLabel", "SoundButton"]:
		var c: Control = _main._title.find_child(node, true, false)
		_log.append("%s: 위 %.3f 아래 %.3f 왼쪽 %.3f 오른쪽 %.3f (창 %s)" % [node, c.get_global_rect().position.y / size.y, c.get_global_rect().end.y / size.y, c.get_global_rect().position.x / size.x, c.get_global_rect().end.x / size.x, str(size)])
	var title: Label = _main._title.find_child("TitleLabel", true, false)
	_log.append("제목 글자 폭 %.0fpx (화면 %.0f)" % [title.label_settings.font.get_string_size("PULSE", HORIZONTAL_ALIGNMENT_LEFT, -1, title.label_settings.font_size).x, size.x])
	_main.save.plays = SaveData.GUIDE_RUNS
	_main._title.show_menu(_main.record.best, _main.save.shows_guide(), _main.save.muted)
	for i in 45:
		await _frame()
	_shot("menu_later")


func _start() -> void:
	var n := 0
	for i in 18:  # 탭 0.3초 전부터
		await _frame()
		if i % 2 == 0:
			_shot("start/%04d" % n)
			n += 1
	_tap()
	_log.append("시작: started %s, 시작 입력으로 레인 %d (가운데 1)" % [_main.started, _main.lane])
	var t := 0.0
	for i in 60:
		t += DT
		await _frame(t)
		if i % 2 == 0:
			_shot("start/%04d" % n)
			n += 1
	_log.append("1초 뒤: 카메라 %s (게임 %s), 제목 보임 %s" % [str(_main._camera.position), str(_main.GAME_CAM), _main._title.visible])


func _home() -> void:
	for i in 10:
		await _frame()
	_tap()
	var t := 0.0
	while t < 1.4:
		t += DT
		await _frame(t)
	var item := {"id": 9999, "lane": _main.lane, "z": -0.75, "kind": ObstacleField.Kind.BLOCK, "beat": 0, "arrive": _main.travel + 0.75, "shape": ""}
	_main.field.items.append(item)
	_main._spawn_node(item)
	await _frame(t + DT)
	var n := 0
	for i in 66:  # 부딪힌 뒤 0.6초 (집 버튼이 0.5초에 보인다) + 페이드 0.4초 + 메인 화면 0.1초
		if i == 36:
			_main.go_home()
		await _frame()
		if i % 2 == 0:
			_shot("home/%04d" % n)
			n += 1
		if i == 34:
			_shot("gameover")
	_log.append("홈: 메인 화면 %s, 장애물 %d, 음악 %s" % [not _main.started, _main.field.items.size(), AudioManager.is_music_on()])


func _mark() -> void:
	_main.started = true
	_main._view = 0.0
	_main._set_view(0.0)
	_main._hud.modulate.a = 0.0
	_main._title.visible = false
	_main._music_t = 0.0
	_main.advance(0.0, 0.0)
	_main.clear_pieces()
	_main.field.items.clear()
	for kind in _main._kind_meshes:  # 안개를 걷는다: 기호 모양만 본다
		for key in ["block", "reflect"]:
			_main._kind_meshes[kind][key].set_shader_parameter("fog_near", 500.0)
			_main._kind_meshes[kind][key].set_shader_parameter("fog_far", 600.0)
	var item := {"id": 9999, "lane": 1, "z": -45.0, "kind": ObstacleField.Kind.LOW, "beat": 0, "arrive": 45.0, "shape": ""}
	_main.field.items.append(item)
	_main._spawn_node(item)
	_main._sync_pieces()
	for i in 3:
		await RenderingServer.frame_post_draw
	_shot("mark_z45")
	var img := get_viewport().get_texture().get_image()
	var at: Vector2 = _main._camera.unproject_position(Vector3(0.0, 0.4, -45.0)) * img.get_width() / get_viewport().get_visible_rect().size.x
	var crop := img.get_region(Rect2i(int(at.x) - 40, int(at.y) - 30, 80, 60))
	crop.resize(320, 240, Image.INTERPOLATE_NEAREST)  # 4배 확대
	crop.save_png("%s/mark_z45_zoom.png" % _out)
	_log.append("z -45 블록 화면 자리 %s (창 %s)" % [str(at), str(img.get_size())])
