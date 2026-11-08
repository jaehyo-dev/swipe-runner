extends TestCase
## 게임 화면(main.tscn) 조립 테스트. 화면 모양은 PC·휴대폰에서 직접 확인한다.

const Dir := SwipeDetector.Dir


func _make_main() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	add_child(main)
	main.set_process(false)  # 시간은 advance()로만 흘려 결과를 고정한다
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
	main.advance(0.0)
	var item: Dictionary = main.field.items[0]
	main.runner.position.x = RunLogic.lane_x(item["lane"])
	item["z"] = 0.0
	main.advance(0.0)
	assert_true(main.dead, "아무 동작 없이 부딪히면 어떤 종류든 게임 오버")
	var label: Label = main.find_child("RestartLabel", true, false)
	assert_true(label.visible)
	var t: float = main.elapsed
	main.advance(1.0)
	assert_eq(main.elapsed, t, "게임 오버 뒤엔 시간이 멈춤")
	main.queue_free()


func test_피하면_계속_달림() -> void:
	var main := _make_main()
	await wait_frames()
	main.advance(0.0)
	var item: Dictionary = main.field.items[0]
	main.runner.position.x = RunLogic.lane_x((item["lane"] + 1) % 3)  # 다른 레인
	item["z"] = 0.0
	main.advance(0.0)
	assert_false(main.dead)
	main.queue_free()


func test_시간이_가면_거리가_늘고_장애물_노드가_생기고_지나가면_사라짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.advance(0.0)
	assert_eq(main.get_children().filter(func(c): return c is MeshInstance3D and c.get_child_count() == 1).size(), 1, "장애물 큐브 1개")
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
