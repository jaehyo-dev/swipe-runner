extends TestCase
## 게임 화면(main.tscn) 조립 테스트. 화면 모양은 PC·휴대폰에서 직접 확인한다.

const Dir := SwipeDetector.Dir


const TEST_BEST := "user://test_best_main.txt"
const LAUNCH := DailyRecord.FIRST_DAY * 86400


func _make_main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	DirAccess.remove_absolute(TEST_BEST)
	DirAccess.remove_absolute(TEST_BEST.get_basename() + "_settings.cfg")  # 판 수·소리 설정도 처음부터
	DirAccess.remove_absolute(TEST_BEST.get_basename() + "_daily.cfg")  # 오늘의 판 기록도
	main.clock_override = LAUNCH + 5 * 86400 + 3600.0  # DAILY #6, 01:00 UTC
	main.best_path = TEST_BEST
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
	_place(main, item, 0.0)
	main.advance(0.0)
	assert_true(main.dead, "아무 동작 없이 부딪히면 어떤 종류든 게임 오버")
	var label: Label = main.find_child("RestartLabel", true, false)
	assert_false(label.visible, "충돌 모션을 가리지 않게 바로는 안 뜸")
	main.advance(main.RESTART_DELAY)
	assert_true(label.visible, "0.5초 뒤 안내")
	var t: float = main.travel
	main.advance(1.0)
	assert_eq(main.travel, t, "게임 오버 뒤엔 거리가 멈춤")
	main.queue_free()


func test_피하면_계속_달림() -> void:
	var main := _make_main()
	await wait_frames()
	var item := _add_obstacle(main)
	main.runner.position.x = RunLogic.lane_x((item["lane"] + 1) % 3)  # 다른 레인
	_place(main, item, 0.0)
	main.advance(0.0)
	assert_false(main.dead)
	main.queue_free()


func test_시간이_가면_거리가_늘고_장애물_노드가_생기고_지나가면_사라짐() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.warmed:  # 미리 준비용 장애물이 사라질 때까지
		await wait_frames()
	await wait_frames()
	assert_eq(main.field.items.size(), 0, "첫 장애물(1마디 뒤)은 아직 안개 너머")
	main.advance(12.0)
	await wait_frames()  # 지워진 노드(queue_free)가 정리될 때까지
	assert_eq(main.travel, RunLogic.SPEED * 12.0)
	var label: Label = main.find_child("ScoreLabel", true, false)
	assert_eq(label.text, "180")
	assert_eq(main._obstacles.size(), main.field.items.size(), "화면의 장애물 수 = 살아 있는 장애물 수")
	main.queue_free()


func test_장애물_종류별_색이_정해진_색으로_나옴() -> void:
	var main := _make_main()
	await wait_frames()
	var K := ObstacleField.Kind
	# 사용자 표(ART_BIBLE.md 4·11장, t = 0): 파랑 옆, 주황 위, 분홍 아래
	var expected := {K.BLOCK: Color("2fb8ff"), K.LOW: Color("ff9a1f"), K.HIGH: Color("ff2fa8")}
	var hero_peak := Color("c8fffa") * 2.4  # 주인공 가장자리 최대 밝기 (jelly.gdshader)
	for kind in expected:
		var material: ShaderMaterial = main._kind_meshes[kind]["block"]
		var edge: Color = material.get_shader_parameter("edge_color")
		assert_true(material.get_shader_parameter("tint").is_equal_approx(expected[kind]), "색 (종류 %d)" % kind)
		var body := Color("1c6fb0") if kind == K.BLOCK else Color("120e24")  # 기둥은 파랗게 채운다
		assert_true(material.get_shader_parameter("body_color").is_equal_approx(body), "몸통 (종류 %d)" % kind)
		assert_true(main._kind_meshes[kind]["reflect"].get_shader_parameter("body_color").is_equal_approx(body), "반사 몸통 (종류 %d)" % kind)
		assert_eq(_strongest(edge), _strongest(expected[kind]), "테두리 색조 (종류 %d)" % kind)
		assert_true(_peak(edge) > 1.0, "테두리는 HDR 발광 (종류 %d)" % kind)
		# 밝기 순서(HDR 가장 센 채널 기준): 주인공 > 기호 > 테두리 > 난간
		if kind != K.BLOCK:  # 기둥에는 기호가 없다
			var mark: Color = material.get_shader_parameter("mark_color")
			assert_true(_peak(mark) < _peak(hero_peak), "기호가 주인공보다 어두움 (종류 %d)" % kind)
			assert_true(_peak(mark) > _peak(edge), "기호가 테두리보다 밝음 (종류 %d)" % kind)
		assert_true(_peak(edge) > StageLight.PEAK_MAX, "테두리가 단계 빛남보다 밝음 (종류 %d)" % kind)
	main.queue_free()


## 가장 센 채널 값 (글로우 번짐 크기를 좌우)
func _peak(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## 가장 센 채널 이름 (색조 비교용)
func _strongest(c: Color) -> String:
	if c.r >= c.g and c.r >= c.b:
		return "r"
	return "g" if c.g >= c.b else "b"


func test_화면에_점수와_버전_안내_글자만_있음() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.warmed:
		await wait_frames()
	await wait_frames()
	var labels: Array = main._hud.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 7, "점수 + 최고 + (숨겨진) 다시 시작 안내·배수·PERFECT 한 줄·게임 오버 한 줄·SHARE")
	assert_eq(main._title.find_children("*", "Label", true, false).size(), 9, "메인 화면: 제목 + BEST + 안내 세 줄(기호는 선으로 그림) + 시작 안내 + DAILY 버튼, 오늘의 판: 번호 + 기록 줄")
	assert_eq(main._pause_menu.find_children("*", "Label", true, false).size(), 5, "일시정지: PAUSED + 버튼 셋 + 숫자")
	assert_eq(main._settings.find_children("*", "Label", true, false).size(), 8, "설정: 제목 + 줄 이름 넷 + 값 둘 + DONE")
	assert_eq(main.find_children("*", "Label", true, false).size(), 17 + 5 + 8, "+ 버전")
	assert_false(main.find_child("ShareButton", true, false).visible, "SHARE 처음엔 숨김")
	assert_false(main._pause_menu.visible or main._settings.visible, "일시정지·설정은 처음엔 숨김")
	for hidden in ["MultiplierLabel", "StatsLabel", "RestartLabel", "PerfectLabel"]:
		assert_false(main.find_child(hidden, true, false).visible, hidden + " 처음엔 숨김")
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
	_place(main, item, z)
	return item


## 장애물을 z에 옮긴다. z는 이동 거리에서 계산되므로 도착 거리를 함께 바꾼다.
func _place(main: Node3D, item: Dictionary, z: float) -> void:
	item["z"] = z
	item["arrive"] = main.travel - z


## 장애물을 하나 바로 놓는다 (패턴의 첫 장애물은 몇 초 뒤에나 온다)
func _add_obstacle(main: Node3D) -> Dictionary:
	var z: float = -main.field.ladder.spawn_distance_at(0.0)
	var item := {"id": 9000 + main._obstacles.size(), "lane": 1, "z": z, "kind": ObstacleField.Kind.BLOCK, "beat": 0, "arrive": main.travel - z, "shape": ""}
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
	assert_true(main.travel <= 0.0 and main.travel > -2.0, "거리는 0(출력 지연만큼 앞)에서 다시")
	assert_eq(main.lane, 0, "레인 그대로")
	assert_eq(main.find_child("ScoreLabel", true, false).text, "0")
	assert_false(main.find_child("RestartLabel", true, false).visible)
	assert_eq(main.field.items.size(), 0, "앞 판은 지우고, 새 장애물은 안개에서 나온다")
	assert_eq(main._obstacles.size(), main.field.items.size())
	assert_eq(main._scroll, floor_scroll, "길 무늬가 튀지 않음")
	# 입력을 바로 받고 세상도 바로 움직인다
	main.apply_swipe(Dir.UP)
	assert_true(main.player.is_jumping(), "바로 입력")
	main.advance(STEP)
	assert_true(main.travel > 0.0, "바로 달림")
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


func test_고정_시드면_다시_시작해도_같은_배치() -> void:
	var main := _make_main()
	await wait_frames()
	var first := _arrivals(main)
	main.restart()
	var second := _arrivals(main)
	assert_eq(second, first)
	main.queue_free()


func _arrivals(main: Node3D) -> Array:
	var result := []
	for item in main.field.step(RunLogic.SPEED * 30.0, main.field.ladder.spawn_distance_at(0.0))["spawned"]:
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


func test_다시_시작하면_앞_판을_지우고_1마디_뒤_첫_박에_도착() -> void:
	var main := _make_main()
	await wait_frames()
	_run(main, 11.3)
	var old_ids: Array = main.field.items.map(func(i): return main._obstacles[i["id"]])
	main.dead = true
	main.restart()
	while main.field.items.is_empty():
		main.advance(STEP)
	var first: Dictionary = main.field.items[0]
	assert_eq(first["beat"], float(BeatClock.BEATS_PER_BAR), "1마디 뒤 첫 박")
	for item in main.field.items:
		assert_true(absf(item["z"] + AudioManager.ladder.distance_of_beat(item["beat"]) - main.travel) < 0.001, "박에서 거꾸로 계산한 자리")
		assert_true(-item["z"] <= AudioManager.ladder.spawn_distance_at(main._music_t), "생성 거리보다 가까운 것만")
		assert_false(old_ids.has(main._obstacles[item["id"]]), "새 노드")
	main.queue_free()


func test_재시작_뒤_0_82초_동안_어떤_장애물도_닿을_수_없음() -> void:
	# 판정을 끄는 규칙 대신, 어떤 판을 달린 뒤 재시작해도 첫 도착이 1마디 뒤라 닿을 수 없음을 확인한다
	var main := _make_main()
	await wait_frames()
	for start in 8:
		_run(main, start * 0.37)
		main.dead = true
		main.restart()
		for i in int(0.82 / STEP):
			main.advance(STEP)
			assert_false(main.dead, "재시작 %d: 0.82초 안에 부딪힘" % start)
	main.queue_free()


## 지금 그려지는 장애물 종류와 그 장애물의 크기 (헤드리스는 MultiMesh 변환을 돌려주지 않아 장애물 값으로 본다)
func _drawn_kinds(main: Node3D) -> Dictionary:
	main._sync_pieces()
	var drawn := {}
	for kind in main._kind_meshes:
		if main._kind_meshes[kind]["body"].visible_instance_count > 0:
			drawn[kind] = 1.0
	for piece in main._obstacles.values() + main._leaving:
		drawn[piece.kind] = minf(drawn.get(piece.kind, 1.0), piece.scale.x)
	return drawn


func test_첫_화면_전에는_메인_화면만_그리고_장애물_방울_글자는_화면_뒤에서_하나씩_작게() -> void:
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
	assert_eq(_drawn_kinds(main), {}, "1단계: 장애물은 그리지 않는다 (메인 화면에 보이는 것만)")
	var covers := main.find_children("*", "ColorRect", true, false).filter(func(c: ColorRect) -> bool: return c.is_visible_in_tree())
	assert_eq(covers.size(), 1)
	assert_true(covers[0].get_parent().layer > main._fade.get_parent().layer, "화면 맨 위 가림막")
	assert_eq(main.find_children("Flash", "", true, false).size(), 0, "v0.8.1: 화면 깜빡임 없음")
	while not main.prewarmed:
		await wait_frames()
	await wait_frames()  # 가림막이 지워질 때까지
	var nodes_shown: int = _count_nodes(main)
	var labels_shown: int = main.find_children("*", "Label", true, false).size()
	var seen := {}
	var orbs_seen := false
	while not main.warmed:
		var drawn := _drawn_kinds(main)
		assert_true(drawn.size() <= 1, "2단계: 한 번에 한 묶음 %s" % drawn)
		for kind in drawn:
			assert_true(drawn[kind] < 0.01, "화면에 안 보이게 아주 작게 %s" % drawn)
			seen[kind] = true
		main._sync_orbs()
		if main._orbs.visible_instance_count > 0:
			orbs_seen = true
			assert_true(main._ring.scale.x < 0.01, "방울 고리도 아주 작게")
			assert_true(main._links.visible_instance_count > 0 and main._ring.visible, "실선·고리 셰이더도 그림")
		assert_eq(main.find_children("*", "ColorRect", true, false).filter(func(c: ColorRect) -> bool: return c.is_visible_in_tree()).size(), 0, "가림막 없이 메인 화면이 보인다")
		await wait_frames()
	assert_eq(seen.size(), main._kind_meshes.size(), "세 종류 모두 그림")
	assert_true(orbs_seen)
	await wait_frames()
	assert_eq(_drawn_kinds(main), {}, "다 그린 뒤 치움")
	assert_eq(_count_nodes(main), nodes_shown, "준비용 노드 정리")
	assert_eq(main.find_children("*", "Label", true, false).size(), labels_shown, "글자 그림용 글자는 지움")
	main.queue_free()


func test_준비가_끝나기_전에_시작을_누르면_남은_것을_한꺼번에_그리고_시작한다() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	while not main.prewarmed:
		await wait_frames()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	main._input(key)
	assert_false(main.started, "아직 준비 중: 기다린다")
	await wait_frames()
	var drawn := _drawn_kinds(main)
	while drawn.size() < 2 and not main.warmed:  # 지금 그리던 묶음이 끝나면 남은 것이 한꺼번에
		await wait_frames()
		drawn = _drawn_kinds(main)
	assert_true(drawn.size() >= 2 or main.warmed, "남은 묶음을 한꺼번에 그림")
	while not main.warmed:
		await wait_frames()
	assert_true(main.started, "다 그리고 시작")
	assert_eq(main.lane, 1, "시작 입력은 동작이 아님")
	AudioManager.music.stop()
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
		if round_no == 2:  # 처음 두 판은 한 번만 만드는 것(첫 방울·아슬아슬 소리, 글자 캐시 등)이 생길 수 있다. 그 뒤로 쌓이지 않으면 된다
			baseline_objects = objects
		assert_eq(nodes, baseline, "%d판째 노드 수" % round_no)
		assert_true(round_no < 2 or objects <= baseline_objects + 2, "%d판째 오브젝트 %d (처음 %d)" % [round_no, objects, baseline_objects])
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
	var item := _put_in_front(main, ObstacleField.Kind.HIGH, -0.0625 * RunLogic.SPEED)
	while item["z"] < 0.075 * RunLogic.SPEED:  # 막대가 판정을 벗어난 뒤
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


func _best_label(main: Node3D) -> Label:
	return main.find_child("BestLabel", true, false)


func _run_past(main: Node3D, distance: float) -> void:
	while main.travel <= distance:
		main.field.items.clear()  # 부딪히지 않고 거리만 늘린다
		main.clear_pieces()
		main.advance(STEP)


func test_첫_판에는_최고_줄을_숨기고_게임_오버에_거리를_보여_줌() -> void:
	var main := _make_main()
	await wait_frames()
	assert_false(_best_label(main).visible, "기록 없음")
	_run_past(main, 25.0)
	assert_false(_best_label(main).visible, "첫 판 내내 숨김")
	assert_true(main.record.best >= 25)
	_place(main, _add_obstacle(main), 0.0)
	main.advance(0.0)
	assert_true(main.dead)
	assert_true(_best_label(main).visible)
	assert_eq(_best_label(main).text, "BEST %d" % main.record.best, "첫 기록은 NEW 표시 없음")
	main.queue_free()


func test_최고를_넘는_순간_숫자가_커졌다_돌아오고_NEW_BEST로_바뀌며_바로_저장() -> void:
	var main := _make_main()
	await wait_frames()
	_run_past(main, 20.0)
	main.dead = true
	main.restart()
	var old: int = main.record.best
	assert_eq(_best_label(main).text, "BEST %d" % old)
	assert_true(_best_label(main).visible)
	_run_past(main, old - 1.0)
	assert_eq(_best_label(main).text, "BEST %d" % old, "넘기 전")
	assert_eq(main._score_label.scale, Vector2.ONE)
	_run_past(main, old + 1.0)
	assert_eq(_best_label(main).text, "NEW BEST")
	assert_eq(FileAccess.get_file_as_string(TEST_BEST).to_int(), main.record.best, "게임이 끝나기 전에 저장")
	# 실제 시간을 기다리면 느린 CI에서 흔들리므로 트윈을 직접 진행한다
	main._pop.custom_step(main.POP_UP)
	assert_true(is_equal_approx(main._score_label.scale.x, main.POP_SCALE), "말랑 커짐 %f" % main._score_label.scale.x)
	main._pop.custom_step(main.POP_DOWN + 0.01)
	assert_eq(main._score_label.scale, Vector2.ONE, "돌아옴")
	_place(main, _add_obstacle(main), 0.0)
	main.advance(0.0)
	assert_eq(_best_label(main).text, "NEW BEST %d" % main.record.best)
	main.queue_free()


func test_단계가_오를_때만_난간과_대시가_0_3초_밝아짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var ladder := MusicLadder.new(0)
	AudioManager.ladder = ladder
	ladder.add_segment(10.0, 32, 1)  # BPM만 오름
	ladder.add_segment(20.0, 64, 2)  # 원본 → A
	var glow := func(t: float) -> float:
		main._music_t = t
		main._move_world()
		assert_true(is_equal_approx(main._rail_material.get_shader_parameter("energy"), StageLight.energy(SpeedPalette.at(main._tint)["rail_energy"], main._stage_glow)), "난간에 들어감")
		assert_true(is_equal_approx(main._dash_material.get_shader_parameter("stage_add"), main._stage_glow * (StageLight.PEAK_MAX - StageLight.ROAD_PEAK)), "대시에 들어감")
		return main._stage_glow
	assert_eq(glow.call(10.05), 0.0, "BPM만 오르면 신호 없음")
	assert_eq(glow.call(19.99), 0.0)
	assert_true(glow.call(20.0) > 0.99, "경계 박에 바로 밝음")
	assert_true(absf(glow.call(20.15) - 0.5) < 0.01)
	assert_eq(glow.call(20.31), 0.0, "0.3초 뒤 끝")
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


## 주인공 자리 바로 앞에 방울 하나를 놓는다 (박은 이동 거리에서 거꾸로 계산하지 않고 z만 쓴다)
func _put_orb(main: Node3D, trail: int, z := -0.3, y := 0.4) -> Dictionary:
	var orb := {"id": 9000 + main.field.orbs.size(), "beat": 0.0, "x": main.runner.position.x, "y": y, "lane": main.lane, "trail": trail, "index": 0, "z": z, "arrive": main.travel - z}
	main.field.orbs.append(orb)
	return orb


func test_방울을_먹으면_점수와_소리_놓치면_콤보가_끊기고_배수가_떨어짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var played: Array = []
	var log := func(sound: StringName, _pitch: float) -> void: played.append(String(sound))
	AudioManager.played.connect(log)
	AudioManager.unblock()  # 앞 테스트의 충돌이 효과음을 막아 두었을 수 있다
	AudioManager._last_orb = -INF
	main.score.combo = 9
	_put_orb(main, 1)
	main.advance(STEP)
	assert_eq(main.score.orbs, 1)
	assert_eq(main.score.points, 130, "10번째 방울은 x2")
	assert_eq(main._score_label.text, str(int(main.travel) + 130))
	assert_true(main._mult_label.visible, "x2 표시")
	assert_eq(main._mult_label.text, "×2")
	assert_true("orb" in played, "톡")
	var missed := _put_orb(main, 2, -0.3, 2.5)  # 서 있으면 닿지 않는 높이
	_run(main, 0.2)
	assert_true(missed.has("missed"), "지나가면 놓침")
	assert_eq(main.score.combo, 0)
	assert_true("combo_break" in played, "툭")
	# 놓친 방울은 0.1초 안에, 늦어도 z 1.5 전에 작아져 없어진다 (카메라 앞에서 커지지 않게)
	while not main.warmed:  # 준비 중 미리 그리는 방울이 빠진 뒤에 센다
		await wait_frames()
	main.field.orbs.assign([missed])
	missed["missed"] = main._music_t
	missed["z"] = 1.4
	main._sync_orbs()
	assert_eq(main._orbs.visible_instance_count, 1, "z 1.4: 아직 작게")
	missed["z"] = 1.5
	main._sync_orbs()
	assert_eq(main._orbs.visible_instance_count, 0, "z 1.5: 없음")
	missed["z"] = 0.7
	missed["missed"] = main._music_t - main.MISS_FADE
	main._sync_orbs()
	assert_eq(main._orbs.visible_instance_count, 0, "0.1초 뒤: 없음")
	_run(main, main.MULT_DROP_TIME + 0.05)
	main._mult_tween.custom_step(1.0)
	assert_false(main._mult_label.visible, "배수가 떨어지며 사라짐")
	AudioManager.played.disconnect(log)
	main.queue_free()


func test_같은_줄_이웃_방울만_빛_실선으로_잇고_먹으면_고리가_퍼졌다_사라짐() -> void:
	var main := _make_main()
	while not main.warmed:  # 준비 중에는 고리를 미리 그려 둔다
		await wait_frames()
	main.field.items.clear()
	main.field.orbs.clear()
	var first := _put_orb(main, 7, -0.3)
	var second := _put_orb(main, 7, -1.3)
	second["index"] = 1
	var other := _put_orb(main, 8, -2.3)  # 다른 줄: 잇지 않는다
	other["index"] = 2
	main._sync_orbs()
	assert_eq(main._links.visible_instance_count, 1, "같은 줄 이웃 한 쌍")
	main.advance(STEP)
	assert_true(first.has("taken"), "첫 방울 먹음")
	main._sync_orbs()
	assert_true(main._ring.visible, "빛 고리")
	assert_eq(main._links.visible_instance_count, 0, "먹은 방울의 실선은 사라짐")
	main.field.orbs.clear()  # 남은 방울을 또 먹으면 고리가 다시 시작된다
	_run(main, main.RING_TIME + 0.02)
	main._sync_orbs()
	assert_false(main._ring.visible, "0.15초 뒤 사라짐")
	main.queue_free()


func test_PERFECT는_점수_아래_글자와_더해진_점수_세어_올라가는_숫자_게임_오버_한_줄() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var item := _put_in_front(main, ObstacleField.Kind.BLOCK, -2.2)  # 속도 15에서 0.15초 뒤 도착 (판정 0.16초)
	main.apply_swipe(SwipeDetector.Dir.LEFT)
	var shown := []
	for i in 24:  # 레인 이동 트윈도 같은 시간만큼
		if main.runner._move_tween.is_running():
			main.runner._move_tween.custom_step(STEP)
		main.advance(STEP)
		shown.append(int(main._score_label.text) - int(main.score.total(main.travel)))
	assert_false(main.dead, "피함")
	assert_eq(main.score.close, 1, "도착 0.15초 전 이동")
	assert_true(main._perfect_label.visible)
	assert_eq(main._perfect_label.text, "PERFECT  +100", "더해진 점수는 같은 줄 오른쪽")
	assert_true(main._perfect_label.label_settings == main._best_label.label_settings, "BEST와 같은 글꼴·크기·색")
	assert_eq(main._perfect_label.offset_top - main.BEST_TOP, main.BEST_TOP - main.MULT_TOP, "BEST 바로 아래, 배수-BEST와 같은 줄 간격")
	assert_true(shown.min() < 0 and shown.min() > -100, "점수 숫자가 세어 올라가는 중: %s" % str(shown))
	_run(main, main.COUNT_TIME)
	assert_eq(main._score_label.text, str(main.score.total(main.travel)), "0.3초 동안 다 올라감")
	assert_true(item.has("passed"))
	main._on_close(item, 200)  # 사라지기 전에 또
	assert_eq(main._perfect_label.text, "PERFECT ×2  +200", "연속")
	assert_true(absf(main._perfect_label.scale.x - 1.1) < 0.001, "다시 '톡' 1.1배에서")
	var y: float = main._perfect_label.position.y
	main._perfect_tween.custom_step(main.PERFECT_POP_TIME + main.PERFECT_HOLD + main.PERFECT_FADE * 0.5)
	assert_eq(main._perfect_label.position.y, y, "떠오르지 않고 제자리에서 흐려짐")
	assert_true(main._perfect_label.modulate.a < 1.0)
	main._perfect_tween.custom_step(main.PERFECT_FADE)
	assert_false(main._perfect_label.visible, "사라짐")
	main._on_close(item, 100)
	assert_eq(main._perfect_label.text, "PERFECT  +100", "사라진 뒤에는 처음부터")
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	assert_true(main._stats_label.visible)
	assert_false(main._mult_label.visible, "게임 오버에는 배수를 숨김")
	assert_false(main._perfect_label.visible, "게임 오버에는 PERFECT를 숨김")
	assert_eq(main._stats_label.text, "ORBS 0 · PERFECT 1 · %dm" % int(main.travel))
	main.restart()
	assert_false(main._stats_label.visible)
	assert_eq(main.score.close, 0, "재시작하면 0")
	main.queue_free()


# ---------- 메인 화면 ----------

## 메인 화면에서 시작하는 게임 화면 (음악은 멈춘 상태에서)
func _make_menu() -> Node3D:
	AudioManager.music.stop()
	var main := _make_main()
	main.started = false
	while not main.warmed:
		await wait_frames()
	main.advance(STEP)
	return main


func _touch(main: Node3D, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = at
	main._input(touch)


func test_메인_화면은_장애물_없이_젤리가_박마다_숨_쉬고_제목과_안내가_보임() -> void:
	var main: Node3D = await _make_menu()
	assert_true(main._camera.position.is_equal_approx(main._menu_cam), "메인 화면 카메라")
	var size: Vector2 = main.get_viewport().get_visible_rect().size
	var pool: float = main._camera.unproject_position(Vector3(0.0, 0.0, main.POOL_FRONT_Z)).y
	assert_true(main._title.start_label.get_global_rect().position.y >= pool, "SWIPE TO START는 젤리 빛 웅덩이 아래 (%.0f, 웅덩이 %.0f)" % [main._title.start_label.get_global_rect().position.y, pool])
	assert_true(main._title.start_label.get_global_rect().end.y <= size.y - TitleScreen.START_FLOOR + 0.5, "화면 안 (버전 글자 위)")
	assert_eq(main._hud.modulate.a, 0.0, "점수 글자는 숨김")
	assert_true(main._title.visible)
	assert_false(main._title.best_label.visible, "기록이 없으면 BEST 숨김")
	assert_true(main._title.guide.visible, "처음에는 조작 안내")
	var beat_time := MusicLadder.beat_time(AudioManager.start_step)
	var glows := 0
	var alphas: Array[float] = []
	main.runner._process(STEP)  # 0박의 부풂은 세지 않는다
	for i in roundi(beat_time * 3.5 / STEP):
		main.advance(STEP)
		if main.runner._absorb == 1.0:
			glows += 1
		main.runner._process(STEP)
		alphas.append(main._title.start_label.modulate.a)
	assert_eq(glows, 3, "3박에 3번 부풂")
	assert_true(alphas.max() - alphas.min() > (TitleScreen.START_HIGH - TitleScreen.START_LOW) * 0.9, "SWIPE TO START가 밝아졌다 흐려짐")
	assert_true(alphas.max() < main._title.best_label.label_settings.font_color.a, "가장 밝을 때도 BEST 줄보다 살짝 어둡게")
	assert_true(main.field.items.is_empty() and main.travel == 0.0, "장애물 없음, 제자리")
	assert_true(main._streaks.visible_instance_count <= main.MENU_STREAKS, "빛 줄기는 아주 적게")
	main.queue_free()


func test_시작하면_제목이_0_3초에_흐려지고_카메라가_0_6초에_게임_자리로_들어감() -> void:
	var main: Node3D = await _make_menu()
	_touch(main, Vector2(360, 700))
	assert_true(main.started)
	assert_eq(main.save.plays, 1, "판 수 저장")
	assert_eq(SaveData.new(main.save._path).plays, 1)
	await get_tree().create_timer(main.TITLE_FADE + 0.05).timeout
	assert_false(main._title.visible, "제목·안내 사라짐")
	assert_eq(main._hud.modulate.a, 1.0, "점수 글자 나타남")
	assert_false(main._camera.position.is_equal_approx(main.GAME_CAM), "카메라는 아직 들어가는 중")
	await get_tree().create_timer(main.CAMERA_IN - main.TITLE_FADE).timeout
	assert_true(main._camera.position.is_equal_approx(main.GAME_CAM), "게임 카메라 자리")
	while main.field.items.is_empty():
		main.advance(STEP)
	assert_eq(main.field.items[0]["beat"], float(BeatClock.BEATS_PER_BAR), "첫 장애물은 1마디 뒤 첫 박")
	AudioManager.music.stop()
	main.queue_free()


func test_소리_버튼은_시작하지_않고_음악_효과음을_끄고_켜며_저장() -> void:
	var main: Node3D = await _make_menu()
	var button: Control = main._title.sound
	_touch(main, button.get_global_rect().get_center())
	assert_false(main.started, "소리 버튼은 시작이 아님")
	assert_true(AudioManager.muted and AudioServer.is_bus_mute(0), "음악·효과음 모두 끔")
	assert_eq(button.kind, UiIcon.Kind.SOUND_OFF)
	assert_true(SaveData.new(main.save._path).muted, "저장")
	_touch(main, button.get_global_rect().get_center())
	assert_false(AudioManager.muted or AudioServer.is_bus_mute(0), "다시 켬")
	assert_false(SaveData.new(main.save._path).muted)
	main.queue_free()


func test_게임_오버의_집_버튼은_0_4초_페이드로_메인_화면에_가고_첫_곡이_6dB_작게_흐름() -> void:
	var main: Node3D = await _make_menu()
	_touch(main, Vector2(360, 700))
	_run(main, 1.0)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	assert_false(main._home.visible, "부딪힌 직후에는 숨김")
	_run(main, main.RESTART_DELAY + 0.05)
	assert_true(main._home.visible, "다시 시작 안내와 함께 보임")
	_touch(main, main._home.get_global_rect().get_center())
	assert_true(main.dead, "페이드가 가릴 때까지는 그대로")
	_touch(main, Vector2(360, 700))
	assert_true(main.dead, "페이드 중 입력은 받지 않음")
	await get_tree().create_timer(main.HOME_FADE * 0.5 + 0.05).timeout
	assert_false(main.dead or main.started, "메인 화면")
	assert_true(main.field.items.is_empty() and main._obstacles.is_empty(), "앞 판 장애물 지움")
	assert_true(main._title.visible and main._title.best_label.visible, "BEST가 보임")
	assert_true(AudioManager.music.playing, "메인 화면 음악")
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), AudioManager.MUSIC_DB + AudioManager.MENU_DB, "게임보다 6dB 작게")
	assert_eq(AudioManager.ladder.segment_at(AudioManager.music_time)["step"], 0, "원본 100BPM")
	await get_tree().create_timer(main.HOME_FADE * 0.5).timeout
	assert_false(main._fade.visible, "페이드 끝")
	main.advance(STEP)
	_touch(main, Vector2(360, 700))
	assert_true(main.started, "다시 시작")
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), AudioManager.MUSIC_DB, "게임 음악은 원래 크기")
	assert_eq(main.save.plays, 2)
	AudioManager.music.stop()
	main.queue_free()


func test_세_판을_한_뒤에는_조작_안내를_숨김() -> void:
	var main: Node3D = await _make_menu()
	main.save.plays = SaveData.GUIDE_RUNS - 1
	main.dead = true
	main.go_home()
	await get_tree().create_timer(main.HOME_FADE + 0.05).timeout
	assert_true(main._title.guide.visible, "3판째 전에는 보임")
	_touch(main, Vector2(360, 700))
	main.dead = true
	main.go_home()
	await get_tree().create_timer(main.HOME_FADE + 0.05).timeout
	assert_false(main._title.guide.visible, "4판째부터 숨김")
	AudioManager.music.stop()
	main.queue_free()


func test_메인_화면에_오자마자_시작해도_앞_페이드가_새_음악을_멈추지_않음() -> void:
	var main: Node3D = await _make_menu()
	_touch(main, Vector2(360, 700))
	main.dead = true
	main.go_home()
	await get_tree().create_timer(main.HOME_FADE + 0.02).timeout  # 메인 화면 음악이 겹쳐 넘어가는 중(0.3초)에 바로 시작
	assert_false(main.started)
	_touch(main, Vector2(360, 700))
	assert_true(main.started)
	await get_tree().create_timer(AudioManager.RESTART_FADE + 0.1).timeout
	assert_true(AudioManager.music.playing, "새 게임 음악이 계속 흐름")
	assert_eq(AudioManager.music.volume_db, 0.0, "제 크기")
	AudioManager.music.stop()
	main.queue_free()


## 메인 화면에서 DAILY 버튼으로 오늘의 판 시작 화면에 들어간다
func _open_daily(main: Node3D) -> void:
	_touch(main, main._title.daily_button.get_global_rect().get_center())


func test_메인_화면의_DAILY_버튼과_오늘_안_했으면_점() -> void:
	var main: Node3D = await _make_menu()
	assert_true(main._title.daily_button.is_visible_in_tree())
	assert_eq(main._title.daily_button.text, "DAILY #6")
	assert_true(main._title.daily_dot.visible, "오늘 아직 안 함")
	var start: Rect2 = main._title.start_label.get_global_rect()
	var button: Rect2 = main._title.daily_button.get_global_rect()
	assert_true(button.position.y >= start.end.y, "SWIPE TO START 아래")
	assert_true(button.end.y <= main.get_viewport().get_visible_rect().size.y - TitleScreen.START_FLOOR, "버전 글자와 겹치지 않음")
	main.queue_free()


func test_오늘의_판_시작_화면과_집_버튼() -> void:
	var main: Node3D = await _make_menu()
	_open_daily(main)
	assert_true(main.daily_mode)
	assert_false(main.started, "버튼은 시작이 아님")
	assert_true(main._title.daily_home.visible)
	assert_eq(main._title._daily_title.text, "DAILY #6")
	assert_eq(main._title._daily_lines.text, "STREAK 0\nNEW IN 23H 0M", "기록이 없으면 TODAY BEST 숨김")
	_touch(main, main._title.daily_home.get_global_rect().get_center())
	assert_false(main.daily_mode, "집 → 메인")
	assert_false(main.started)
	assert_true(main.record == main.normal_record)
	main.queue_free()


func test_오늘의_판은_그날_씨앗이고_기록이_일반_최고와_섞이지_않음() -> void:
	var main: Node3D = await _make_menu()
	main.normal_record.update(777)
	main.normal_record.save()
	_open_daily(main)
	_touch(main, Vector2(360, 700))
	assert_true(main.started)
	assert_eq(main.daily.tries, 1)
	assert_eq(main.field._pattern._rng.seed, DailyRecord.seed_of(main.today()), "그날 씨앗")
	assert_false(main._best_label.visible, "오늘 기록이 없으면 숨김 (일반 BEST 777이 아님)")
	_run(main, 2.0)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_true(main.dead)
	var daily_best: int = main.daily.best
	assert_true(daily_best > 0)
	assert_eq(main._best_label.text, "DAILY BEST %d" % daily_best)
	assert_eq(main._stats_label.text, "TRIES 1")
	_run(main, main.RESTART_DELAY + 0.05)
	assert_true(main._share.visible, "SHARE")
	_touch(main, main._share.get_global_rect().get_center())
	assert_true(main.dead, "SHARE는 다시 시작이 아님")
	assert_eq(main._share.text, "COPIED")
	assert_eq(main.shared_text, "SWIPE PULSE Daily #6 — %d %s" % [main._final_score, main.GAME_URL])
	main._share_tween.custom_step(main.COPIED_TIME + 0.01)
	assert_eq(main._share.text, "SHARE", "0.8초 뒤 돌아옴")
	assert_eq(BestRecord.new(TEST_BEST).best, 777, "일반 최고 점수 그대로")
	# 다시 시작: 도전 2, 플레이 중 BEST 자리에 DAILY BEST
	_touch(main, Vector2(360, 700))
	assert_false(main.dead)
	assert_eq(main.daily.tries, 2)
	assert_eq(main._best_label.text, "DAILY BEST %d" % daily_best)
	assert_true(main._best_label.visible)
	main.queue_free()


func test_일반_모드는_SHARE가_없고_DAILY_BEST도_아님() -> void:
	var main: Node3D = await _make_menu()
	_touch(main, Vector2(360, 700))
	assert_false(main.daily_mode)
	_run(main, 2.0)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	_run(main, main.RESTART_DELAY + 0.05)
	assert_false(main._share.visible)
	assert_eq(main.daily.tries, 0, "오늘의 판 도전 횟수 그대로")
	assert_true(main._stats_label.text.begins_with("ORBS"))
	main.queue_free()


func test_플레이_중_자정을_넘기면_그_판은_시작한_날_다음_판은_새_날() -> void:
	var main: Node3D = await _make_menu()
	main.clock_override = LAUNCH + 6 * 86400 - 5.0  # #6의 23:59:55
	_open_daily(main)
	_touch(main, Vector2(360, 700))
	var first_day: int = main.daily.day
	main.clock_override += 10.0  # 자정이 지남
	_run(main, 2.0)
	_put_in_front(main, ObstacleField.Kind.BLOCK)
	main.advance(STEP)
	assert_eq(main.daily.day, first_day, "시작한 날의 기록")
	assert_true(DailyRecord.new(main.daily._path, first_day).best > 0)
	_run(main, main.RESTART_DELAY + 0.05)
	_touch(main, Vector2(360, 700))
	assert_eq(main.daily.day, first_day + 1, "다음 판은 새 날")
	assert_eq(main.daily.tries, 1)
	assert_eq(main.field._pattern._rng.seed, DailyRecord.seed_of(first_day + 1))
	assert_eq(main.daily.streak_on(first_day + 1), 2, "이틀 연속")
	main.queue_free()
