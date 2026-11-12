extends TestCase
## 일시정지(버튼·자동·3·2·1 이어 하기·HOME), 설정 패널(크기·진동·안내 다시 보기 저장), 진동 호출 시점.

const TEST_BEST := "user://test_best_pause.txt"


func _make_main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	DirAccess.remove_absolute(TEST_BEST)
	DirAccess.remove_absolute(TEST_BEST.get_basename() + "_settings.cfg")
	main.best_path = TEST_BEST
	add_child(main)
	main.haptics = Haptics.new(true)  # 진동을 지원하는 기기처럼 (기록만 남는다)
	while not main.warmed:
		await wait_frames()
	return main


func _done(main: Node3D) -> void:
	get_tree().paused = false
	AudioManager.set_held(false)
	AudioManager.music.stop()
	main.queue_free()


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _events(main: Node3D) -> Array:
	return main.haptics.sent.map(func(e: Dictionary) -> int: return e["event"])


func test_일시정지_버튼은_플레이_중에만_보인다() -> void:
	var main: Node3D = await _make_main()
	assert_false(main._pause_btn.is_visible_in_tree(), "메인 화면: 없음")
	main.begin()
	assert_true(main._pause_btn.visible, "플레이 중: 왼쪽 위")
	assert_true(_center(main._pause_btn).x < 200 and _center(main._pause_btn).y < 200)
	main._game_over({"kind": ObstacleField.Kind.BLOCK, "lane": 1, "z": 0.0})
	assert_false(main._pause_btn.visible, "게임 오버: 없음")
	main.pause()
	assert_false(main.paused, "게임 오버에서는 일시정지하지 않음")
	main.restart()
	assert_true(main._pause_btn.visible, "다시 시작: 다시 보임")
	_done(main)


func test_일시정지하면_세상과_음악이_멈추고_RESUME은_3_2_1_뒤_이어진다() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	await wait_frames(20)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = _center(main._pause_btn)
	main._input(touch)
	assert_true(main.paused and get_tree().paused, "‖ 버튼으로 멈춤")
	assert_true(main._pause_menu.visible and main._pause_menu.title.text == "PAUSED")
	assert_true(AudioManager.music.stream_paused, "음악도 그 자리에서 멈춤")
	var t: float = AudioManager.music_time
	var travel: float = main.travel
	await wait_frames(15)
	assert_eq(AudioManager.music_time, t, "음악 시간이 서 있다")
	assert_eq(main.travel, travel, "세상도 서 있다")
	main.apply_swipe(SwipeDetector.Dir.LEFT)  # (직접 부르면 움직이지만) 화면 입력은 막힌다
	main.lane = 1
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	main._input(key)
	assert_eq(main.lane, 1, "멈춘 동안 게임 입력 없음")
	main._pause_menu.tap(_center(main._pause_menu.buttons["RESUME"]))
	assert_true(main._pause_menu.counting, "숫자 세기")
	var digits: Array[String] = []
	while main.paused:
		var text: String = main._pause_menu.count_label.text
		if main._pause_menu.count_label.visible and (digits.is_empty() or digits[-1] != text):
			digits.append(text)
		assert_eq(AudioManager.music_time, t, "숫자 동안 음악·판정 없음")
		await wait_frames()
	assert_eq(digits, ["3", "2", "1"])
	assert_false(get_tree().paused)
	assert_false(AudioManager.music.stream_paused)
	assert_true(main._pause_btn.visible)
	await wait_frames(10)
	assert_true(AudioManager.music_time > t, "음악이 이어진다")
	_done(main)


func test_숫자_세는_중에_다시_가려지면_일시정지_화면으로() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	await wait_frames(5)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(main.paused, "창이 포커스를 잃으면 자동 일시정지")
	main._pause_menu.resume_pressed.emit()
	assert_true(main._pause_menu.counting)
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_false(main._pause_menu.counting, "다시 일시정지 화면")
	assert_true(main._pause_menu.buttons["RESUME"].visible)
	assert_true(main.paused and get_tree().paused)
	_done(main)


func test_메인_화면에서는_자동_일시정지하지_않음() -> void:
	var main: Node3D = await _make_main()
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(main.paused)
	assert_false(get_tree().paused)
	_done(main)


func test_일시정지의_HOME은_페이드로_메인_화면에_가고_멈춤을_푼다() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	await wait_frames(5)
	main.pause()
	main._pause_menu.tap(_center(main._pause_menu.buttons["HOME"]))
	await get_tree().create_timer(main.HOME_FADE + 0.1).timeout
	assert_false(main.started, "메인 화면")
	assert_false(main.paused)
	assert_false(get_tree().paused)
	assert_false(main._pause_menu.visible)
	assert_false(main._pause_btn.is_visible_in_tree())
	_done(main)


func test_설정은_크기_진동_안내를_바로_적용하고_저장한다() -> void:
	var main: Node3D = await _make_main()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = _center(main._title.gear)
	main._input(touch)
	var panel: SettingsPanel = main._settings
	assert_true(panel.visible, "메인 화면 톱니로 열림")
	assert_true(main._title.gear.get_global_rect().end.x <= main._title.sound.get_global_rect().position.x + 1.0, "톱니는 소리 버튼 왼쪽")
	panel.tap(panel.music_slider.get_global_rect().position)  # 왼쪽 끝: 0
	assert_eq(main.save.music, 0.0)
	assert_true(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) <= -60.0, "음악 꺼짐")
	panel.tap(_center(panel.sfx_slider))
	assert_true(absf(main.save.sfx - 0.5) < 0.05, "가운데: 반")
	assert_true(panel._rows["VIBRATION"].is_visible_in_tree(), "지원하는 기기는 진동 줄을 보인다")
	panel.tap(_center(panel._rows["VIBRATION"]))
	assert_false(main.save.vibration)
	assert_false(main.haptics.enabled)
	assert_eq(panel.vibration_value.text, "OFF")
	assert_eq(panel.graphics_value.text, "AUTO", "GRAPHICS 처음은 AUTO")
	panel.tap(_center(panel._rows["GRAPHICS"]))
	assert_eq(panel.graphics_value.text, "HIGH")
	assert_eq(main._effect_level, 0)
	panel.tap(_center(panel._rows["GRAPHICS"]))
	assert_eq(panel.graphics_value.text, "LOW")
	assert_eq(main._effect_level, QualityGuard.LEVELS, "바로 적용")
	main.save.plays = 10
	panel.tap(_center(panel._rows["SHOW GUIDE"]))
	assert_eq(main.save.guide_left, SaveData.GUIDE_RUNS)
	panel.tap(_center(panel.done_label))
	assert_false(panel.visible, "DONE으로 닫힘")
	var again := SaveData.new(main.save._path)
	assert_eq(again.music, 0.0, "저장")
	assert_false(again.vibration)
	assert_true(again.shows_guide(), "다음 판에 안내")
	assert_eq(again.graphics, "low", "GRAPHICS 저장")
	panel.open(main.save, main.haptics)
	panel.tap(_center(panel._rows["GRAPHICS"]))
	assert_eq(main.save.graphics, "auto", "LOW 다음은 AUTO")
	assert_eq(main._effect_level, 0, "AUTO는 처음부터 다시 판단")
	panel.close()
	AudioManager.set_volumes(1.0, 1.0)
	_done(main)


func test_왼쪽_위_세_번_탭으로_성능_표시를_켜고_끄고_시작하지_않음() -> void:
	var main: Node3D = await _make_main()
	var tap := func() -> void:
		for pressed in [true, false]:
			var touch := InputEventScreenTouch.new()
			touch.pressed = pressed
			touch.position = PerfStats.TAP_ZONE.get_center()
			main._input(touch)
	assert_false(main._perf_label.visible)
	for i in 3:
		tap.call()
	assert_true(main._perf_label.visible, "세 번 탭")
	assert_false(main.started, "메인 화면 탭으로 시작하지 않음")
	assert_true(main._perf_label.text.begins_with("FPS"), main._perf_label.text)
	assert_true(main._perf_label.text.contains("QUALITY 0 AUTO"))
	for i in 3:
		tap.call()
	assert_false(main._perf_label.visible, "다시 세 번이면 숨김")
	var f3 := InputEventKey.new()
	f3.pressed = true
	f3.keycode = KEY_F3
	main._input(f3)
	assert_true(main._perf_label.visible, "PC는 F3")
	_done(main)


func test_진동을_지원하지_않으면_설정에서_숨김() -> void:
	var main: Node3D = await _make_main()
	main.haptics = Haptics.new(false)
	main.open_settings()
	assert_false(main._settings._rows["VIBRATION"].is_visible_in_tree())
	assert_eq(main._settings._rows["SHOW GUIDE"].position.y, SettingsPanel.TOP + SettingsPanel.ROW * 3, "아래 줄이 올라온다 (MUSIC·SFX·GRAPHICS 다음)")
	main._settings.close()
	_done(main)


func test_일시정지의_SETTINGS는_일시정지_위에_열리고_닫으면_돌아온다() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	main.pause()
	main._pause_menu.tap(_center(main._pause_menu.buttons["SETTINGS"]))
	assert_true(main._settings.visible)
	assert_true(main._pause_menu.blocked, "설정 뒤 일시정지 화면은 누름을 받지 않음")
	main._settings.tap(Vector2(5, 5))  # 패널 바깥: 닫힘
	assert_false(main._settings.visible)
	assert_false(main._pause_menu.blocked)
	assert_true(main.paused, "여전히 일시정지")
	_done(main)


func test_진동은_충돌_PERFECT_새_기록에만() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	for dir in [SwipeDetector.Dir.LEFT, SwipeDetector.Dir.UP, SwipeDetector.Dir.DOWN]:
		main.apply_swipe(dir)
	assert_eq(_events(main), [], "레인 이동·점프·슬라이드는 진동 없음")
	main._on_close({"lane": 0}, 100)
	main._on_new_record()
	main._game_over({"kind": ObstacleField.Kind.BLOCK, "lane": 1, "z": 0.0})
	assert_eq(_events(main), [Haptics.Event.PERFECT, Haptics.Event.NEW_BEST, Haptics.Event.CRASH])
	_done(main)


func test_숫자가_끝나고_소리를_기다리는_사이_가려져도_다시_일시정지() -> void:
	var main: Node3D = await _make_main()
	main.begin()
	main.pause()
	main._pause_menu.hide()  # 숫자가 끝난 순간 (_on_resumed가 소리를 기다리는 중)
	main.pause()
	assert_true(main._pause_menu.visible, "일시정지 화면이 다시 보임")
	assert_true(main.paused and get_tree().paused)
	assert_false(AudioManager.is_running(), "소리도 다시 멈춤")
	_done(main)


func test_준비_중에_시작을_눌러_두고_설정을_열면_시작을_취소한다() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	while not main.prewarmed:
		await wait_frames()
	main._begin_waiting = true  # 준비가 끝나기 전에 시작을 누름
	main.open_settings()
	while not main.warmed:
		await wait_frames()
	assert_false(main.started, "설정 뒤에서 시작하지 않음")
	main._settings.close()
	_done(main)
