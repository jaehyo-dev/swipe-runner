extends TestCase
## 소리 파일·버스·재생 시점 테스트. 실제로 들리는지는 사용자 귀와 review/v0.3.0/ 영상으로 확인한다.

const Dir := SwipeDetector.Dir
const STEP := 1.0 / 60.0

var _log: Array = []


func _start_log() -> void:
	_log.clear()
	AudioManager.unblock()
	AudioManager.played.connect(_on_played)


func _on_played(sound: StringName, pitch: float) -> void:
	_log.append([sound, pitch])


func _names() -> Array:
	return _log.map(func(x): return String(x[0]))


func _exit_tree() -> void:
	if AudioManager.played.is_connected(_on_played):
		AudioManager.played.disconnect(_on_played)
	AudioManager.unblock()


func _make_main(started := true) -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	main.set_process(false)
	main.started = started
	return main


func _semitones(pitch: float) -> float:
	return 12.0 * log(pitch) / log(2.0)


func test_버스와_기본_크기() -> void:
	assert_eq(AudioServer.get_bus_name(0), "Master")
	var music := AudioServer.get_bus_index(&"Music")
	var sfx := AudioServer.get_bus_index(&"SFX")
	assert_true(music > 0 and sfx > 0, "버스 있음")
	assert_eq(AudioServer.get_bus_volume_db(music), -6.0, "Music")
	assert_eq(AudioServer.get_bus_volume_db(sfx), 0.0, "SFX")
	assert_eq(AudioServer.get_bus_send(music), &"Master")
	assert_eq(AudioServer.get_bus_send(sfx), &"Master")
	assert_eq(AudioManager.music.bus, &"Music")


func test_소리_파일_길이와_음악_반복_설정() -> void:
	var want := {&"lane": 0.10, &"jump": 0.22, &"slide": 0.28, &"land": 0.37, &"crash": 0.43}
	for sound in want:
		var stream: AudioStreamWAV = AudioManager.SFX[sound]
		assert_true(absf(stream.get_length() - want[sound]) < 0.02, "%s %f" % [sound, stream.get_length()])
	var bgm: AudioStreamOggVorbis = AudioManager.BGM
	assert_true(bgm.loop, "반복")
	assert_eq(bgm.loop_offset, 0.0)
	assert_true(absf(bgm.get_length() - BeatClock.LOOP) < 0.001, "길이 %f" % bgm.get_length())


func test_효과음은_6개_이상_겹쳐_남() -> void:
	assert_true(AudioManager.POOL_SIZE >= 6)
	_start_log()
	var players := {}
	for i in AudioManager.POOL_SIZE:
		players[AudioManager._next] = true
		AudioManager.play_action(&"jump")
	assert_eq(players.size(), AudioManager.POOL_SIZE, "매번 다른 플레이어")


func test_레인_이동은_왼쪽_낮게_오른쪽_높게_무작위_반반음() -> void:
	_start_log()
	var seen := {}
	for i in 200:
		AudioManager.play_lane(-1)
		var left := _semitones(_log[-1][1])
		assert_true(left >= -1.5001 and left <= -0.4999, "왼쪽 %f" % left)
		AudioManager.play_lane(1)
		var right := _semitones(_log[-1][1])
		assert_true(right >= 0.4999 and right <= 1.5001, "오른쪽 %f" % right)
		seen[snappedf(right, 0.01)] = true
	assert_true(seen.size() > 20, "매번 달라짐")


func test_점프_슬라이드_착지는_무작위_반반음_충돌은_그대로() -> void:
	_start_log()
	for i in 100:
		AudioManager.play_action(&"land")
		assert_true(absf(_semitones(_log[-1][1])) <= 0.5001, "%f" % _log[-1][1])
	AudioManager.play_crash()
	assert_eq(_log[-1], [&"crash", 1.0])


func test_충돌_뒤엔_다시_시작할_때까지_다른_효과음_없음_음악은_잠깐_낮아짐() -> void:
	_start_log()
	var bus := AudioServer.get_bus_index(&"Music")
	AudioManager.play_crash()
	AudioManager._duck.custom_step(AudioManager.DUCK_FADE)
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - (-14.0)) < 0.01, "기본 -6에서 -8 더 낮춤")
	var count := _log.size()
	AudioManager.play_lane(1)
	AudioManager.play_action(&"jump")
	assert_eq(_log.size(), count, "막힘")
	AudioManager._duck.custom_step(AudioManager.DUCK_TIME - 2.0 * AudioManager.DUCK_FADE)
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - (-14.0)) < 0.01, "아직 낮음")
	AudioManager._duck.custom_step(AudioManager.DUCK_FADE + 0.01)
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - (-6.0)) < 0.01, "1초 뒤 원래대로")
	AudioManager.unblock()
	AudioManager.play_lane(1)
	assert_eq(_log.size(), count + 1, "다시 남")


func test_동작과_같은_호출_안에서_소리가_남() -> void:
	var main := _make_main()
	await wait_frames()
	_start_log()
	main.apply_swipe(Dir.LEFT)
	assert_eq(_names(), ["lane"], "레인 이동")
	assert_true(_semitones(_log[0][1]) < 0.0, "왼쪽은 낮게")
	main.apply_swipe(Dir.LEFT)
	assert_eq(_names(), ["lane"], "끝에서 더 못 가면 소리 없음")
	_log.clear()
	main.apply_swipe(Dir.UP)
	assert_eq(_names(), ["jump"], "점프")
	main.queue_free()


func test_착지는_점프_뒤에만_슬라이드가_끝날_때는_소리_없음() -> void:
	var main := _make_main()
	await wait_frames()
	_start_log()
	main.apply_swipe(Dir.UP)
	main.advance(PlayerAction.JUMP_TIME + STEP)
	assert_eq(_names(), ["jump", "land"])
	_log.clear()
	main.apply_swipe(Dir.DOWN)
	assert_eq(_names(), ["slide"])
	main.advance(PlayerAction.SLIDE_TIME + STEP)
	assert_eq(_names(), ["slide"], "슬라이드 끝은 조용")
	main.queue_free()


func test_공중_아래_스와이프는_땅에_닿아_슬라이드가_시작될_때_소리() -> void:
	var main := _make_main()
	await wait_frames()
	_start_log()
	main.apply_swipe(Dir.UP)
	main.advance(0.2)
	main.apply_swipe(Dir.DOWN)
	assert_eq(_names(), ["jump"], "떨어지는 동안은 아직")
	main.advance(PlayerAction.DROP_MAX_TIME + STEP)
	assert_eq(_names(), ["jump", "slide"], "닿는 순간 슬라이드, 착지 소리는 없음")
	main.queue_free()


func test_저장된_입력은_실행될_때_소리_남() -> void:
	var main := _make_main()
	await wait_frames()
	_start_log()
	main.apply_swipe(Dir.UP)
	main.advance(PlayerAction.JUMP_TIME - 0.1)
	main.apply_swipe(Dir.UP)
	assert_eq(_names(), ["jump"], "저장만")
	main.advance(0.1 + STEP)
	assert_eq(_names(), ["jump", "land", "jump"], "착지 후 바로 다시 점프")
	main.queue_free()


func test_충돌_소리_뒤_막혔다가_다시_시작하면_풀림_음악은_계속() -> void:
	var main := _make_main()
	await wait_frames()
	_start_log()
	var item := {"id": 9000, "lane": main.lane, "z": -0.6, "kind": ObstacleField.Kind.BLOCK, "beat": 0}
	main.field.items.append(item)
	main._spawn_node(item)
	main.advance(STEP)
	assert_true(main.dead)
	assert_eq(_names(), ["crash"])
	main.advance(main.RESTART_DELAY)
	AudioManager.start_music()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	main._input(key)
	assert_false(main.dead, "다시 시작")
	assert_true(AudioManager.music.playing, "음악이 끊기지 않음")
	main.apply_swipe(Dir.UP)
	assert_eq(_names(), ["crash", "jump"])
	main.queue_free()


func test_첫_입력_전에는_길만_흐르고_첫_입력이_음악을_켜고_동작으로도_처리됨() -> void:
	AudioManager.music.stop()
	var main := _make_main(false)
	await wait_frames()
	_start_log()
	var scroll: float = main._scroll
	main.advance(30.0)
	assert_eq(main.elapsed, 0.0, "거리는 아직")
	assert_eq(main.field.items.size(), 0, "장애물 없음")
	assert_true(main._scroll > scroll, "길은 흐름")
	assert_false(AudioManager.music.playing, "음악은 아직")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	main._input(key)
	assert_true(main.started)
	assert_true(AudioManager.music.playing, "음악 시작")
	assert_eq(main.lane, 0, "첫 입력도 게임 동작")
	assert_eq(_names(), ["lane"])
	AudioManager.music.stop()
	main.queue_free()


func test_첫_터치도_시작이고_그대로_밀면_스와이프() -> void:
	AudioManager.music.stop()
	var main := _make_main(false)
	await wait_frames()
	_start_log()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(100, 600)
	main._input(touch)
	assert_true(AudioManager.music.playing)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(300, 600)
	main._input(drag)
	assert_eq(main.lane, 2)
	assert_eq(_names(), ["lane"])
	AudioManager.music.stop()
	main.queue_free()


func test_음악_시간을_받으면_세상이_그_차이만큼_움직임() -> void:
	var main := _make_main()
	await wait_frames()
	main.advance(1.0, 1.0)
	var z: float = main.field.items[0]["z"]
	main.advance(0.001, 1.5)  # 프레임 시간과 상관없이
	assert_true(absf(main.field.items[0]["z"] - (z + RunLogic.SPEED * 0.5)) < 0.000001)
	assert_true(absf(main.elapsed - 1.5) < 0.000001)
	main.queue_free()


func test_음악을_시작하면_시간은_지연만큼_앞에서_출발() -> void:
	AudioManager.music.stop()
	AudioManager.start_music()
	assert_eq(AudioManager.music_time, -AudioServer.get_output_latency())
	AudioManager.music.stop()
