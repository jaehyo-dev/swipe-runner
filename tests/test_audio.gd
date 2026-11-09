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


const TEST_BEST := "user://test_best_audio.txt"


func _make_main(started := true) -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
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
	assert_eq(AudioServer.get_bus_volume_db(music), AudioManager.MUSIC_DB, "Music")
	assert_eq(AudioServer.get_bus_volume_db(sfx), AudioManager.SFX_DB, "SFX")
	assert_eq(AudioServer.get_bus_send(music), &"Master")
	assert_eq(AudioServer.get_bus_send(sfx), &"Master")
	assert_eq(AudioManager.music.bus, &"Music")


func test_소리_파일_길이와_음악_반복_설정() -> void:
	var want := {&"lane": 0.10, &"jump": 0.22, &"slide": 0.28, &"land": 0.37, &"crash": 0.43}
	for sound in want:
		var stream: AudioStreamWAV = AudioManager.SFX[sound]
		assert_true(absf(stream.get_length() - want[sound]) < 0.02, "%s %f" % [sound, stream.get_length()])
	assert_eq(AudioManager.TRACKS.size(), MusicLadder.STEPS.size())
	for i in AudioManager.TRACKS.size():
		var bgm: AudioStreamOggVorbis = AudioManager.TRACKS[i]
		assert_true(bgm.resource_path.ends_with(MusicLadder.STEPS[i]["file"] + ".ogg"), bgm.resource_path)
		assert_true(bgm.loop, "반복")
		assert_true(absf(bgm.get_length() - MusicLadder.lap_time(i)) < 0.001, "길이 %f" % bgm.get_length())


## 반복 이음매에 틈이 없으려면 곡을 읽은 표본이 한 바퀴 뒤에도 똑같아야 한다 (mix_audio 앞머리 빈 표본을 버린 결과)
func test_곡을_표본_단위로_읽으면_첫_표본부터_소리가_있고_한_바퀴_뒤_그대로_이어짐() -> void:
	for i in AudioManager.TRACKS.size():
		var frames := roundi(MusicLadder.lap_time(i) * AudioServer.get_mix_rate())
		var playback: AudioStreamPlayback = AudioManager.open_track(AudioManager.TRACKS[i])
		var head := playback.mix_audio(1.0, 64)
		assert_true(head[0] != Vector2.ZERO, "곡 %d 첫 표본" % i)
		var left := frames - 64
		while left > 0:
			var got := playback.mix_audio(1.0, mini(left, 4096))
			left -= got.size()
		var again := playback.mix_audio(1.0, 64)
		var worst := 0.0
		for k in 64:
			worst = maxf(worst, (again[k] - head[k]).length())
		assert_true(worst < 0.002, "곡 %d 이음매 차이 %f" % [i, worst])


## 곡을 8마디째부터 열어도 앞에서부터 읽은 것과 표본이 같아야 곡 갈아타기에 박이 어긋나지 않는다
func test_곡을_4마디_위치에서_열면_처음부터_읽은_표본과_같음() -> void:
	var rate := AudioServer.get_mix_rate()
	for i in [0, 3, 6]:
		var from := MusicLadder.span_time(i)
		var playback: AudioStreamPlayback = AudioManager.open_track(AudioManager.TRACKS[i])
		var left := roundi(from * rate)
		while left > 0:
			left -= playback.mix_audio(1.0, mini(left, 4096)).size()
		var want := playback.mix_audio(1.0, 64)
		var got: PackedVector2Array = AudioManager.open_track(AudioManager.TRACKS[i], from).mix_audio(1.0, 64)
		var worst := 0.0
		for k in 64:
			worst = maxf(worst, (got[k] - want[k]).length())
		assert_true(worst < 0.05, "곡 %d 차이 %f" % [i, worst])  # 경계가 표본 사이에 떨어지면 반 표본까지 어긋난 값이 나온다


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
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - (AudioManager.MUSIC_DB - 8.0)) < 0.01, "기본에서 -8 더 낮춤")
	var count := _log.size()
	AudioManager.play_lane(1)
	AudioManager.play_action(&"jump")
	assert_eq(_log.size(), count, "막힘")
	AudioManager._duck.custom_step(AudioManager.DUCK_TIME - 2.0 * AudioManager.DUCK_FADE)
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - (AudioManager.MUSIC_DB - 8.0)) < 0.01, "아직 낮음")
	AudioManager._duck.custom_step(AudioManager.DUCK_FADE + 0.01)
	assert_true(absf(AudioServer.get_bus_volume_db(bus) - AudioManager.MUSIC_DB) < 0.01, "1초 뒤 원래대로")
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
	var item := {"id": 9000, "lane": main.lane, "z": -0.6, "kind": ObstacleField.Kind.BLOCK, "beat": 0, "arrive": main.travel + 0.6}
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


func test_첫_입력_전에는_세상이_멈춰_있고_첫_입력이_음악을_켜고_동작으로도_처리됨() -> void:
	AudioManager.music.stop()
	var main := _make_main(false)
	while not main.prewarmed:
		await wait_frames()
	_start_log()
	var scroll: float = main._scroll
	var waiting_z: Array = main.field.items.map(func(i): return i["z"])
	assert_true(waiting_z.size() > 0, "장애물이 미리 놓여 있음")
	main.advance(30.0)
	assert_eq(main.travel, 0.0, "거리는 아직")
	assert_eq(main.field.items.map(func(i): return i["z"]), waiting_z, "장애물은 멈춰 있음")
	assert_eq(main._scroll, scroll, "길도 멈춰 있음")
	assert_false(AudioManager.music.playing, "음악은 아직")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	main._input(key)
	assert_true(main.started)
	assert_true(AudioManager.music.playing, "음악 시작")
	assert_eq(main.lane, 0, "첫 입력도 게임 동작")
	assert_eq(_names(), ["lane"])
	# 박 계산은 첫 입력(음악 0초) 기준이다
	var t: float = AudioManager.music_time
	assert_true(absf(t) < 0.2, "음악 0초 근처 %f" % t)
	assert_eq(main.field.travel, AudioManager.ladder.distance_at(t), "장애물 거리 = 음악 시간의 이동 거리")
	for item in main.field.items:
		assert_true(absf(item["z"] + RunLogic.SPEED * (item["beat"] * 0.6 - t)) < 0.001, "자기 박에 맞는 자리")
		assert_true(absf(main._obstacles[item["id"]].position.z - item["z"]) < 0.0001, "노드도 같은 자리")
	AudioManager.music.stop()
	main.queue_free()


func test_첫_터치도_시작이고_그대로_밀면_스와이프() -> void:
	AudioManager.music.stop()
	var main := _make_main(false)
	while not main.prewarmed:
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
	assert_true(absf(main.travel - RunLogic.SPEED * 1.5) < 0.000001)
	main.queue_free()


func test_음악을_시작하면_시간은_지연만큼_앞에서_출발() -> void:
	AudioManager.music.stop()
	AudioManager.start_music()
	assert_eq(AudioManager.music_time, -AudioServer.get_output_latency())
	AudioManager.music.stop()


func test_재시작하면_곡과_템포_구간이_처음으로_돌아감() -> void:
	AudioManager.start_music()
	AudioManager.ladder.plan(MusicLadder.span_time(0) - 6.5, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
	assert_eq(AudioManager.ladder.segments.size(), 2)
	var old: AudioStreamPlayer = AudioManager.music
	AudioManager.restart_music()
	assert_true(AudioManager.music != old, "새 플레이어로 겹쳐 넘어감")
	assert_true(old.playing, "지금 곡은 페이드 동안 남음")
	assert_true(AudioManager.music.playing)
	assert_eq(AudioManager.ladder.segments.size(), 1)
	assert_eq(AudioManager.ladder.segments[0]["step"], AudioManager.start_step)
	assert_true(AudioManager.music_time <= 0.0, "박 계산은 0초부터")
	AudioManager.music.stop()
	old.stop()


func test_부딪힌_뒤에는_다음_곡을_예약하지_않음() -> void:
	AudioManager.start_music()
	AudioManager._clock.time = MusicLadder.span_time(0) - 6.5  # 재생 위치가 이보다 뒤라 시계는 이 값을 유지한다
	AudioManager._blocked = true
	AudioManager._process(0.0)
	assert_eq(AudioManager.ladder.segments.size(), 1, "부딪힌 뒤에는 예약 안 함")
	AudioManager._blocked = false
	AudioManager._process(0.0)
	assert_eq(AudioManager.ladder.segments.size(), 2, "달리는 중이면 예약")
	AudioManager.music.stop()


## 출력 지연이 커서 이미 넣은 표본을 지난 경계도 멈추지 않고 넘어간다 (경계 계산이 음수가 되면 무한 반복)
func test_이미_넣은_표본을_지난_경계도_멈추지_않고_바뀜() -> void:
	AudioManager.start_music()
	AudioManager.music_time = MusicLadder.span_time(0) - 6.5
	AudioManager._pushed = roundi(MusicLadder.span_time(0) * AudioServer.get_mix_rate()) + 1000  # 경계보다 1000표본 뒤까지 넣은 상태
	AudioManager._plan_next_track()
	assert_eq(AudioManager._switch_frame, AudioManager._pushed)
	AudioManager.music.stop()
	AudioManager.music.play()
	AudioManager._gen = AudioManager.music.get_stream_playback()
	AudioManager._pump_generator()
	assert_eq(AudioManager._switch_frame, -1, "곡이 바뀜")
	AudioManager.music.stop()


## 제너레이터 안에서 곡이 바뀌는 표본을 직접 확인한다 (데스크톱·녹화 경로)
func test_데스크톱은_경계_표본에서_다음_곡으로_틈_없이_바뀜() -> void:
	AudioManager.start_music()
	var rate := AudioServer.get_mix_rate()
	AudioManager._pushed = roundi(40.0 * rate)  # 넣은 표본 수를 경계 바로 앞으로
	AudioManager._switch_frame = AudioManager._pushed + 100
	AudioManager._switch_step = 1
	var before: AudioStreamPlayback = AudioManager._feed
	# 버퍼가 가득 차 있으면 경계까지 못 넣으므로 새 제너레이터로 다시 연다
	AudioManager.music.stop()
	AudioManager.music.play()
	AudioManager._gen = AudioManager.music.get_stream_playback()
	AudioManager._pump_generator()
	assert_true(AudioManager._feed != before, "곡이 바뀜")
	assert_eq(AudioManager._switch_frame, -1)
	assert_true(AudioManager._pushed > roundi(40.0 * rate) + 100, "경계 뒤로도 이어서 넣음")
	AudioManager.music.stop()


## 150BPM 이상은 앞 전환이 일어나기 전에 다음 경계가 정해진다. 하나만 저장하면 단계를 건너뛴다
func test_데스크톱_곡_전환은_앞_전환이_끝날_때까지_기다림() -> void:
	AudioManager._switch_frame = 1000
	AudioManager._switch_step = 11
	AudioManager._waiting_switches.append({"frame": 2000, "step": 12, "from": 0.0})
	AudioManager._next_switch()
	assert_eq(AudioManager._switch_step, 11, "앞 전환이 그대로")
	AudioManager._switch_frame = -1
	AudioManager._pushed = 0
	AudioManager._next_switch()
	assert_eq(AudioManager._switch_step, 12, "다음 전환")
	assert_eq(AudioManager._switch_frame, 2000)
	assert_true(AudioManager._waiting_switches.is_empty())
	AudioManager._switch_frame = -1
