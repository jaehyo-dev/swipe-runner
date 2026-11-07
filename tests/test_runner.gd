extends TestCase
## 주인공(물방울 젤리)의 형태와 달리기 모션 테스트. 질감·색감은 PC·휴대폰 화면에서 직접 확인한다.


func _make_runner() -> Runner:
	var runner := Runner.new()
	add_child(runner)
	return runner


func test_몸_메시는_바닥이_y0이고_높이가_BODY_HEIGHT() -> void:
	var box := Runner.build_body_mesh().get_aabb()
	assert_true(absf(box.position.y) < 0.001, "바닥 y=%f" % box.position.y)
	assert_true(absf(box.size.y - Runner.BODY_HEIGHT) < 0.001, "높이 %f" % box.size.y)


func test_몸은_아래쪽이_가장_넓고_위는_뾰족한_물방울() -> void:
	var mesh := Runner.build_body_mesh(24, 32)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var widest_y := 0.0
	var widest := 0.0
	var top := 0.0
	for v in verts:
		var r := Vector2(v.x, v.z).length()
		if r > widest:
			widest = r
			widest_y = v.y
		if v.y > Runner.BODY_HEIGHT * 0.95:
			top = maxf(top, r)
	assert_true(widest_y < Runner.BODY_HEIGHT * 0.5, "가장 넓은 높이 %f" % widest_y)
	assert_true(top < widest * 0.3, "위 끝 반지름 %f, 최대 %f" % [top, widest])


func test_몸_메시에_삼각형이_있고_법선이_바깥을_향함() -> void:
	var arrays := Runner.build_body_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_true(verts.size() > 0 and verts.size() % 3 == 0, "삼각형 수")
	# 몸통 옆면(중간 높이)의 법선은 중심 바깥쪽이어야 한다 (감기 순서가 뒤집히면 안쪽을 향함)
	var checked := 0
	for i in verts.size():
		var v := verts[i]
		if absf(v.y - Runner.BODY_HEIGHT * 0.3) < 0.03 and Vector2(v.x, v.z).length() > 0.1:
			assert_true(Vector2(normals[i].x, normals[i].z).dot(Vector2(v.x, v.z)) > 0.0, "법선 방향")
			checked += 1
	assert_true(checked > 0, "검사한 점 수")


func test_구성_요소_발_없음_꼭지_그림자_눈_둘() -> void:
	var runner := _make_runner()
	await wait_frames()
	assert_not_null(runner._shadow, "그림자")
	assert_eq(runner._body.get_child_count(), 3, "머리 꼭지 1 + 눈 2")
	# 몸통 한 덩어리: 달린 메시는 몸·그림자뿐 (러너의 직접 자식 메시 2개)
	assert_eq(runner.get_child_count(), 2, "러너 자식: 몸 + 그림자")
	runner.queue_free()


func test_땅에_닿는_순간이_가장_납작하고_넓음() -> void:
	var runner := _make_runner()
	runner.set_phase(0.0)  # hop = 0: 바닥
	var low := runner._body.scale
	runner.set_phase(PI / 2.0)  # hop = 1: 가장 높음
	var high := runner._body.scale
	assert_true(low.y < high.y, "납작 %f < 길쭉 %f" % [low.y, high.y])
	assert_true(low.x > high.x, "넓음 %f > 좁음 %f" % [low.x, high.x])
	assert_true(low.y <= 0.8, "눌림 폭이 충분히 큼: %f" % low.y)
	runner.queue_free()


func test_착지에서_몸이_땅에_닿고_박자마다_튐() -> void:
	var runner := _make_runner()
	runner.set_phase(0.0)
	assert_true(absf(runner._body.position.y) < 0.001, "착지 시 몸 바닥이 땅")
	runner.set_phase(PI / 2.0)
	assert_true(absf(runner._body.position.y - Runner.HOP_HEIGHT) < 0.001, "정점 높이")
	runner.queue_free()


func test_그림자는_착지에서_커졌다_공중에서_작아짐() -> void:
	var runner := _make_runner()
	runner.set_phase(PI / 2.0)
	var air: float = runner._shadow.scale.x
	runner.set_phase(0.0)
	var land: float = runner._shadow.scale.x
	runner.set_phase(0.0)
	assert_true(land > 1.0, "착지 순간 1보다 커짐 %f" % land)
	assert_true(air < 1.0 and air < land, "공중 %f < 착지 %f" % [air, land])
	runner.queue_free()


func test_오른쪽으로_가면_몸이_왼쪽으로_처졌다가_돌아옴() -> void:
	var runner := _make_runner()
	var peak := 0.0
	for i in 8:  # 0.12초 동안 오른쪽 이동
		runner.step_sway(12.0, 0.015)
		peak = maxf(peak, runner._sway)
	assert_true(peak > 0.1, "위가 왼쪽(회전 +)으로 처짐 %f" % peak)
	assert_true(peak <= Runner.SWAY_MAX * 1.5, "과하지 않음 %f" % peak)
	for i in 100:  # 멈춘 뒤 1.5초
		runner.step_sway(0.0, 0.015)
	assert_true(absf(runner._sway) < 0.01, "다시 똑바로 %f" % runner._sway)
	runner.queue_free()
