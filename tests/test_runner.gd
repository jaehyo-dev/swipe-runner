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


func test_바닥은_가장_넓은_폭의_약_80퍼센트가_땅에_닿음() -> void:
	var verts: PackedVector3Array = Runner.build_body_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	var foot := 0.0
	for v in verts:
		var r := Vector2(v.x, v.z).length()
		widest = maxf(widest, r)
		if v.y < 0.001:
			foot = maxf(foot, r)
	var ratio := foot / widest
	assert_true(ratio > 0.75 and ratio < 0.85, "접지 폭 비율 %f" % ratio)
	# 가장자리는 살짝 둥글게: 바닥 바로 위(높이 3%)는 바닥보다 넓고 가장 넓은 폭보다 좁다
	var low := Runner._blob_point(0.03 / Runner.BODY_HEIGHT, 0.0).x
	assert_true(low > foot and low < widest, "둥근 모서리 %f (바닥 %f, 최대 %f)" % [low, foot, widest])


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
		# 바닥 원판은 아래를, 아래 모서리(높이 0~0.15의 옆면)는 바깥을 향해야 한다
		if v.y < 0.001 and Vector2(v.x, v.z).length() < 0.2:
			assert_true(normals[i].y < -0.9, "바닥 원판 법선이 아래")
			checked += 1
		elif v.y > 0.02 and v.y < 0.15:
			assert_true(Vector2(normals[i].x, normals[i].z).dot(Vector2(v.x, v.z)) > 0.0, "아래 모서리 법선 방향")
			checked += 1
	assert_true(checked > 100, "검사한 점 수 %d" % checked)


func test_구성_요소_발_꼭지_없음_그림자_눈_둘() -> void:
	var runner := _make_runner()
	await wait_frames()
	assert_not_null(runner._shadow, "그림자")
	assert_eq(runner._body.get_child_count(), 2, "눈 2 (꼭지 없음)")
	# 몸통 한 덩어리: 달린 메시는 몸·그림자뿐 (러너의 직접 자식 메시 2개)
	assert_eq(runner.get_child_count(), 2, "러너 자식: 몸 + 그림자")
	runner.queue_free()


func test_눌리는_박자에_가장_납작하고_넓음() -> void:
	var runner := _make_runner()
	runner.set_phase(0.0)  # hop = 0: 가장 눌리는 박자
	var low := runner._body.scale
	runner.set_phase(PI / 2.0)  # hop = 1: 가장 늘어나는 박자
	var high := runner._body.scale
	assert_true(low.y < high.y, "납작 %f < 길쭉 %f" % [low.y, high.y])
	assert_true(low.x > high.x, "넓음 %f > 좁음 %f" % [low.x, high.x])
	assert_true(low.y <= 0.95 and low.y >= 0.85, "눌림이 은은함(존재감만): %f" % low.y)
	runner.queue_free()


## 달리기를 60fps로 진행하며 프레임마다 (몸 바닥 높이, 정수리 높이)를 모은다.
func _simulate_run(runner: Runner, seconds: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in roundi(seconds * 60.0):
		runner._process(1.0 / 60.0)
		var bottom := runner._body.position.y  # 메시 바닥이 y=0이고 크기 변화는 바닥 기준이라 몸 바닥 = 몸 위치
		out.append(Vector2(bottom, bottom + runner._body.scale.y * Runner.BODY_HEIGHT))
	return out


func test_달리는_동안_몸_바닥은_항상_땅() -> void:
	var runner := _make_runner()
	for s in _simulate_run(runner, 3.0):
		assert_eq(s.x, 0.0, "몸 바닥 높이")
	runner.queue_free()


func test_달리는_동안_위아래_움직임은_v0_1_6보다_작음() -> void:
	# v0.1.6 정수리 위아래 폭: 튀기 0.07 + 눌림 배율 0.35 기준 크기 변화(납작 0.902 ~ 늘어남 1.028) = 약 0.196
	const V016_TOP_RANGE := 0.07 + 0.35 * (0.28 + 0.08) * Runner.BODY_HEIGHT
	var runner := _make_runner()
	var lo := INF
	var hi := -INF
	for s in _simulate_run(runner, 3.0):
		lo = minf(lo, s.y)
		hi = maxf(hi, s.y)
	assert_true(hi - lo > 0.02, "박자가 눌림으로 보임 %f" % (hi - lo))
	assert_true(hi - lo <= V016_TOP_RANGE, "정수리 위아래 폭 %f <= %f" % [hi - lo, V016_TOP_RANGE])
	runner.queue_free()


func test_점프만_땅에서_뜸() -> void:
	var runner := _make_runner()
	runner.lift = 0.8
	runner._animate()
	assert_true(absf(runner._body.position.y - 0.8) < 0.0001, "점프 높이만큼 뜸 %f" % runner._body.position.y)
	runner.queue_free()


func test_접촉_그림자는_눌릴_때_넓어지고_늘어날_때_좁아짐() -> void:
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


func test_레인_이동_출렁임_값은_v0_2_1과_같음() -> void:
	# 사용자가 적당하다고 확인한 값 (2026-11-08). 바꾸려면 사용자 확인 뒤 이 테스트도 함께 고친다
	assert_eq(Runner.MOVE_TIME, 0.18, "레인 이동 시간")
	assert_eq(Runner.WOBBLE_GAIN, 0.45, "출렁임 세기")
	assert_eq(Runner.WOBBLE_MAX, 0.2, "출렁임 최대")
	assert_eq(Runner.WOBBLE_STIFF, 1000.0, "출렁임 스프링 세기")
	assert_eq(Runner.WOBBLE_DAMP, 15.0, "출렁임 감쇠")


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

