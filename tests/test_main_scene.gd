extends TestCase
## 게임 화면(main.tscn) 조립 테스트. 화면 모양은 PC·휴대폰에서 직접 확인한다.

const Dir := SwipeDetector.Dir


func _make_main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	main.set_process(false)  # 시간은 advance()로만 흘려 결과를 고정한다
	main.started = true  # 음악 시작(begin)은 따로 테스트한다
	return main


func test_시작하면_가운데_레인에서_거리는_0() -> void:
	var main := _make_main()
	await wait_frames()
	assert_eq(main.lane, 1)
	main.queue_free()


func test_스와이프로_레인이_바뀌고_양쪽_끝에서_멈춤() -> void:
	var main := _make_main()
	await wait_frames()
	main.apply_swipe(Dir.LEFT)
	main.apply_swipe(Dir.LEFT)
	main.apply_swipe(Dir.LEFT)
	assert_eq(main.lane, 0)
	main.apply_swipe(Dir.RIGHT)
	main.apply_swipe(Dir.RIGHT)
	main.apply_swipe(Dir.RIGHT)
	main.apply_swipe(Dir.RIGHT)
	assert_eq(main.lane, 2)
	main.queue_free()


## 실제 터치 이벤트로 from → to 를 steps번에 나눠 끌고 뗀다.
func _touch_swipe(main: Node3D, from: Vector2, to: Vector2, steps: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = from
	touch.pressed = true
	main._input(touch)
	for i in steps:
		var drag := InputEventScreenDrag.new()
		drag.position = from.lerp(to, float(i + 1) / steps)
		main._input(drag)
	touch.position = to
	touch.pressed = false
	main._input(touch)


func test_터치로_길게_밀어도_한_칸만_가고_떼고_다시_밀면_다음_칸() -> void:
	var main := _make_main()
	await wait_frames()
	_touch_swipe(main, Vector2(40, 900), Vector2(700, 900), 40)
	assert_eq(main.lane, 2, "화면 끝까지 밀어도 한 칸")
	_touch_swipe(main, Vector2(700, 900), Vector2(40, 900), 40)
	assert_eq(main.lane, 1, "떼고 다시 밀면 다음 칸")
	_touch_swipe(main, Vector2(360, 1200), Vector2(360, 100), 40)
	assert_true(main.player.is_jumping(), "위로 길게 밀면 점프")
	main.advance(PlayerAction.JUMP_TIME + 0.05)
	assert_false(main.player.is_jumping(), "점프는 한 번만 (미리 넣은 입력으로 또 뛰지 않음)")
	main.queue_free()


func test_위_스와이프는_점프_아래는_슬라이드() -> void:
	var main := _make_main()
	await wait_frames()
	main.apply_swipe(Dir.UP)
	assert_true(main.player.is_jumping())
	assert_eq(main.lane, 1, "레인은 그대로")
	main.advance(PlayerAction.JUMP_TIME + 0.05)
	main.apply_swipe(Dir.DOWN)
	assert_true(main.player.is_sliding())
	main.queue_free()


func test_장애물에_부딪히면_멈추고_안내가_뜸() -> void:
	var main := _make_main()
	await wait_frames()
	var item := _add_obstacle(main)
	main.runner.position.x = RunLogic.lane_x(item["lane"])
	item["z"] = 0.0
	main.advance(0.0)
	assert_true(main.dead, "아무 동작 없이 부딪히면 어떤 종류든 게임 오버")
	var label: Label = main.find_child("RestartLabel", true, false)
	assert_false(label.visible, "충돌 모션을 가리지 않게 바로는 안 뜸")
	main.advance(main.RESTART_DELAY)
	assert_true(label.visible, "0.5초 뒤 안내")
	var t: float = main.elapsed
	main.advance(1.0)
	assert_eq(main.elapsed, t, "게임 오버 뒤엔 시간이 멈춤")
	main.queue_free()


func test_피하면_계속_달림() -> void:
	var main := _make_main()
	await wait_frames()
	var item := _add_obstacle(main)
	main.runner.position.x = RunLogic.lane_x((item["lane"] + 1) % 3)  # 다른 레인
	item["z"] = 0.0
	main.advance(0.0)
	assert_false(main.dead)
	main.queue_free()


func test_시간이_가면_거리가_늘고_장애물_노드가_생기고_지나가면_사라짐() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.prewarmed:  # 미리 준비용 장애물이 사라질 때까지
		await wait_frames()
	await wait_frames()
	var cubes_now := main.get_children().filter(func(c): return c is MeshInstance3D and c.get_child_count() == 1)
	assert_eq(cubes_now.size(), main.field.items.size(), "미리 놓인 장애물이 처음부터 노드로 있음")
	assert_true(cubes_now.size() > 0)
	main.advance(12.0)
	await wait_frames()  # 지워진 노드(queue_free)가 정리될 때까지
	assert_eq(main.elapsed, 12.0)
	var label: Label = main.find_child("DistanceLabel", true, false)
	assert_eq(label.text, str(RunLogic.distance(12.0)))
	var cubes := main.get_children().filter(func(c): return c is MeshInstance3D and c.get_child_count() == 1)
	assert_eq(cubes.size(), main.field.items.size(), "노드 수 = 살아 있는 장애물 수")
	main.queue_free()


func test_장애물_종류별_색조가_정해진_색으로_나옴() -> void:
	var main := _make_main()
	await wait_frames()
	var K := ObstacleField.Kind
	# 기획 색(ART_BIBLE.md 4번): 블록 아이스 블루, 허들 앰버, 막대 로즈 핑크
	var expected := {K.BLOCK: Color("9edbff"), K.LOW: Color("ffc38a"), K.HIGH: Color("ff8fc8")}
	# 주인공 가장자리 최대 밝기 = 테두리 빛(jelly.gdshader 기본값 rim_color #C8FFFA × rim_energy 2.1)
	var hero_peak := Color("c8fffa") * 2.1
	# 길 선 = line_color × energy (floor.gdshader 기본값. 헤드리스에선 셰이더 기본값 조회가 안 돼 소스에서 읽음)
	var code: String = main._floor_material.shader.code
	var re := RegEx.create_from_string("line_color[^=]*= vec3\\(([\\d.]+), ([\\d.]+), ([\\d.]+)\\)[\\s\\S]*energy = ([\\d.]+)")
	var m := re.search(code)
	var road_peak := maxf(float(m.get_string(1)), maxf(float(m.get_string(2)), float(m.get_string(3)))) * float(m.get_string(4))
	for kind in expected:
		main._spawn_node({"id": 900 + kind, "lane": 1, "z": -10.0, "kind": kind})
		var cube: MeshInstance3D = main._obstacles[900 + kind]
		var edge: Color = cube.get_child(0).material_override.albedo_color
		assert_eq(cube.material_override.get_shader_parameter("tint"), expected[kind], "유리 면 색 (종류 %d)" % kind)
		# 선은 같은 색조: 가장 센 채널이 유리 색과 같고, HDR(1 초과)로 빛남
		var glass: Color = expected[kind]
		assert_eq(_strongest(edge), _strongest(glass), "선 색조가 유리와 같음 (종류 %d)" % kind)
		assert_true(_peak(edge) > 1.0, "선은 HDR 발광 (종류 %d)" % kind)
		# 밝기 순서(HDR 가장 센 채널 기준): 주인공 > 모서리 선 > 길 선
		assert_true(_peak(edge) < _peak(hero_peak), "선이 주인공 가장자리보다 어두움 (종류 %d)" % kind)
		assert_true(_peak(edge) > road_peak, "선이 길 선보다 밝음 (종류 %d)" % kind)
	main.queue_free()


## 가장 센 채널 값 (글로우 번짐 크기를 좌우)
func _peak(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## 가장 센 채널 이름 (색조 비교용)
func _strongest(c: Color) -> String:
	if c.r >= c.g and c.r >= c.b:
		return "r"
	return "g" if c.g >= c.b else "b"


func test_화면에_거리와_버전_안내_글자만_있음() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.prewarmed:
		await wait_frames()
	await wait_frames()
	var labels := main.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 3, "거리 + 버전 + (숨겨진) 다시 시작 안내")
	var version: Label = main.find_child("VersionLabel", true, false)
	assert_eq(version.text, "v" + str(ProjectSettings.get_setting("application/config/version")))
	main.queue_free()


func test_카메라는_주인공의_위아래_튀기를_따라가지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	var cam: Camera3D = main._camera
	assert_false(main.runner.is_ancestor_of(cam), "카메라는 주인공의 자식이 아님")
	main.runner.set_phase(0.0)
	var low := cam.global_position
	main.runner.set_phase(PI / 2.0)
	assert_true(cam.global_position.is_equal_approx(low), "주인공이 튀어도 카메라는 고정")
	main.queue_free()


# ---------- 충돌·다시 시작 ----------

const STEP := 1.0 / 60.0


## 프레임 단위로 게임과 주인공을 진행한다 (주인공의 _process는 실시간과 별개로 직접 돌림).
func _run(main: Node3D, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		main.advance(STEP)
		main.runner._process(STEP)


## 주인공 레인 바로 앞에 이 종류의 장애물을 놓는다
func _put_in_front(main: Node3D, kind: ObstacleField.Kind, z := -0.75) -> Dictionary:
	var item := _add_obstacle(main)
	item["lane"] = main.lane
	item["kind"] = kind
	item["z"] = z
	return item


## 장애물을 하나 바로 놓는다 (패턴의 첫 장애물은 몇 초 뒤에나 온다)
func _add_obstacle(main: Node3D) -> Dictionary:
	var item := {"id": 9000 + main._obstacles.size(), "lane": 1, "z": ObstacleField.SPAWN_Z, "kind": ObstacleField.Kind.BLOCK, "beat": 0}
	main.field.items.append(item)
	main._spawn_node(item)
	return item


func test_세_종류_모두_앞면에_붙었다_흘러내려_웅덩이가_되고_멈춤() -> void:
	var K := ObstacleField.Kind
	for kind in [K.BLOCK, K.LOW, K.HIGH]:
		var main := _make_main()
		await wait_frames()
		main.runner.set_process(false)
		var item := _put_in_front(main, kind)
		main.advance(STEP)
		assert_true(main.dead, "종류 %d 부딪힘" % kind)
		var hit_z: float = item["z"]
		var half: float = ObstacleField.BLOCK_SIZE * 0.5 if kind == K.BLOCK else ObstacleField.BAR_DEPTH * 0.5
		# 느려지는 동안 세상이 아주 조금만 움직이고 그 뒤엔 멈춘다
		_run(main, CrashMotion.SLOW_TIME)
		var moved: float = item["z"] - hit_z
		assert_true(absf(moved - RunLogic.SPEED * CrashMotion.SLOW_SCALE * CrashMotion.SLOW_TIME) < 0.02, "느린 이동 %f" % moved)
		# 찰싹 붙음: 납작하고, 몸 앞 끝이 장애물 앞면에 닿아 있다
		_run(main, CrashMotion.SNAP_TIME + 0.04)
		var body: MeshInstance3D = main.runner._body
		assert_true(body.scale.z < 0.5, "납작 %f" % body.scale.z)
		var face: float = item["z"] + half
		var body_front: float = main.runner.position.z - Runner.BODY_RADIUS * body.scale.z
		assert_true(absf(body_front - face) < 0.02, "면에 닿음: 몸 %f, 면 %f" % [body_front, face])
		assert_true(main.runner._drops[0].visible, "물방울이 튐")
		if kind == K.HIGH:
			assert_true(body.position.y > 0.1, "막대는 부딪힌 높이에 붙음 %f" % body.position.y)
		# 웅덩이: 바닥에 낮고 넓게
		_run(main, CrashMotion.FLOW_END)
		assert_eq(body.position.y, 0.0, "바닥에 있음")
		assert_true(body.scale.y <= Runner.PUDDLE_FLAT + 0.001, "낮음 %f" % body.scale.y)
		assert_true(body.scale.x >= 1.5, "넓음 %f" % body.scale.x)
		assert_false(main.runner._drops[0].visible, "물방울은 끝남")
		# 멈춤
		var pose: Vector3 = body.scale
		var pos: Vector3 = main.runner.position
		var z: float = item["z"]
		_run(main, 0.5)
		assert_eq(body.scale, pose, "모양 고정")
		assert_eq(main.runner.position, pos, "위치 고정")
		assert_eq(item["z"], z, "세상 고정")
		assert_eq(main._camera.h_offset, 0.0, "흔들림 끝")
		main.queue_free()


func test_0_5초_전에는_탭해도_다시_시작하지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	main.advance(0.3)
	main._input(tap)
	assert_true(main.dead, "아직")
	main.advance(0.25)
	main._input(tap)
	assert_false(main.dead, "0.5초 뒤 탭")
	main.queue_free()


func test_다시_시작은_장면을_유지하고_상태만_초기화() -> void:
	var main := _make_main()
	await wait_frames()
	var runner_node: Runner = main.runner
	_run(main, 2.0)
	main.apply_swipe(Dir.LEFT)
	main.runner.position.x = RunLogic.lane_x(0)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	_run(main, 1.0)
	var floor_scroll: float = main._scroll
	main.restart()
	assert_false(main.dead)
	assert_eq(main.runner, runner_node, "주인공 노드 그대로")
	assert_true(is_instance_valid(main) and main.is_inside_tree(), "장면 그대로")
	assert_eq(main.elapsed, 0.0)
	assert_eq(main.lane, 0, "레인 그대로")
	assert_eq(main.find_child("DistanceLabel", true, false).text, "0")
	assert_false(main.find_child("RestartLabel", true, false).visible)
	assert_true(main.field.items.size() > 0, "앞으로 올 장애물이 바로 길 위에 있음")
	assert_eq(main._obstacles.size(), main.field.items.size())
	assert_eq(main._scroll, floor_scroll, "길 무늬가 튀지 않음")
	# 입력을 바로 받고 세상도 바로 움직인다
	main.apply_swipe(Dir.UP)
	assert_true(main.player.is_jumping(), "바로 입력")
	main.advance(STEP)
	assert_true(main.elapsed > 0.0, "바로 달림")
	assert_true(main._scroll > floor_scroll)
	main.queue_free()


func test_다시_시작하면_약_0_3초에_걸쳐_모여_달리는_모양이_됨() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	_put_in_front(main, ObstacleField.Kind.LOW)
	main.advance(STEP)
	_run(main, 1.0)
	var body: MeshInstance3D = main.runner._body
	var last_y: float = body.scale.y
	assert_true(last_y < 0.2, "웅덩이 %f" % last_y)
	main.restart()
	main.runner._process(0.0)
	assert_true(absf(body.scale.y - last_y) < 0.01, "그 자리 모양에서 시작해 튀지 않음")
	for i in 18:  # 0.3초
		main.advance(STEP)
		main.runner._process(STEP)
		assert_true(absf(body.scale.y - last_y) < 0.2, "프레임마다 조금씩 %f → %f" % [last_y, body.scale.y])
		last_y = body.scale.y
	_run(main, 0.7)
	assert_true(body.scale.y > 0.8 and body.scale.y < 1.2, "달리는 키 %f" % body.scale.y)
	assert_true(body.scale.x > 0.9 and body.scale.x < 1.1, "달리는 폭 %f" % body.scale.x)
	assert_eq(main.runner.position.z, 0.0, "제자리로 돌아옴")
	assert_eq(main.runner._mat.get_shader_parameter("rim_wave"), 0.0)
	main.queue_free()


func test_부딪힘에서_다시_달리기까지_1_5초_이내() -> void:
	# 탭 가능 0.5초 + 모이기 0.3초. 남는 0.7초가 사람이 탭하는 시간이다
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	var took := 0.0
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	while main.dead and took < 2.0:  # 탭이 먹힐 때까지 프레임마다 탭한다
		main._input(tap)
		if main.dead:
			main.advance(STEP)
			main.runner._process(STEP)
			took += STEP
	assert_false(main.dead, "탭으로 다시 시작")
	while main.runner._reform_t >= 0.0 and took < 2.0:
		main.advance(STEP)
		main.runner._process(STEP)
		took += STEP
	assert_true(took <= 0.85, "가장 빠르게 탭했을 때 %.3f초" % took)
	main.queue_free()


func test_흘러내리는_중에_다시_시작해도_모양이_튀지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	_run(main, main.RESTART_DELAY)  # 탭할 수 있는 가장 이른 순간
	var runner: Runner = main.runner
	var wave: float = runner._mat.get_shader_parameter("rim_wave")
	var flat: float = runner._flat
	assert_true(flat < 0.9, "아직 바닥이 둥글게 남아 있음 %f" % flat)
	main.restart()
	main.advance(STEP)
	runner._process(STEP)
	assert_true(runner._mat.get_shader_parameter("rim_wave") <= wave + 0.001, "물결이 커지지 않음")
	assert_true(runner._flat < 1.0 and runner._flat - flat < 0.4, "평평함이 한 프레임에 다 바뀌지 않음 %f → %f" % [flat, runner._flat])
	_run(main, 0.4)
	assert_eq(runner._flat, 1.0, "달릴 때는 평평함")
	main.queue_free()


func test_레인_이동_중_옆면에_부딪히면_옆면에_붙음() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	var item := _put_in_front(main, ObstacleField.Kind.BLOCK, 0.2)
	item["lane"] = 0
	main.runner.position.x = RunLogic.lane_x(0) + 0.65  # 왼쪽 레인 블록 쪽으로 가는 중
	main.advance(STEP)
	assert_true(main.dead)
	_run(main, CrashMotion.SLOW_TIME + CrashMotion.SNAP_TIME + 0.04)
	var body: MeshInstance3D = main.runner._body
	assert_true(body.scale.x < 0.5, "x 쪽이 납작 %f" % body.scale.x)
	assert_true(body.scale.z > 1.0, "z 쪽이 넓음 %f" % body.scale.z)
	var face: float = RunLogic.lane_x(0) + ObstacleField.BLOCK_SIZE * 0.5
	var edge: float = main.runner.position.x - Runner.BODY_RADIUS * body.scale.x
	assert_true(absf(edge - face) < 0.02, "옆면에 닿음: 몸 %f, 면 %f" % [edge, face])
	main.queue_free()


func test_고정_시드면_음악의_같은_자리에서_다시_시작할_때_같은_배치() -> void:
	var main := _make_main()
	await wait_frames()
	var first := _arrivals(main)
	main._music_t = BeatClock.LOOP  # 한 바퀴 돈 같은 자리
	main.restart()
	var second := _arrivals(main)
	assert_eq(second, first)
	main.queue_free()


func _arrivals(main: Node3D) -> Array:
	var result := []
	for item in main.field.step(30.0)["spawned"]:
		result.append([posmod(item["beat"], 64), item["lane"], item["kind"]])
	return result


func test_시드를_정하지_않으면_판마다_다른_배치() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await wait_frames()
	main.set_process(false)
	var seed_a: int = main.field._pattern._rng.seed
	main.restart()
	assert_true(main.field._pattern._rng.seed != seed_a, "새 시드")
	main.queue_free()


func test_다시_시작하면_앞_판을_지우고_다음_마디_첫_박에_1마디_넘게_뒤_도착() -> void:
	var main := _make_main()
	await wait_frames()
	_run(main, 11.3)
	var old_ids: Array = main.field.items.map(func(i): return main._obstacles[i["id"]])
	main.dead = true
	main.restart()
	var t: float = main._music_t
	var first: Dictionary = main.field.items[0]
	assert_eq(first["beat"] % BeatClock.BEATS_PER_BAR, 0, "마디 첫 박")
	var wait: float = first["beat"] * BeatClock.BEAT - t
	assert_true(wait >= BeatClock.BAR and wait < BeatClock.BAR * 2.0, "2.4~4.8초 안 %f" % wait)
	for item in main.field.items:
		assert_true(absf(item["z"] + RunLogic.SPEED * (item["beat"] * BeatClock.BEAT - t)) < 0.001, "박에서 거꾸로 계산한 자리")
		assert_true(item["z"] >= ObstacleField.SPAWN_Z, "z -60보다 가까운 것만")
		assert_false(old_ids.has(main._obstacles[item["id"]]), "새 노드")
	main.queue_free()


func test_다시_시작한_장애물은_바닥에서_퐁_솟아_살짝_넘쳤다가_돌아옴() -> void:
	var main := _make_main()
	await wait_frames()
	_run(main, 3.0)
	main.dead = true
	main.restart()
	var item: Dictionary = main.field.items[0]
	var node: Node3D = main._obstacles[item["id"]]
	var y: float = main._kind_meshes[item["kind"]]["y"]
	assert_true(node.scale.y < 0.01 and node.position.y < 0.01, "높이 0에서 시작")
	var peak := 0.0
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < 400:
		await wait_frames()
		peak = maxf(peak, node.scale.y)
		assert_true(absf(node.position.y - y * node.scale.y) < 0.001, "바닥을 기준으로 늘어남")
	assert_true(peak > 1.02, "살짝 넘침 %f" % peak)
	assert_true(peak < 1.2, "많이 넘치지 않음 %f" % peak)
	assert_eq(node.scale.y, 1.0, "제 크기로 돌아옴")
	main.queue_free()


func test_첫_판_대기_화면의_장애물은_솟아오르지_않고_제_크기() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	assert_true(main.field.items.size() > 0)
	for item in main.field.items:
		assert_eq(main._obstacles[item["id"]].scale.y, 1.0)
	main.queue_free()


func test_재시작_뒤_0_82초_동안_어떤_장애물도_닿을_수_없음() -> void:
	# 판정을 끄는 규칙 대신, 어느 시각에 재시작해도 첫 도착이 2.4초 뒤라 닿을 수 없음을 확인한다
	var main := _make_main()
	await wait_frames()
	for start in 40:
		main._music_t = start * 0.37
		main.dead = true
		main.restart()
		for i in int(0.82 / STEP):
			main.advance(STEP)
			assert_false(main.dead, "재시작 %d: 0.82초 안에 부딪힘" % start)
	main.queue_free()


func test_첫_화면_전에_세_종류와_물방울과_글자를_가림막_뒤에서_그린다() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	assert_false(main.prewarmed, "아직 준비 중")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	main._input(key)
	assert_false(main.started, "가림막 뒤 입력으로는 시작하지 않음")
	assert_eq(main.lane, 1, "동작도 하지 않음")
	var drawn := {}
	for node in main.find_children("*", "MeshInstance3D", true, false):
		drawn[node.material_override] = true
	for kind in main._kind_meshes:
		assert_true(drawn.has(main._kind_meshes[kind]["glass"]), "유리 %d" % kind)
		assert_true(drawn.has(main._kind_meshes[kind]["edge"]), "모서리 %d" % kind)
	var cover: ColorRect = main.find_children("*", "ColorRect", true, false)[0]
	assert_true(cover.get_parent().layer > 1, "화면 맨 위 가림막")
	assert_eq(main.find_children("*", "Label", true, false).size(), 5, "숫자·안내 글자도 그림")
	var nodes_during: int = _count_nodes(main)
	while not main.prewarmed:
		await wait_frames()
	await wait_frames()
	assert_eq(main.find_children("*", "ColorRect", true, false).size(), 0, "가림막 사라짐")
	assert_true(_count_nodes(main) < nodes_during, "준비용 노드 정리")
	assert_eq(main.find_children("*", "Label", true, false).size(), 3)
	main.queue_free()


func test_다시_시작을_20번_해도_노드와_오브젝트가_쌓이지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	var baseline := -1
	var baseline_objects := -1
	for round_no in 20:
		_run(main, 1.2)  # 장애물 2개가 나올 만큼
		_put_in_front(main, ObstacleField.Kind.BLOCK)
		main.advance(STEP)
		assert_true(main.dead, "%d판째 부딪힘" % round_no)
		_run(main, 0.6)
		main.restart()
		assert_false(main.dead)
		await get_tree().create_timer(maxf(main.OBSTACLE_FADE, main.POP_TIME) + 0.05).timeout  # 앞 판이 사라지고 새 판이 다 솟을 시간
		await wait_frames(2)
		await wait_frames(2)
		var nodes: int = _count_nodes(main) - main.field.items.size() * 2  # 미리 놓인 장애물 수는 음악 자리마다 다르다 (큐브 + 모서리)
		var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - main.field.items.size() * 2
		if round_no == 0:
			baseline = nodes
			baseline_objects = objects
		assert_eq(nodes, baseline, "%d판째 노드 수" % round_no)
		assert_true(objects <= baseline_objects + 2, "%d판째 오브젝트 %d (처음 %d)" % [round_no, objects, baseline_objects])
	main.queue_free()


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func test_다시_시작한_뒤에도_다시_부딪힘() -> void:
	var main := _make_main()
	await wait_frames()
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	main.restart()
	_run(main, 0.5)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	main.queue_free()


func test_다시_시작한_손가락으로_바로_스와이프() -> void:
	var main := _make_main()
	await wait_frames()
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	main.advance(0.6)
	_touch_swipe(main, Vector2(360, 900), Vector2(360, 700), 5)
	assert_false(main.dead, "탭으로 다시 시작")
	assert_true(main.player.is_jumping(), "같은 손가락의 스와이프가 점프")
	main.queue_free()


# ---------- 공중 아래 스와이프·입력 저장 (화면과 연결) ----------

func test_공중_아래_스와이프_중에는_앞에_온_막대를_지나감() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	main.apply_swipe(Dir.UP)
	_run(main, 0.3)
	main.apply_swipe(Dir.DOWN)
	# 스와이프 뒤 막대가 바로 판정 범위로 들어와도 착지와 슬라이드를 거쳐 지나간다
	var item := _put_in_front(main, ObstacleField.Kind.HIGH, -0.75)
	while item["z"] < PlayerAction.HIT_Z + 0.2:
		main.advance(STEP)
		main.runner._process(STEP)
		assert_false(main.dead, "z=%f 에서 부딪힘" % item["z"])
	assert_true(main.player.is_sliding(), "슬라이드 중")
	main.queue_free()


func test_넘고_있던_허들은_아래로_밀어도_부딪히지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	main.apply_swipe(Dir.UP)
	_run(main, 0.2)
	var item := _put_in_front(main, ObstacleField.Kind.LOW, -0.6)
	main.apply_swipe(Dir.DOWN)
	while item["z"] < PlayerAction.HIT_Z + 0.2:
		main.advance(STEP)
		assert_false(main.dead, "z=%f 에서 부딪힘" % item["z"])
	main.queue_free()


func test_아직_앞에_있는_허들에_슬라이드로_들어가면_부딪힘() -> void:
	var main := _make_main()
	await wait_frames()
	main.runner.set_process(false)
	main.apply_swipe(Dir.UP)
	_run(main, 0.3)
	main.apply_swipe(Dir.DOWN)
	var item := _put_in_front(main, ObstacleField.Kind.LOW, -2.5)
	while item["z"] < PlayerAction.HIT_Z + 0.2 and not main.dead:
		main.advance(STEP)
	assert_true(main.dead, "슬라이드는 허들을 못 지남")
	main.queue_free()


func test_레인_이동은_공중에서도_바로이고_저장된_입력을_지우지_않음() -> void:
	var main := _make_main()
	await wait_frames()
	main.apply_swipe(Dir.UP)
	_run(main, PlayerAction.JUMP_TIME - 0.1)
	main.apply_swipe(Dir.UP)
	main.apply_swipe(Dir.LEFT)
	assert_eq(main.lane, 0, "저장 없이 바로")
	_run(main, 0.12)
	assert_true(main.player.is_jumping(), "저장된 점프가 실행됨")
	main.queue_free()
