extends TestCase
## v0.4.1 길·장애물 아트의 규칙: 보이는 모양 = 판정 범위, 판정 값 그대로, 물방울 줄은 박에 닿음, 반사는 몸을 따라감.
## 충돌 소리·음악을 실제로 켜서 AudioManager 상태가 남는다. test_audio보다 뒤에 돌도록 파일 이름을 test_track_로 시작한다.

const K := ObstacleField.Kind
const STEP := 1.0 / 60.0
const TEST_BEST := "user://test_best_art.txt"


func _make_main(seed_value := 1234) -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = seed_value
	DirAccess.remove_absolute(TEST_BEST)
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	main.started = true
	return main


func _meshes(kind: K) -> Dictionary:
	return ArtMeshes.obstacle(kind)


## 값이 달라지면 게임이 달라지므로 일부러 숫자를 그대로 적어 둔다
func test_판정_값은_그대로() -> void:
	assert_eq(PlayerAction.HIT_X, 0.7)
	assert_eq(PlayerAction.HIT_Z, 0.7)
	assert_eq(ObstacleField.BLOCK_SIZE, 1.1)
	assert_eq(ObstacleField.BAR_WIDTH, 1.3)
	assert_eq(ObstacleField.BAR_DEPTH, 0.5)
	assert_eq(ObstacleField.LOW_TOP, 0.45)
	assert_eq(ObstacleField.HIGH_BOTTOM, 0.62)
	assert_eq(ObstacleField.HIGH_TOP, 1.32)
	assert_eq(PlayerAction.JUMP_HEIGHT, 1.6)
	assert_eq(PlayerAction.JUMP_TIME, 0.6)
	assert_eq(PlayerAction.SLIDE_TIME, 0.65)
	assert_eq(PlayerAction.CROUCH_SCALE, 0.45)
	assert_eq(RunLogic.LANE_WIDTH, 1.5)
	# 판정 함수의 표: 종류, dx, dz, 높이, 슬라이드 → 결과
	for row: Array in [
		[K.BLOCK, 0.0, 0.0, 0.0, false, true],
		[K.BLOCK, 0.0, 0.0, 1.6, false, true],  # 기둥은 넘을 수 없다
		[K.BLOCK, 0.71, 0.0, 0.0, false, false],
		[K.BLOCK, 0.0, 0.71, 0.0, false, false],
		[K.LOW, 0.0, 0.0, 0.44, false, true],
		[K.LOW, 0.0, 0.0, 0.45, false, false],
		[K.HIGH, 0.0, 0.0, 0.0, false, true],
		[K.HIGH, 0.0, 0.0, 0.0, true, false],
	]:
		assert_eq(PlayerAction.hits(row[0], row[1], row[2], row[3], row[4]), row[5], str(row))


func test_보이는_면이_판정_크기에_정확히_맞음() -> void:
	var cases := {
		K.BLOCK: [Vector3(1.1, 2.1, 1.1), 0.0],
		K.LOW: [Vector3(1.3, 0.45, 0.5), 0.0],
		K.HIGH: [Vector3(1.3, 0.7, 0.5), 0.62],
	}
	for kind in cases:
		var box: AABB = _meshes(kind)["glass"].get_aabb()
		assert_true(box.size.is_equal_approx(cases[kind][0]), "크기 %s: %s" % [kind, box.size])
		assert_true(is_equal_approx(box.position.y, cases[kind][1]), "아랫면 %s: %f" % [kind, box.position.y])
		assert_true(absf(box.position.x + box.size.x * 0.5) < 0.001 and absf(box.position.z + box.size.z * 0.5) < 0.001, "레인 가운데 %s" % kind)


func test_기둥은_점프보다_확실히_높음() -> void:
	assert_true(ObstacleField.BLOCK_HEIGHT - PlayerAction.JUMP_HEIGHT >= 0.4)


func test_막대에는_기둥이_없고_바닥_띠는_레인_안쪽() -> void:
	var half := RunLogic.LANE_WIDTH * 0.5
	var meshes := _meshes(K.HIGH)
	var lines: AABB = meshes["edges"].get_aabb()
	assert_true(lines.position.y >= ObstacleField.HIGH_BOTTOM - 0.1, "선이 막대 아래로 내려가지 않음 %f" % lines.position.y)
	assert_true(lines.position.x > -half, "선")
	var mirror: AABB = meshes["mirror"].get_aabb()
	assert_true(mirror.position.x > -half, "빛 띠")
	var band := 0.0
	var arrays: Array = meshes["mirror"].surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		if arrays[Mesh.ARRAY_VERTEX][i].y == 0.0:
			band = maxf(band, arrays[Mesh.ARRAY_COLOR][i].a)
	assert_true(band >= 0.6, "빛 띠가 또렷함 %f" % band)
	assert_true(band > 0.42, "v0.4.1보다 진함")


## 앞뒤 두 면이 겹쳐 보이므로 화면 불투명도는 1 - (1 - a)^2
func test_유리_면_불투명도는_55에서_70퍼센트() -> void:
	var main := _make_main()
	await wait_frames()
	var far: float = load("res://shaders/glass.gdshader").code.get_slice("far_alpha = ", 1).get_slice(";", 0).to_float()
	var through := func(a: float) -> float: return 1.0 - (1.0 - a) * (1.0 - a)
	assert_true(through.call(far) >= 0.55 and through.call(far) <= 0.7, "멀리 %f" % through.call(far))
	for kind in main.KINDS:
		var near: float = main._kind_meshes[kind]["glass"].get_shader_parameter("near_alpha")
		assert_true(through.call(near) >= 0.55 and through.call(near) <= 0.7, "종류 %d: %f" % [kind, through.call(near)])
	main.queue_free()


func test_반사는_바닥_아래이고_불투명도는_15에서_25퍼센트() -> void:
	for kind in [K.BLOCK, K.LOW, K.HIGH]:
		var arrays: Array = _meshes(kind)["mirror"].surface_get_arrays(0)
		var alphas := {}
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var a: float = arrays[Mesh.ARRAY_COLOR][i].a
			if a > 0.0 and arrays[Mesh.ARRAY_VERTEX][i].y < 0.0:
				assert_true(a <= 0.25 + 0.001, "불투명도 상한 %f" % a)
				alphas[snappedf(a, 0.01)] = true
		assert_true(alphas.has(0.15) and alphas.has(0.25), "면 15%%, 선 25%%: %s" % str(alphas))


func test_세_종류의_실루엣_높이가_다름() -> void:
	var pillar: AABB = _meshes(K.BLOCK)["glass"].get_aabb()
	var low: AABB = _meshes(K.LOW)["glass"].get_aabb()
	var high: AABB = _meshes(K.HIGH)["glass"].get_aabb()
	assert_true(pillar.end.y > high.end.y + 0.5, "기둥이 가장 키가 큼")
	assert_true(low.end.y < high.position.y, "턱 윗면이 막대 아랫면보다 아래: 막대 아래가 비어 보임")


func test_물방울_줄은_템포가_바뀌어도_박에_주인공_자리에_닿음() -> void:
	var ladder := MusicLadder.new(0)
	ladder.add_segment(19.2, 32, 1)
	ladder.add_segment(37.49, 64, 6)
	for beat in [0, 1, 31, 32, 33, 63, 64, 65, 500]:
		var t := ladder.time_of_beat(beat)
		assert_true(absf(BeatRows.row_z(ladder, t, beat)) < 0.000001, "박 %d" % beat)


func test_줄은_짝수_자리가_박이고_주인공_앞뒤를_덮으며_간격이_구간_속도를_따름() -> void:
	assert_true(BeatRows.is_beat_row(0))
	assert_false(BeatRows.is_beat_row(1))
	assert_eq(BeatRows.beat_of(0, 10.3), 9.0)
	assert_eq(BeatRows.beat_of(1, 10.3), 9.5)
	assert_eq(BeatRows.beat_of(4, 10.9), 11.0)
	for step in MusicLadder.STEPS.size():
		var ladder := MusicLadder.new(step)
		var t := 3.0
		var now := ladder.beat_at(t)
		assert_true(BeatRows.row_z(ladder, t, BeatRows.beat_of(0, now)) > 0.0, "주인공 뒤")
		assert_true(BeatRows.row_z(ladder, t, BeatRows.beat_of(BeatRows.COUNT - 1, now)) < ObstacleField.SPAWN_Z + 10.0, "장애물이 나오는 안개 근처까지")
		var gap := BeatRows.row_z(ladder, t, 5.0) - BeatRows.row_z(ladder, t, 6.0)
		assert_true(is_equal_approx(gap, MusicLadder.beat_distance(step)), "한 박 거리 %f" % gap)


func test_실제_줄_노드가_박에_주인공_자리에_닿음() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var ladder: MusicLadder = AudioManager.ladder
	for beat in [4.0, 7.0, 12.0]:
		main.advance(0.0, ladder.time_of_beat(beat))
		var slot := int((beat - BeatRows.beat_of(0, beat)) * 2.0) * 2
		assert_true(absf(main._droplets.multimesh.get_instance_transform(slot).origin.z) < 0.000001, "박 %f" % beat)
	main.queue_free()


func test_박마다_1_15배까지_부풀고_0_15초에_돌아옴() -> void:
	assert_eq(BeatRows.pulse(0.0), 1.0)
	assert_eq(BeatRows.pulse(BeatRows.PULSE_TIME), 1.0)
	assert_eq(BeatRows.pulse(0.3), 1.0)
	var peak := 0.0
	for i in 150:
		peak = maxf(peak, BeatRows.pulse(i * 0.001))
	assert_true(absf(peak - 1.15) < 0.001, "최대 %f" % peak)


func test_물방울_노드는_이동_거리를_따르고_멈추면_부풂과_반짝임이_꺼짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	main.advance(1.8 + 0.03)  # 3박(1.8초) 0.03초 뒤
	var mat: ShaderMaterial = main._droplet_material
	assert_eq(main._droplets.position.z, 0.0, "달리는 동안 노드는 그대로이고 줄 z가 움직인다")
	assert_true(mat.get_shader_parameter("pulse") > 1.1, "박 직후 부풂")
	main.advance(0.2)
	assert_eq(mat.get_shader_parameter("pulse"), 1.0, "0.15초 뒤 돌아옴")
	var item := {"id": 7000, "lane": main.lane, "z": 0.0, "kind": K.BLOCK, "beat": 0, "arrive": main.travel}
	main.field.items.append(item)
	main._spawn_node(item)
	main.advance(STEP)
	assert_true(main.dead, "부딪힘")
	assert_eq(mat.get_shader_parameter("pulse"), 1.0)
	assert_eq(mat.get_shader_parameter("sparkle_on"), 0.0, "멈춘 줄이 계속 빛나지 않음")
	var z: float = main._droplets.position.z
	main.advance(STEP)
	assert_true(main._droplets.position.z > z, "느려지는 동안 장애물과 같이 다가옴")
	main.restart()
	assert_eq(main._droplets.position.z, 0.0, "밀린 만큼 되돌림")
	assert_eq(mat.get_shader_parameter("appear"), 0.0, "재시작 때 '퐁'으로 다시 나타남")
	assert_eq(mat.get_shader_parameter("sparkle_on"), 1.0)
	main.queue_free()


func test_대기_화면에서는_줄이_반짝이지_않고_출발하면_반짝임() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	var on: Variant = main._droplet_material.get_shader_parameter("sparkle_on")
	assert_true(on == null or on == 0.0, "대기 중 꺼짐")
	main.begin()
	assert_eq(main._droplet_material.get_shader_parameter("sparkle_on"), 1.0)
	main.queue_free()


func test_주인공_반사는_모양이_변하는_대로_따라감() -> void:
	var runner := Runner.new()
	add_child(runner)
	await wait_frames()
	var check := func(label: String) -> void:
		assert_eq(runner._mirror.scale, runner._body.scale * Vector3(1, -1, 1), label + " 크기")
		assert_eq(runner._mirror.position, runner._body.position * Vector3(1, -1, 1), label + " 위치")
		for param in ["lean", "sag", "drag", "rim_wave", "flat_bottom"]:
			assert_eq(runner._mirror_mat.get_shader_parameter(param), runner._mat.get_shader_parameter(param), "%s %s" % [label, param])
	assert_eq(runner._mirror.mesh, runner._body.mesh, "같은 메시")
	assert_eq(runner._mirror_mat.get_shader_parameter("mirror_alpha"), Runner.MIRROR_ALPHA)
	assert_true(Runner.MIRROR_ALPHA >= 0.15 and Runner.MIRROR_ALPHA <= 0.25)
	runner.lift = 1.0
	for i in 6:
		runner.step_shape(STEP)
		runner._process(STEP)
	check.call("점프")
	runner.lift = 0.0
	runner.crouch = 1.0
	for i in 6:
		runner.step_shape(STEP)
		runner._process(STEP)
	check.call("슬라이드")
	runner.queue_free()


func test_재시작_뒤_새_모양도_바닥에서_솟음() -> void:
	var main := _make_main()
	await wait_frames()
	main.advance(1.0)
	main.dead = true
	main.restart()
	for item in main.field.items:
		var node: Node3D = main._obstacles[item["id"]]
		assert_true(node.scale.y < 0.01, "높이 0에서 시작")
		assert_eq(node.position.y, 0.0, "원점이 바닥")
		assert_eq(node.get_child_count(), 2, "선 + 반사도 같이 늘어남")
	main.queue_free()


func test_자동_플레이어_시드_5개_3분_충돌_없음_사다리를_끝까지_오름() -> void:
	for seed_value in [11, 143, 2024, 7777, 90001]:
		var ladder := MusicLadder.new(0)
		AudioManager.ladder = ladder
		var main := _make_main(seed_value)
		await wait_frames()
		var t := 0.0
		var last_input := -INF
		while t < 180.0 and not main.dead:
			t += STEP
			ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
			main.advance(STEP, t)
			if main.runner._move_tween and main.runner._move_tween.is_valid():
				main.runner._move_tween.custom_step(STEP)
			var dir := AutoPlayer.decide(main.field.items, main.lane, main.player, main.speed, t - last_input)
			if dir != SwipeDetector.Dir.NONE:
				main.apply_swipe(dir)
				last_input = t
		assert_false(main.dead, "시드 %d: %.1f초에 충돌" % [seed_value, t])
		assert_eq(ladder.segments.size(), MusicLadder.STEPS.size(), "시드 %d: 사다리를 끝까지 오름" % seed_value)
		main.queue_free()
		await wait_frames()
	AudioManager.ladder = MusicLadder.new(0)


## 첫 입력의 음악 시작이 사다리를 새로 만든다. 장애물 목록이 옛 사다리를 보면 경계 뒤 장애물의 도착 거리가 어긋난다.
func test_첫_입력_뒤_장애물은_음악의_사다리로_경계를_넘어_박에_도착() -> void:
	AudioManager.music.stop()
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	main.begin()
	assert_eq(main.field.ladder, AudioManager.ladder, "같은 사다리")
	var ladder: MusicLadder = AudioManager.ladder
	var edge := MusicLadder.span_time(0)
	ladder.plan(edge - 6.5, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
	main.field.step(ladder.distance_at(edge - 1.0))
	var crossing: Array = main.field.items.filter(func(item): return item["beat"] > 32.0)
	assert_true(crossing.size() > 0, "경계를 넘는 장애물이 있음")
	for item: Dictionary in crossing:
		assert_true(absf(item["arrive"] - ladder.distance_of_beat(item["beat"])) < 0.000001, "새 속도로 계산한 도착 거리")
		assert_true(item["arrive"] > 32 * 6.0 + (item["beat"] - 32.0) * 6.0, "경계 뒤 한 박은 6보다 멂")
	AudioManager.music.stop()
	main.queue_free()


## --- v0.5.0 색 진하기 ---
func _sky_top(main: Node3D) -> Color:
	return main._sky_material.get_shader_parameter("top")


func test_색은_속도를_따라_진해지고_재질을_새로_만들지_않음() -> void:
	var ladder := MusicLadder.new(0)
	AudioManager.ladder = ladder
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var glass: ShaderMaterial = main._kind_meshes[K.BLOCK]["glass"]
	main.advance(0.0, 1.0)
	assert_eq(main._tint, 0.0)
	assert_true(_sky_top(main).is_equal_approx(Color("0b0a24")), "t=0 하늘")
	assert_true(glass.get_shader_parameter("tint").is_equal_approx(Color("bfe6ff")))
	assert_true(main._env.fog_light_color.is_equal_approx(Color("3a2470")), "안개 = 지평선")
	ladder.add_segment(19.2, 32, 6)
	main.advance(0.0, 19.2 + 60.0 / 130.0 * 4.0)  # 2마디의 절반
	assert_true(absf(main._tint - 0.5) < 0.001, "절반 %f" % main._tint)
	main.advance(0.0, 30.0)
	assert_eq(main._tint, 1.0)
	assert_true(_sky_top(main).is_equal_approx(Color("06021a")), "t=1 하늘")
	assert_true(glass.get_shader_parameter("tint").is_equal_approx(Color("7cc8ff")))
	assert_eq(main._kind_meshes[K.BLOCK]["glass"], glass, "같은 재질")
	var node: Node3D = main._make_obstacle(K.HIGH, 1, -10.0)
	assert_true(node.get_child(1).material_override.get_shader_parameter("glass_color").is_equal_approx(Color("ff1fb8")), "반사도 같은 색")
	node.free()
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


func test_빛날_때도_난간과_물방울은_상한을_넘지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	for t in [0.0, 0.5, 1.0]:
		main._tint = -1.0
		main._apply_tint(t)
		main._set_flash(1.0)
		var rail: Color = main._rail_material.get_shader_parameter("color")
		var peak := maxf(rail.r, maxf(rail.g, rail.b))
		assert_true(peak * main._rail_material.get_shader_parameter("energy") <= main.ROAD_PEAK_MAX + 0.001, "난간 t=%f" % t)
		assert_true(peak * main._droplet_material.get_shader_parameter("max_energy") <= main.ROAD_PEAK_MAX + 0.001, "물방울 t=%f" % t)
		main._set_flash(0.0)
		assert_true(is_equal_approx(main._rail_material.get_shader_parameter("energy"), SpeedPalette.at(t)["rail_energy"]), "평소 빛 세기")
	main.queue_free()


func test_재시작하면_색이_0_5초_동안_돌아감() -> void:
	var ladder := MusicLadder.new(6)
	AudioManager.ladder = ladder
	AudioManager.start_step = 6
	var main := _make_main()
	await wait_frames()
	main.advance(0.0, 1.0)
	assert_eq(main._tint, 1.0)
	AudioManager.start_step = 0
	main.dead = true
	main.restart()
	assert_eq(AudioManager.ladder.segments[0]["step"], 0, "100BPM으로")
	var from: float = main._tint
	assert_eq(from, 1.0, "재시작 순간 끊기지 않음")
	var clock: float = main._tint_clock
	var at := func(t: float) -> float:
		main.advance(0.0, clock + t)
		return main._tint
	var mid: float = at.call(0.25)
	assert_true(absf(mid - 0.5) < 0.001, "0.25초 %f" % mid)
	assert_eq(at.call(0.5), 0.0, "0.5초에 t=0")
	assert_eq(main.speed, 10.0, "속도 10")
	assert_true(_sky_top(main).is_equal_approx(Color("0b0a24")))
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()
