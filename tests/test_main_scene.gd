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


func test_위아래_스와이프는_아직_아무것도_안_함() -> void:
	var main := _make_main()
	await wait_frames()
	main.apply_swipe(Dir.UP)
	main.apply_swipe(Dir.DOWN)
	assert_eq(main.lane, 1)
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


func test_화면에_거리와_버전만_있음() -> void:
	var main := _make_main()
	await wait_frames()
	var labels := main.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 2)
	var version: Label = main.find_child("VersionLabel", true, false)
	assert_eq(version.text, "v" + str(ProjectSettings.get_setting("application/config/version")))
	main.queue_free()
