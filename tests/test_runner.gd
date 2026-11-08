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


func test_몸은_아래쪽이_가장_넓고_위는_둥근_돔() -> void:
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
	assert_true(top > widest * 0.3 and top < widest, "정수리가 뾰족하지 않고 둥긂: 위 반지름 %f, 최대 %f" % [top, widest])


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


func test_구성_요소_발_꼭지_없음_그림자_눈_둘() -> void:
	var runner := _make_runner()
	await wait_frames()
	assert_not_null(runner._shadow, "그림자")
	assert_eq(runner._body.get_child_count(), 2, "눈 2 (꼭지 없음)")
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
	assert_true(low.y <= 0.95 and low.y >= 0.85, "눌림이 은은함(존재감만): %f" % low.y)
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


## 실제 레인 이동 곡선(SINE ease-in-out, MOVE_TIME)으로 60fps 동안 출렁임을 진행하고 프레임별 정수리 밀림을 돌려준다.
func _simulate_lane_move(runner: Runner, seconds: float) -> Array[float]:
	var dist := RunLogic.LANE_WIDTH
	var dt := 1.0 / 60.0
	var prev_x := 0.0
	var out: Array[float] = []
	for i in roundi(seconds / dt):
		var t := minf((i + 1) * dt, Runner.MOVE_TIME)
		var x := dist * (1.0 - cos(PI * t / Runner.MOVE_TIME)) * 0.5
		runner.step_wobble((x - prev_x) / dt, dt)
		prev_x = x
		out.append(runner.lean())
	return out


func test_레인_이동_중에는_윗부분이_늦게_따라옴() -> void:
	var runner := _make_runner()
	var leans := _simulate_lane_move(runner, Runner.MOVE_TIME * 0.5)
	# 오른쪽으로 출발하면 정수리가 바닥보다 왼쪽(-)에 남는다
	assert_true(leans[-1] < -0.03, "정수리가 뒤처짐 %f" % leans[-1])
	runner.queue_free()


func test_멈춘_뒤_2에서_3번_출렁이고_0_5초_안에_멈춤() -> void:
	var runner := _make_runner()
	var leans := _simulate_lane_move(runner, Runner.MOVE_TIME + 1.0)
	var peak := 0.0
	for l in leans:
		peak = maxf(peak, absf(l))
	assert_true(peak > 0.05 and peak <= Runner.WOBBLE_MAX, "출렁임 크기 %f" % peak)
	# 이동이 끝난 뒤의 눈에 띄는 출렁임(최대치의 15% 이상인 꺾임) 횟수
	var start := roundi(Runner.MOVE_TIME * 60.0) - 1
	var swings := 0
	for i in range(maxi(start, 1), leans.size() - 1):
		var turn := (leans[i] - leans[i - 1]) * (leans[i + 1] - leans[i]) < 0.0
		if turn and absf(leans[i]) >= peak * 0.15:
			swings += 1
	assert_true(swings >= 2 and swings <= 3, "출렁임 횟수 %d" % swings)
	# 이동 끝 + 0.5초부터는 최대치의 3% 안에서 멈춰 있어야 함
	for i in range(roundi((Runner.MOVE_TIME + 0.5) * 60.0), leans.size()):
		assert_true(absf(leans[i]) < peak * 0.03, "%.2f초에 아직 흔들림 %f" % [(i + 1) / 60.0, leans[i]])
	runner.queue_free()


func test_레인_이동_출렁임이_덜컹이지_않음() -> void:
	var runner := _make_runner()
	var leans := _simulate_lane_move(runner, Runner.MOVE_TIME + 0.6)
	var peak := 0.0
	var max_jerk := 0.0  # 프레임 간 변화량의 변화(=속도가 한 프레임에 얼마나 바뀌나)
	for i in range(2, leans.size()):
		peak = maxf(peak, absf(leans[i]))
		max_jerk = maxf(max_jerk, absf((leans[i] - leans[i - 1]) - (leans[i - 1] - leans[i - 2])))
	# 같은 크기의 매끈한 출렁임(사인파)이 낼 수 있는 값 ω²·A·dt² 안이어야 함. 속도가 툭 튀면(덜컹) 이 값을 넘는다
	var smooth_limit := Runner.WOBBLE_STIFF * peak / 3600.0 * 1.2
	assert_true(max_jerk < smooth_limit, "프레임마다 변화가 급하지 않음 %f < %f" % [max_jerk, smooth_limit])
	runner.queue_free()


func test_레인_이동_시간과_튀기_높이는_그대로() -> void:
	assert_eq(Runner.MOVE_TIME, 0.18, "레인 이동 시간")
	assert_eq(Runner.HOP_HEIGHT, 0.07, "위아래 튀기 높이")


func test_출렁임은_셰이더_기울기로_그리고_몸은_회전하지_않음() -> void:
	var runner := _make_runner()
	await wait_frames()
	runner._wobble = 0.2
	runner._animate()
	assert_eq(runner._body.rotation.z, 0.0, "몸 통째 회전 없음")
	assert_eq(runner._mat.get_shader_parameter("lean"), runner.lean(), "셰이더에 정수리 밀림 전달")
	runner.queue_free()


func test_착지_뒤_몸이_출렁이며_목표로_돌아옴() -> void:
	var runner := _make_runner()
	runner.set_phase(0.0)  # 납작하게 착지한 모양 (눌림 1)
	var min_squish := 1.0
	for i in 200:  # 목표가 0(공중)으로 바뀌고 1.6초
		runner._step_squish(0.0, 0.008)
		min_squish = minf(min_squish, runner._squish)
	assert_true(min_squish < -0.05, "목표를 지나쳐 길쭉하게 튕김 %f" % min_squish)
	assert_true(absf(runner._squish) < 0.01, "결국 목표로 안정 %f" % runner._squish)
	runner.queue_free()


func test_레인_이동은_출발이_부드러움() -> void:
	var runner := _make_runner()
	await wait_frames()
	var dist: float = RunLogic.lane_x(2) - runner.position.x
	runner.move_to_lane(2)
	await wait_frames(2)
	# 처음엔 천천히 출발해야 한다 (예전 ease-out은 첫 프레임에 30% 넘게 점프함)
	assert_true(runner.position.x < dist * 0.2, "출발 직후 이동량 %f / %f" % [runner.position.x, dist])
	runner.queue_free()


func test_튀는_높이는_작게_유지됨() -> void:
	# 집중을 깨지 않도록 정점도 몸 높이의 10% 이하
	assert_true(Runner.HOP_HEIGHT <= Runner.BODY_HEIGHT * 0.1 and Runner.HOP_HEIGHT > 0.03, "HOP_HEIGHT %f" % Runner.HOP_HEIGHT)
