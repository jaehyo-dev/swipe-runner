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


## 몸통 메시에서 면(UV.x == 0) 또는 테두리 관(UV.x > 0) 꼭짓점의 영역
func _box(kind: K, lines: bool) -> AABB:
	var arrays: Array = _meshes(kind)["body"].surface_get_arrays(0)
	var box := AABB()
	var first := true
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		if (arrays[Mesh.ARRAY_TEX_UV][i].x > 0.0) != lines:
			continue
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		box = AABB(p, Vector3.ZERO) if first else box.expand(p)
		first = false
	return box


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
		var box: AABB = _box(kind, false)
		assert_true(box.size.is_equal_approx(cases[kind][0]), "크기 %s: %s" % [kind, box.size])
		assert_true(is_equal_approx(box.position.y, cases[kind][1]), "아랫면 %s: %f" % [kind, box.position.y])
		assert_true(absf(box.position.x + box.size.x * 0.5) < 0.001 and absf(box.position.z + box.size.z * 0.5) < 0.001, "레인 가운데 %s" % kind)


func test_기둥은_점프보다_확실히_높음() -> void:
	assert_true(ObstacleField.BLOCK_HEIGHT - PlayerAction.JUMP_HEIGHT >= 0.4)


func test_막대에는_기둥이_없고_아래_빛_웅덩이는_막대보다_좁고_가장자리가_사라짐() -> void:
	var half := RunLogic.LANE_WIDTH * 0.5
	var meshes := _meshes(K.HIGH)
	var lines: AABB = _box(K.HIGH, true)
	assert_true(lines.position.y >= ObstacleField.HIGH_BOTTOM - 0.1, "선이 막대 아래로 내려가지 않음 %f" % lines.position.y)
	assert_true(lines.position.x > -half, "선")
	var center := 0.0
	var arrays: Array = meshes["mirror"].surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		if p.y != 0.0:
			continue
		var c: Color = arrays[Mesh.ARRAY_COLOR][i]
		center = maxf(center, c.a)
		assert_eq(c.b, 1.0, "멀어도 그리는 바닥 흔적")
		assert_true(absf(p.x) < ObstacleField.BAR_WIDTH * 0.5, "막대 폭보다 좁음 %f" % p.x)
		var r := Vector2(p.x / ArtMeshes.POOL_HALF.x, p.z / ArtMeshes.POOL_HALF.y).length()
		assert_true(r <= 1.001, "타원 안")
		if r > 0.999:
			assert_eq(c.a, 0.0, "가장자리 0%%")
	assert_true(center > 0.2 and center <= 0.35, "가운데 %f" % center)


## 자기 뒤쪽 테두리와 화살이 앞으로 비쳐 두 겹으로 보이지 않게 뒷면 선은 만들지 않는다
func test_테두리는_앞면에만_있음() -> void:
	for kind: K in [K.LOW, K.HIGH]:
		assert_true(_box(kind, true).position.z > 0.0, "%d: 뒤쪽 선 없음 %f" % [kind, _box(kind, true).position.z])
	assert_true(_box(K.BLOCK, true).position.z > -0.1, "기둥: 카메라 쪽 모서리만 %f" % _box(K.BLOCK, true).position.z)


func test_기둥에는_바닥에_부드러운_접지_그림자() -> void:
	var arrays: Array = _meshes(K.BLOCK)["mirror"].surface_get_arrays(0)
	var center := 0.0
	var reach := 0.0
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		if p.y == 0.0 and arrays[Mesh.ARRAY_COLOR][i].g == 1.0:
			center = maxf(center, arrays[Mesh.ARRAY_COLOR][i].a)
			reach = maxf(reach, absf(p.x))
	assert_true(center > 0.3, "진하기 %f" % center)
	assert_true(reach > ObstacleField.BLOCK_SIZE * 0.5 and reach < RunLogic.LANE_WIDTH * 0.75, "기둥보다 조금 넓음 %f" % reach)


func test_연속_기둥의_뒤쪽만_흐림() -> void:
	var main := _make_main()
	await wait_frames()
	main.clear_pieces()
	main._spawn_node({"id": 8001, "lane": 0, "z": -10.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8002, "lane": 0, "z": -18.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8003, "lane": 2, "z": -18.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8004, "lane": 0, "z": -26.0, "kind": K.LOW})
	assert_eq(main._obstacles[8001].haze, 0.0, "앞 기둥")
	assert_true(main._obstacles[8002].haze > 0.0, "같은 레인 뒤 기둥")
	assert_eq(main._obstacles[8003].haze, 0.0, "다른 레인")
	assert_eq(main._obstacles[8004].haze, 0.0, "기둥이 아님")
	main.queue_free()


## 장애물이 늘어도 그리는 횟수가 늘지 않고, 보통 프레임에는 값을 쓰지 않는다
func test_장애물은_종류별_MultiMesh_하나이고_바뀔_때만_다시_씀() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.prewarmed:  # 미리 준비용 장애물이 사라질 때까지
		await wait_frames()
	main.clear_pieces()
	for i in 5:
		main._spawn_node({"id": 8100 + i, "lane": i % 3, "z": -10.0 - i * 5.0, "kind": K.BLOCK})
	main._sync_pieces()
	assert_eq(main._kind_meshes[K.BLOCK]["body"].visible_instance_count, 5)
	assert_eq(main._kind_meshes[K.BLOCK]["mirror"].visible_instance_count, 5)
	assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 0)
	assert_eq(main._pieces_root.get_child_count(), 3 * main.KINDS.size(), "종류마다 깊이·색·반사")
	assert_false(main._pieces_dirty, "다 썼음")
	main._scroll += 3.0
	main._sync_pieces()
	assert_eq(main._pieces_root.position.z, main._scroll, "세상이 움직이면 부모만 움직임")
	assert_false(main._pieces_dirty)
	main.queue_free()


func test_물방울은_새로_들어온_줄만_다시_씀() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var ladder: MusicLadder = AudioManager.ladder
	main.advance(0.0, ladder.time_of_beat(4.1))
	var before: Array[float] = main._row_beats.duplicate()
	main.advance(0.0, ladder.time_of_beat(4.2))
	assert_eq(main._row_beats, before, "같은 박 안에서는 값이 그대로")
	main.advance(0.0, ladder.time_of_beat(5.1))
	var changed := 0
	for i in BeatRows.COUNT:
		changed += 1 if main._row_beats[i] != before[i] else 0
	assert_eq(changed, 2, "한 박에 두 칸(박 줄, 반 박 줄)")
	main.queue_free()


func test_프레임이_밀리면_효과를_낮춤() -> void:
	var main := _make_main()
	await wait_frames()
	var msaa: int = get_viewport().msaa_3d
	var glow: float = main._env.glow_intensity
	main.apply_quality(1)
	assert_eq(main._kind_meshes[K.BLOCK]["reflect"].get_shader_parameter("reflect_on"), 0.0, "1단계 반사 끔")
	assert_false(main.runner._mirror.visible, "주인공 반사도")
	assert_eq(get_viewport().msaa_3d, msaa, "MSAA는 그대로")
	main.apply_quality(2)
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_2X, "2단계 MSAA 2x")
	assert_eq(main._env.glow_intensity, glow, "빛 번짐은 그대로")
	main.apply_quality(3)
	assert_true(main._env.glow_intensity < glow, "3단계 빛 번짐 낮춤")
	get_viewport().msaa_3d = msaa
	main.queue_free()


## 깊이를 먼저 쓰고 색을 칠하므로 화소마다 맨 앞면 한 장만 보인다: 화면 불투명도 = 몸통 불투명도
func test_몸통_불투명도는_70퍼센트이고_깊이를_먼저_씀() -> void:
	var main := _make_main()
	await wait_frames()
	var code: String = load("res://shaders/glass.gdshader").code
	assert_true(absf(code.get_slice("body_alpha = ", 1).get_slice(";", 0).to_float() - 0.7) < 0.0001)
	assert_true(code.contains("depth_draw_always"))
	for kind in main.KINDS:
		var shape: Dictionary = main._kind_meshes[kind]
		assert_eq(shape["depth"].get_shader_parameter("pass_alpha"), 0.0, "깊이만")
		assert_true(shape["depth"].render_priority < shape["glass"].render_priority, "깊이 먼저")
		assert_true(shape["depth"].render_priority > 0, "주인공 다음: 뒤 장애물이 주인공을 덮지 않음")
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
	var pillar: AABB = _box(K.BLOCK, false)
	var low: AABB = _box(K.LOW, false)
	var high: AABB = _box(K.HIGH, false)
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
		main._music_t = ladder.time_of_beat(beat)  # 큰 시간 건너뛰기로 장애물에 부딪히지 않게 줄만 옮긴다
		main._place_rows()
		# 헤드리스 렌더러는 MultiMesh 값을 돌려주지 않으므로 칸에 담긴 박과 부모 위치로 확인한다. 실제 값은 tools/playthrough.gd가 웹에서 잰다
		assert_eq(main._row_beats[BeatRows.slot_of(beat)], beat, "그 박이 들어 있는 칸")
		assert_true(absf(main._droplets.position.z - ladder.distance_of_beat(beat)) < 0.0001, "부모가 그 박의 이동 거리에 있어 z = 0")
	main.queue_free()


func test_박마다_1_15배까지_부풀고_0_15초에_돌아옴() -> void:
	assert_eq(BeatRows.pulse(0.0), 1.0)
	assert_eq(BeatRows.pulse(BeatRows.PULSE_TIME), 1.0)
	assert_eq(BeatRows.pulse(0.3), 1.0)
	var peak := 0.0
	for i in 150:
		peak = maxf(peak, BeatRows.pulse(i * 0.001))
	assert_true(absf(peak - 1.15) < 0.001, "최대 %f" % peak)


func test_물방울은_박에_부풀고_멈추면_부풂과_반짝임이_꺼짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	main.advance(1.8 + 0.03)  # 3박(1.8초) 0.03초 뒤
	var mat: ShaderMaterial = main._droplet_material
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
		var node = main._obstacles[item["id"]]
		assert_true(node.scale.y < 0.01, "높이 0에서 시작")
		assert_eq(node.position.y, 0.0, "원점이 바닥")
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
	var crossing: Array = main.field.items.filter(func(item): return item["beat"] > 16.0)
	assert_true(crossing.size() > 0, "경계를 넘는 장애물이 있음")
	for item: Dictionary in crossing:
		assert_true(absf(item["arrive"] - ladder.distance_of_beat(item["beat"])) < 0.000001, "새 속도로 계산한 도착 거리")
		assert_true(item["arrive"] > 16 * 7.2 + (item["beat"] - 16.0) * 7.2, "경계 뒤 한 박은 7.2보다 멂")
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
	assert_true(glass.get_shader_parameter("tint").is_equal_approx(Color("bfdcff")))
	assert_true(main._env.fog_light_color.is_equal_approx(Color("3a2470")), "안개 = 지평선")
	ladder.add_segment(9.6, 16, 12)
	main.advance(0.0, 9.6 + 60.0 / 160.0 * 4.0)  # 2마디의 절반
	assert_true(absf(main._tint - 0.5) < 0.001, "절반 %f" % main._tint)
	main._music_t = 30.0  # 큰 시간 건너뛰기로 장애물에 부딪히지 않게 색만 계산한다
	main._apply_tint(main._tint_now())
	assert_eq(main._tint, 1.0)
	assert_true(_sky_top(main).is_equal_approx(Color("0a0030")), "t=1 하늘")
	assert_true(glass.get_shader_parameter("tint").is_equal_approx(Color("4fa0ff")))
	assert_eq(main._kind_meshes[K.BLOCK]["glass"], glass, "같은 재질")
	assert_true(main._kind_meshes[K.HIGH]["reflect"].get_shader_parameter("glass_color").is_equal_approx(Color("ff0fa0")), "반사도 같은 색")
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
	var ladder := MusicLadder.new(12)
	AudioManager.ladder = ladder
	AudioManager.start_step = 12
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
	assert_eq(main.speed, 12.0, "속도 12")
	assert_true(_sky_top(main).is_equal_approx(Color("0b0a24")))
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()
