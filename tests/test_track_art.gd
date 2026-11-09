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
	return ArtMeshes.obstacle(kind, Color.WHITE, Color.WHITE)


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
	assert_eq(MusicLadder.BEAT_DISTANCE, 5.4)
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


func test_막대의_기둥과_바닥_띠는_레인_안쪽() -> void:
	var half := RunLogic.LANE_WIDTH * 0.5
	var meshes := _meshes(K.HIGH)
	assert_true(meshes["edges"].get_aabb().position.x > -half, "선")
	assert_true(meshes["mirror"].get_aabb().position.x > -half, "반사·빛 띠")
	var lines: AABB = meshes["edges"].get_aabb()
	assert_true(lines.position.y < 0.02, "기둥이 바닥까지 내려옴")


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
	ladder.segments.append({"start": 38.4, "beat": 64, "step": 1})
	ladder.segments.append({"start": 74.97, "beat": 128, "step": 6})
	for beat in [0, 1, 63, 64, 65, 127, 128, 129, 500]:
		var t := ladder.time_of_beat(beat)
		var travel := ladder.distance_at(t)
		# 격자 어딘가의 박 줄이 z = 0 이어야 한다 (offset은 한 박 거리로 되풀이)
		var offset := BeatRows.offset(travel)
		var nearest: float = minf(offset, MusicLadder.BEAT_DISTANCE - offset)
		assert_true(nearest * 1000.0 / ladder.speed_at(t) < 1.0, "박 %d에서 어긋남 %f" % [beat, nearest])


func test_박_줄과_반_박_줄이_번갈아_놓이고_주인공_앞뒤를_덮음() -> void:
	assert_true(BeatRows.is_beat_row(0))
	assert_false(BeatRows.is_beat_row(1))
	assert_true(BeatRows.is_beat_row(-2))
	assert_eq(BeatRows.row_z(2), -MusicLadder.BEAT_DISTANCE)
	assert_true(BeatRows.row_z(BeatRows.FIRST) > 0.0, "주인공 뒤")
	assert_true(BeatRows.row_z(BeatRows.LAST) < ObstacleField.SPAWN_Z + 10.0, "장애물이 나오는 안개 근처까지")


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
	assert_true(is_equal_approx(main._droplets.position.z, fposmod(main.travel, 5.4)))
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
		while t < 180.0 and not main.dead:
			t += STEP
			ladder.plan(t, 1.0, 0.1, true)
			main.advance(STEP, t)
			if main.runner._move_tween and main.runner._move_tween.is_valid():
				main.runner._move_tween.custom_step(STEP)
			var dir := AutoPlayer.decide(main.field.items, main.lane, main.player, main.speed)
			if dir != SwipeDetector.Dir.NONE:
				main.apply_swipe(dir)
		assert_false(main.dead, "시드 %d: %.1f초에 충돌" % [seed_value, t])
		assert_true(ladder.segments.size() >= 5, "시드 %d: 사다리를 오름" % seed_value)
		main.queue_free()
		await wait_frames()
	AudioManager.ladder = MusicLadder.new(0)
