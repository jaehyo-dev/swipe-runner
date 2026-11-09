extends TestCase
## 무대·장애물 아트의 규칙: 보이는 모양 = 판정 범위, 판정 값 그대로, 대시 줄은 박에 닿음, 반사는 몸을 따라감, 지나간 장애물은 부서짐.
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


## 몸통 메시에서 부위(ArtMeshes.Part) 꼭짓점의 영역. 관은 둥근 끝까지 포함한다
func _box(kind: K, part: int) -> AABB:
	var arrays: Array = _meshes(kind)["body"].surface_get_arrays(0)
	var box := AABB()
	var first := true
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		if int(arrays[Mesh.ARRAY_TEX_UV][i].y) != part:
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
		var box: AABB = _box(kind, ArtMeshes.Part.BODY)
		assert_true(box.size.is_equal_approx(cases[kind][0]), "크기 %s: %s" % [kind, box.size])
		assert_true(is_equal_approx(box.position.y, cases[kind][1]), "아랫면 %s: %f" % [kind, box.position.y])
		assert_true(absf(box.position.x + box.size.x * 0.5) < 0.001 and absf(box.position.z + box.size.z * 0.5) < 0.001, "레인 가운데 %s" % kind)


func test_옆_블록은_점프보다_확실히_높음() -> void:
	assert_true(ObstacleField.BLOCK_HEIGHT - PlayerAction.JUMP_HEIGHT >= 0.4)


func test_슬라이드_블록에는_받침이_없고_아래_빛_웅덩이는_블록보다_좁고_가장자리가_사라짐() -> void:
	var half := RunLogic.LANE_WIDTH * 0.5
	var meshes := _meshes(K.HIGH)
	var lines: AABB = _box(K.HIGH, ArtMeshes.Part.EDGE)
	assert_true(lines.position.y >= ObstacleField.HIGH_BOTTOM - 0.1, "선이 블록 아래로 내려가지 않음 %f" % lines.position.y)
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


## 기호 하나가 면의 50~60% (둥근 끝까지 포함한 폭과 높이), 앞면에 있고 면 안에 든다
func test_기호는_앞면의_50에서_60퍼센트() -> void:
	for kind: K in [K.BLOCK, K.LOW, K.HIGH]:
		var face: AABB = _box(kind, ArtMeshes.Part.BODY)
		var mark: AABB = _box(kind, ArtMeshes.Part.MARK)
		for axis in 2:
			var share: float = mark.size[axis] / face.size[axis]
			assert_true(share >= 0.5 and share <= 0.6, "종류 %d 축 %d: %f" % [kind, axis, share])
		assert_true(absf(mark.get_center().y - face.get_center().y) < 0.001, "종류 %d: 가운데" % kind)
		assert_true(mark.end.z > face.end.z, "종류 %d: 앞면에서 솟음" % kind)
		assert_true(mark.position.z > 0.0, "종류 %d: 앞면에만" % kind)


## 뒤집힌 ^는 슬라이드 기호 v로 읽힌다
func test_반사에는_기호가_없음() -> void:
	for kind: K in [K.BLOCK, K.LOW, K.HIGH]:
		var mark := _box(kind, ArtMeshes.Part.MARK)
		assert_true(mark.size.x > 0.0, "몸통에는 기호가 있음")
		var arrays: Array = _meshes(kind)["mirror"].surface_get_arrays(0)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			if arrays[Mesh.ARRAY_COLOR][i].r > 0.5 and arrays[Mesh.ARRAY_COLOR][i].b < 0.5:
				assert_true(absf(p.x) > mark.end.x or absf(p.y + mark.get_center().y) > mark.size.y * 0.5, "종류 %d: 기호 자리에 빛 없음 %s" % [kind, p])


## 불투명 재질은 뒷면을 잘라 낸다. 감기 방향이 뒤집히면 몸통이 투명해 보이고 기호가 사라진다 (v0.6.0에서 실제로 겪음)
func test_몸통과_관은_바깥이_앞면() -> void:
	for kind: K in [K.BLOCK, K.LOW, K.HIGH]:
		var arrays: Array = _meshes(kind)["body"].surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var wrong := 0
		for i in range(0, v.size(), 3):
			var cross := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
			if cross.length() > 0.000001 and cross.dot(n[i] + n[i + 1] + n[i + 2]) > 0.0:  # Godot는 시계 방향이 앞면
				wrong += 1
		assert_eq(wrong, 0, "종류 %d: 뒤집힌 삼각형" % kind)


func test_몸통은_불투명이고_안개를_직접_섞음() -> void:
	var code: String = load("res://shaders/block.gdshader").code
	assert_false(code.contains("ALPHA"), "불투명")
	assert_true(code.contains("fog_disabled"))
	assert_false(ResourceLoader.exists("res://shaders/glass.gdshader"), "유리 재질 제거")


## 가산 혼합에 안개가 있으면 안개 색이 그대로 더해져 사각형째 떠 보인다
func test_가산_셰이더는_안개를_끔() -> void:
	for path in ["res://shaders/laser.gdshader", "res://shaders/shard.gdshader"]:
		var code: String = load(path).code
		assert_true(code.contains("blend_add") and code.contains("fog_disabled"), path)


func test_연속_블록의_뒤쪽만_흐림() -> void:
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
	assert_eq(main._pieces_root.get_child_count(), 2 * main.KINDS.size(), "종류마다 몸통·반사")
	assert_false(main._pieces_dirty, "다 썼음")
	main._scroll += 3.0
	main._sync_pieces()
	assert_eq(main._pieces_root.position.z, main._scroll, "세상이 움직이면 부모만 움직임")
	assert_false(main._pieces_dirty)
	main.queue_free()


func test_대시는_새로_들어온_줄만_다시_씀() -> void:
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
	assert_eq(changed, 1, "한 박에 한 칸")
	main.queue_free()


func test_프레임이_밀리면_줄기_레이저_반사_MSAA_빛_번짐_순서로_낮춤() -> void:
	var main := _make_main()
	await wait_frames()
	var msaa: int = get_viewport().msaa_3d
	var glow: float = main._env.glow_intensity
	main._tint = -1.0
	main._apply_tint(1.0)
	var streaks: int = main._streaks.visible_instance_count
	assert_eq(streaks, 48, "t=1 빛 줄기")
	assert_eq(main._laser_material.get_shader_parameter("count"), 6.0, "t=1 레이저")
	main.apply_quality(1)
	assert_true(main._streaks.visible_instance_count < streaks, "1단계 줄기")
	assert_eq(main._laser_material.get_shader_parameter("count"), 6.0, "레이저는 그대로")
	main.apply_quality(2)
	assert_eq(main._laser_material.get_shader_parameter("count"), QualityGuard.LASER_LOW, "2단계 레이저")
	assert_true(main.runner._mirror.visible, "반사는 그대로")
	main.apply_quality(3)
	assert_eq(main._kind_meshes[K.BLOCK]["reflect"].get_shader_parameter("reflect_on"), 0.0, "3단계 반사 끔")
	assert_false(main.runner._mirror.visible, "주인공 반사도")
	assert_eq(get_viewport().msaa_3d, msaa, "MSAA는 그대로")
	main.apply_quality(4)
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_2X, "4단계 MSAA 2x")
	assert_eq(main._env.glow_intensity, glow, "빛 번짐은 그대로")
	main.apply_quality(5)
	assert_true(main._env.glow_intensity < glow, "5단계 빛 번짐 낮춤")
	get_viewport().msaa_3d = msaa
	main.queue_free()


func test_반사는_바닥_아래이고_몸통과_빛의_불투명도가_정해진_값() -> void:
	for kind in [K.BLOCK, K.LOW, K.HIGH]:
		var arrays: Array = _meshes(kind)["mirror"].surface_get_arrays(0)
		var alphas := {}
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var a: float = arrays[Mesh.ARRAY_COLOR][i].a
			if a > 0.0 and arrays[Mesh.ARRAY_VERTEX][i].y < 0.0:
				alphas[snappedf(a, 0.01)] = true
		assert_eq(alphas.size(), 2, str(alphas))
		assert_true(alphas.has(snappedf(ArtMeshes.MIRROR_BODY_ALPHA, 0.01)) and alphas.has(snappedf(ArtMeshes.MIRROR_EDGE_ALPHA, 0.01)), str(alphas))


func test_세_종류의_실루엣_높이가_다름() -> void:
	var pillar: AABB = _box(K.BLOCK, ArtMeshes.Part.BODY)
	var low: AABB = _box(K.LOW, ArtMeshes.Part.BODY)
	var high: AABB = _box(K.HIGH, ArtMeshes.Part.BODY)
	assert_true(pillar.end.y > high.end.y + 0.5, "옆 블록이 가장 키가 큼")
	assert_true(low.end.y < high.position.y, "낮은 블록 윗면이 떠 있는 블록 아랫면보다 아래: 아래가 비어 보임")


func test_대시_줄은_템포가_바뀌어도_박에_주인공_자리에_닿음() -> void:
	var ladder := MusicLadder.new(0)
	ladder.add_segment(19.2, 32, 1)
	ladder.add_segment(37.49, 64, 6)
	for beat in [0, 1, 31, 32, 33, 63, 64, 65, 500]:
		var t := ladder.time_of_beat(beat)
		assert_true(absf(BeatRows.row_z(ladder, t, beat)) < 0.000001, "박 %d" % beat)


func test_줄은_박_거리마다_하나이고_주인공_앞뒤를_덮으며_간격이_구간_속도를_따름() -> void:
	assert_eq(BeatRows.beat_of(0, 10.3), 9.0)
	assert_eq(BeatRows.beat_of(1, 10.3), 10.0)
	assert_eq(BeatRows.beat_of(4, 10.9), 13.0)
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
		assert_true(absf(main._dashes.position.z - ladder.distance_of_beat(beat)) < 0.0001, "부모가 그 박의 이동 거리에 있어 z = 0")
	main.queue_free()


func test_박에_바로_밝아지고_0_15초에_돌아옴() -> void:
	assert_eq(BeatRows.pulse(0.0), 0.0)
	assert_eq(BeatRows.pulse(BeatRows.PULSE_TIME), 0.0)
	assert_eq(BeatRows.pulse(0.3), 0.0)
	var peak := 0.0
	for i in 150:
		peak = maxf(peak, BeatRows.pulse(i * 0.001))
	assert_true(absf(peak - 1.0) < 0.001, "최대 %f" % peak)


func test_대시는_박에_밝아지고_멈추면_꺼짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	main.advance(1.8 + 0.03)  # 3박(1.8초) 0.03초 뒤
	var mat: ShaderMaterial = main._dash_material
	assert_true(mat.get_shader_parameter("pulse") > 0.5, "박 직후 밝음")
	main.advance(0.2)
	assert_eq(mat.get_shader_parameter("pulse"), 0.0, "0.15초 뒤 돌아옴")
	var item := {"id": 7000, "lane": main.lane, "z": 0.0, "kind": K.BLOCK, "beat": 0, "arrive": main.travel}
	main.field.items.append(item)
	main._spawn_node(item)
	main.advance(STEP)
	assert_true(main.dead, "부딪힘")
	assert_eq(mat.get_shader_parameter("pulse"), 0.0)
	assert_eq(mat.get_shader_parameter("sparkle_on"), 0.0, "멈춘 줄이 계속 빛나지 않음")
	var z: float = main._dashes.position.z
	main.advance(STEP)
	assert_true(main._dashes.position.z > z, "느려지는 동안 장애물과 같이 다가옴")
	main.restart()
	assert_eq(main._dashes.position.z, 0.0, "밀린 만큼 되돌림")
	assert_eq(mat.get_shader_parameter("appear"), 0.0, "재시작 때 '퐁'으로 다시 나타남")
	assert_eq(mat.get_shader_parameter("sparkle_on"), 1.0)
	main.queue_free()


func test_대기_화면에서는_줄이_반짝이지_않고_출발하면_반짝임() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	var on: Variant = main._dash_material.get_shader_parameter("sparkle_on")
	assert_true(on == null or on == 0.0, "대기 중 꺼짐")
	main.begin()
	assert_eq(main._dash_material.get_shader_parameter("sparkle_on"), 1.0)
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
	var block: ShaderMaterial = main._kind_meshes[K.BLOCK]["block"]
	main.advance(0.0, 1.0)
	assert_eq(main._tint, 0.0)
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")), "t=0 하늘")
	assert_true(block.get_shader_parameter("tint").is_equal_approx(Color("2fb8ff")))
	assert_true(main._env.fog_light_color.is_equal_approx(Color("241650")), "안개 = 지평선")
	assert_eq(main._laser_material.get_shader_parameter("count"), 4.0, "t=0 레이저 4줄")
	ladder.add_segment(9.6, 16, 12)
	main.advance(0.0, 9.6 + 60.0 / 160.0 * 4.0)  # 2마디의 절반
	assert_true(absf(main._tint - 0.5) < 0.001, "절반 %f" % main._tint)
	main._music_t = 30.0  # 큰 시간 건너뛰기로 장애물에 부딪히지 않게 색만 계산한다
	main._apply_tint(main._tint_now())
	assert_eq(main._tint, 1.0)
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")), "t=1 하늘")
	assert_true(main._env.fog_light_color.is_equal_approx(Color("3d1880")), "t=1 안개 짙게")
	assert_true(block.get_shader_parameter("tint").is_equal_approx(Color("0faeff")))
	assert_eq(main._kind_meshes[K.BLOCK]["block"], block, "같은 재질")
	assert_eq(main._laser_material.get_shader_parameter("count"), 6.0, "t=1 레이저 6줄")
	assert_eq(main._streaks.visible_instance_count, 48, "t=1 빛 줄기")
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


func test_번쩍여도_레이저와_대시는_상한을_넘지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	for t in [0.0, 0.5, 1.0]:
		main._tint = -1.0
		main._apply_tint(t)
		main._beat_flash = StageLight.BAR_BOOST
		main._set_flash(1.0)
		assert_true(main._laser_peak * main._laser_material.get_shader_parameter("energy") <= main.ROAD_PEAK_MAX + 0.001, "레이저 t=%f" % t)
		var rail: Color = main._rail_material.get_shader_parameter("color")
		assert_true(maxf(rail.r, maxf(rail.g, rail.b)) * main._dash_material.get_shader_parameter("max_energy") <= main.ROAD_PEAK_MAX + 0.001, "대시 t=%f" % t)
		main._beat_flash = 0.0
		main._set_flash(0.0)
		assert_true(is_equal_approx(main._laser_material.get_shader_parameter("energy"), SpeedPalette.at(t)["laser_energy"]), "평소 빛 세기")
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
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")))
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


## 옆 레인에 곧 주인공 위치를 지날 장애물을 놓는다
func _passing(main: Node3D, id: int, kind: K, lane: int, ahead := 0.01) -> Dictionary:
	var item := {"id": id, "lane": lane, "z": -ahead, "kind": kind, "beat": 0, "arrive": main.travel + ahead}
	main.field.items.append(item)
	main._spawn_node(item)
	return item


func _shatter_sounds(main: Node3D, frames: int) -> int:
	var heard := [0]
	var count := func(sound: StringName, _pitch: float) -> void:
		if sound == &"shatter":
			heard[0] += 1
	AudioManager.played.connect(count)
	for i in frames:
		main.advance(STEP)
	AudioManager.played.disconnect(count)
	return heard[0]


func test_지나간_장애물은_박에_조각으로_부서지고_판정이_끝나면_몸통이_사라짐() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.prewarmed:  # 미리 준비용 조각이 사라질 때까지
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var item := _passing(main, 7100, K.LOW, 2)
	var free_before: int = main._shard_free.size()
	assert_eq(_shatter_sounds(main, 1), 1, "한 번")
	assert_true(item.has("broken"))
	var made: int = free_before - main._shard_free.size()
	assert_true(made >= Shatter.COUNT_MIN and made <= Shatter.COUNT_MAX, "조각 %d개" % made)
	assert_true(item["z"] <= PlayerAction.HIT_Z, "아직 판정 범위")
	assert_false(main._obstacles[7100].broken, "판정이 남아 있는 동안 몸통은 보임")
	main._sync_pieces()
	assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 1, "그림")
	assert_eq(_shatter_sounds(main, 3), 0, "한 장애물은 한 번만")
	while item["z"] <= PlayerAction.HIT_Z:
		main.advance(STEP)
	main._sync_pieces()
	assert_true(main._obstacles[7100].broken, "판정이 끝나면 숨김")
	assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 0, "그리지 않음")
	for i in 30:
		main.advance(STEP)
	assert_eq(main._shard_live.size(), 0, "0.35초 안에 사라짐")
	assert_eq(main._shard_free.size(), free_before, "풀로 돌아옴")
	main.queue_free()


func test_같은_박에_여러_개면_모두_부서지고_소리는_하나() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.prewarmed:  # 미리 준비용 조각이 사라질 때까지
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var a := _passing(main, 7200, K.BLOCK, 0)
	var b := _passing(main, 7201, K.HIGH, 2)
	var free_before: int = main._shard_free.size()
	assert_eq(_shatter_sounds(main, 1), 1, "소리 하나")
	assert_true(a.has("broken") and b.has("broken"), "둘 다")
	assert_true(free_before - main._shard_free.size() >= Shatter.COUNT_MIN * 2, "조각도 둘 다")
	main.queue_free()


func test_충돌한_장애물은_부서지지_않음() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.prewarmed:  # 미리 준비용 조각이 사라질 때까지
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var item := _passing(main, 7300, K.BLOCK, main.lane)
	var free_before: int = main._shard_free.size()
	main.advance(STEP)
	assert_true(main.dead, "부딪힘")
	assert_false(item.has("broken"))
	assert_eq(main._shard_free.size(), free_before, "조각 없음")
	main.queue_free()


## 판정은 z 0.7까지 그대로다. 부서진 직후 그 범위로 파고들면 원래대로 부딪히고, 몸통은 계속 보이며 그 조각만 사라진다
func test_부서진_직후_판정_범위에서_부딪히면_몸통은_보이고_조각이_사라짐() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.prewarmed:  # 미리 준비용 조각이 사라질 때까지
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var side: int = (main.lane + 1) % 3
	var item := _passing(main, 7400, K.BLOCK, side)
	main.advance(STEP)
	assert_true(item.has("broken") and not main.dead, "옆 레인이라 부서짐")
	assert_true(item["z"] < PlayerAction.HIT_Z)
	var free_before: int = main._shard_free.size()
	main.runner.position.x = RunLogic.lane_x(side)
	main.advance(STEP)
	assert_true(main.dead, "v0.5.1과 같이 부딪힘")
	assert_false(main._obstacles[7400].broken, "몸통이 보임")
	assert_true(main._shard_free.size() > free_before, "그 조각을 지움")
	assert_eq(main._shard_live.size(), 0)
	main.queue_free()


func test_조각은_새_노드를_만들지_않고_풀이_차도_안전함() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.prewarmed:  # 미리 준비용 조각이 사라질 때까지
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var nodes: int = main.get_child_count()
	for i in 40:  # 풀보다 많이
		_passing(main, 7500 + i, K.LOW, 2)
	main.advance(STEP)
	assert_eq(main._shard_free.size(), 0, "풀을 다 씀")
	assert_eq(main._shard_live.size(), main.SHARD_POOL)
	assert_eq(main.get_child_count(), nodes, "노드 그대로")
	main.queue_free()
