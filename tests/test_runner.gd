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
	# 몸통 한 덩어리: 달린 메시는 몸·그림자 + 착지 때만 보이는 물방울
	assert_eq(runner.get_child_count(), 2 + Runner.DROPLET_COUNT, "러너 자식: 몸 + 그림자 + 물방울")
	for d in runner._drops:
		assert_true(not d.visible, "달리는 동안 물방울 숨김")
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



func test_몸_크기는_폭_약_1_0_키_약_0_8() -> void:
	var box := Runner.build_body_mesh().get_aabb()
	assert_true(absf(box.size.x - 1.0) < 0.03, "폭 %f" % box.size.x)
	assert_true(absf(box.size.y - 0.8) < 0.01, "키 %f" % box.size.y)


## 실제 게임처럼 PlayerAction과 주인공을 60fps로 진행한다. actions = {프레임: "jump"/"slide"}.
## 프레임마다 {y: 몸 키 배율, x: 옆 배율, z: 앞뒤 배율, bottom: 몸 바닥 높이, lift, ducking, stretch} 를 모은다.
func _simulate_actions(runner: Runner, actions: Dictionary, frames: int, move_x := {}) -> Array[Dictionary]:
	var player := PlayerAction.new()
	var dt := 1.0 / 60.0
	var out: Array[Dictionary] = []
	for f in frames:
		if actions.get(f) == "jump":
			player.jump()
		elif actions.get(f) == "slide":
			player.slide()
		if move_x.has(f):
			runner.position.x = move_x[f]
		player.step(dt)
		runner.lift = player.height()
		runner.crouch = player.crouch()
		runner._process(dt)
		var s := runner._body.scale
		out.append({"y": s.y, "x": s.x, "z": s.z, "bottom": runner._body.position.y, "lift": runner.lift,
			"ducking": player.is_ducking(), "stretch": runner._stretch, "pz": runner._body.position.z, "sag": runner.sag()})
	return out


func _jump_runner() -> Runner:
	var runner := _make_runner()
	runner.running = false  # 달리기 박자 눌림을 멈춰 점프 모양만 본다
	runner.set_phase(PI / 2.0)
	return runner


func test_점프는_입력_첫_프레임부터_늘어나며_뜨고_옆은_좁아짐() -> void:
	var runner := _jump_runner()
	var base: float = runner._body.scale.y
	var base_x: float = runner._body.scale.x
	var frames := _simulate_actions(runner, {0: "jump"}, 8)
	assert_true(frames[0]["lift"] > 0.0, "첫 프레임부터 뜸 %f" % frames[0]["lift"])
	assert_true(frames[0]["y"] / base > 1.12, "첫 프레임부터 늘어남 %f (예비 동작으로 늦추지 않음)" % (frames[0]["y"] / base))
	var peak := 0.0
	var peak_f := 0
	for i in frames.size():
		if frames[i]["y"] / base > peak:
			peak = frames[i]["y"] / base
			peak_f = i
	assert_true(peak > 1.35 and peak < 1.55, "늘어남 %f" % peak)
	assert_true(peak_f <= 4, "늘어남이 바로 옴 (프레임 %d)" % peak_f)
	assert_true(frames[peak_f]["x"] < base_x * 0.88, "옆은 좁아짐 %f" % frames[peak_f]["x"])
	runner.queue_free()


## 실제 main 장면에서 점프하고 공중 프레임마다 게임 카메라로 본 화면 키/폭을 모은다.
## chain_at >= 0이면 착지 뒤 그 프레임에 한 번 더 점프하고 두 번째 공중만 모은다.
func _air_aspects(chain_at := -1) -> Array[float]:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 136
	add_child(main)
	main.set_process(false)
	await wait_frames()
	main.runner.running = false  # 달리기 박자를 멈춰 점프 모양만 본다
	main.apply_swipe(SwipeDetector.Dir.UP)
	var air: Array[float] = []
	var land := -1
	for f in 200:  # 점프는 0.6초(36프레임): 착지하지 못해도 테스트가 멈추지 않게 상한을 둔다
		if land >= 0 and f == land + chain_at:
			main.apply_swipe(SwipeDetector.Dir.UP)
		var was_air: bool = main.runner.lift > 0.0
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
		if main.runner.lift > 0.0:
			if chain_at < 0 or land >= 0:
				air.append(main.runner.screen_aspect(main._camera))
		elif was_air:
			if chain_at < 0 or land >= 0:
				break
			land = f
	main.queue_free()
	return air


func test_공중_키폭은_속도에_비례해_뛸때와_떨어질때_약_1_4_꼭대기_약_1_0() -> void:
	# 실제 게임 카메라로 본 키/폭 (ART_BIBLE.md 2-4 공중 비율, 2-5 원칙 1). 공중 내내 1.0 이상
	var air: Array[float] = await _air_aspects()
	assert_true(air.size() >= 30, "공중 프레임 수 %d" % air.size())
	for i in air.size():
		assert_true(air[i] >= 1.0, "공중 %d프레임 키/폭 %f" % [i, air[i]])
	var takeoff: float = air.slice(0, 8).max()
	assert_true(takeoff > 1.35 and takeoff < 1.5, "뛰는 순간 %f" % takeoff)
	var apex: float = air.slice(air.size() / 2 - 3, air.size() / 2 + 3).min()
	assert_true(apex >= 1.0 and apex < 1.1, "꼭대기 동그라미 %f" % apex)
	assert_true(air[-1] > 1.3 and air[-1] < 1.5, "떨어질 때 %f" % air[-1])
	# 속도 비례: 꼭대기를 지나면(스프링이 따라오는 2~3프레임 뒤부터) 떨어지는 동안 계속 길어진다 (꼭대기에서 납작해지는 출렁임 없음)
	for i in range(air.size() / 2 + 5, air.size()):
		assert_true(air[i] >= air[i - 1], "떨어지며 길어짐 %d: %f -> %f" % [i, air[i - 1], air[i]])


## 한 번 점프하고 착지한 프레임 번호
func _land_frame(frames: Array[Dictionary]) -> int:
	var land := 0
	while frames[land]["lift"] > 0.0:
		land += 1
	return land


func test_착지는_반구를_거쳐_팬케이크_약_0_25배로_눌린_뒤_튕겨_1에서_2번_출렁() -> void:
	var runner := _jump_runner()
	var frames := _simulate_actions(runner, {0: "jump"}, 120)
	var land := _land_frame(frames)
	var low := INF
	var low_f := 0
	for i in range(land, land + 15):
		if 1.0 + frames[i]["stretch"] < low:
			low = 1.0 + frames[i]["stretch"]
			low_f = i
	assert_true(low > 0.2 and low < 0.3, "팬케이크 키 배율 %f" % low)
	assert_true(low_f - land >= 4, "단계적으로 깊어짐: 팬케이크는 닿고 %d프레임 뒤" % (low_f - land))
	# 닿는 순간은 아직 동그라미에 가깝고(키 0.85배 이상), 그다음 넓은 반구(0.4~0.75배)를 거친다
	assert_true(1.0 + frames[land]["stretch"] > 0.85, "닿는 순간 %f" % (1.0 + frames[land]["stretch"]))
	var hemi := false
	for i in range(land, low_f):
		hemi = hemi or (1.0 + frames[i]["stretch"] > 0.4 and 1.0 + frames[i]["stretch"] < 0.75)
	assert_true(hemi, "넓은 반구 단계")
	assert_true(frames[low_f]["x"] > 1.35 and frames[low_f]["x"] <= Runner.BODY_WIDTH_LIMIT, "팬케이크 옆 퍼짐 %f" % frames[low_f]["x"])
	# 튕긴 뒤 눈에 띄는 출렁임(키 배율 1.5% 이상인 꺾임) 1~2번
	var swings := 0
	for i in range(low_f + 1, frames.size() - 1):
		var a: float = frames[i]["stretch"] - frames[i - 1]["stretch"]
		var b: float = frames[i + 1]["stretch"] - frames[i]["stretch"]
		if a * b < 0.0 and absf(frames[i]["stretch"]) >= 0.015:
			swings += 1
	assert_true(swings >= 1 and swings <= 2, "착지 출렁임 횟수 %d" % swings)
	for i in range(land, frames.size()):
		assert_eq(frames[i]["bottom"], 0.0, "착지 뒤 몸 바닥은 땅")
	runner.queue_free()


func test_착지_뒤_0_5초_안에_원래_모양으로_돌아옴() -> void:
	var runner := _jump_runner()
	var frames := _simulate_actions(runner, {0: "jump"}, 120)
	var land := _land_frame(frames)
	for i in range(land + 30, frames.size()):  # 착지 + 0.5초부터
		assert_true(absf(frames[i]["stretch"]) < 0.03, "%.2f초에 아직 출렁임 %f" % [(i - land) / 60.0, frames[i]["stretch"]])
	runner.queue_free()


func test_착지하면_물방울이_튀었다가_합쳐지고_사라짐() -> void:
	var runner := _jump_runner()
	_simulate_actions(runner, {0: "jump"}, 37)  # 36프레임째 착지
	assert_true(runner._drops.size() >= 2 and runner._drops.size() <= 4, "물방울 %d개" % runner._drops.size())
	var top := 0.0
	for f in 30:
		runner._process(1.0 / 60.0)
		for d in runner._drops:
			if d.visible:
				top = maxf(top, d.position.y)
				assert_true(d.scale.x <= 1.0, "물방울은 작게")
	assert_true(top > 0.2, "위로 튀어 오름 %f" % top)
	runner._process(0.2)
	for d in runner._drops:
		assert_true(not d.visible, "착지 0.5초 뒤에는 몸에 합쳐져 없음")
	runner.queue_free()


## 프레임 사이 키 배율 변화의 최댓값
func _max_step(frames: Array[Dictionary], from: int, to: int) -> float:
	var m := 0.0
	for i in range(maxi(from, 1), mini(to, frames.size())):
		m = maxf(m, absf(frames[i]["y"] - frames[i - 1]["y"]))
	return m


func test_팬케이크_중_점프는_첫_프레임에_쭉_솟음() -> void:
	var single := _simulate_actions(_jump_runner(), {0: "jump"}, 60)
	var land := _land_frame(single)
	for at in [land + 3, land + 5, land + 9]:  # 반구 · 팬케이크 · 튕기는 중
		var chain := _simulate_actions(_jump_runner(), {0: "jump", at: "jump"}, at + 40)
		assert_true(chain[at]["lift"] > 0.0, "입력 프레임에 바로 뜸 (%d)" % at)
		assert_true(chain[at]["y"] - chain[at - 1]["y"] > 0.2, "첫 프레임에 쭉 솟음 %f -> %f" % [chain[at - 1]["y"], chain[at]["y"]])
		# 한 프레임에 다 펴지지 않음(툭 튀지 않음): 한 프레임 키 변화는 몸 키 배율 0.45 이하, 2~3프레임에 걸쳐 솟는다
		assert_true(_max_step(chain, at, chain.size()) <= 0.45, "프레임 변화 %f" % _max_step(chain, at, chain.size()))


func test_팬케이크_중_재점프도_세번째_공중_프레임부터_키폭_1_0_이상() -> void:
	# 팬케이크(키 0.25배)에서 솟아오르는 처음 2프레임(0.03초)만 1.0 아래를 지나간다
	var air: Array[float] = await _air_aspects(5)
	assert_true(air.size() >= 30, "공중 프레임 수 %d" % air.size())
	assert_true(air[0] < air[1] and air[1] < air[2], "솟아오름 %f %f %f" % [air[0], air[1], air[2]])
	for i in range(2, air.size()):
		assert_true(air[i] >= 1.0, "두 번째 공중 %d프레임 키/폭 %f" % [i, air[i]])


func test_팬케이크_중에도_레인_이동이_바로_됨() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 136
	add_child(main)
	main.set_process(false)
	await wait_frames()
	main.apply_swipe(SwipeDetector.Dir.UP)
	for f in 40:  # 착지(36프레임) + 4프레임: 팬케이크로 눌리는 중
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
	assert_true(main.runner._stretch < -0.5, "팬케이크 중 %f" % main.runner._stretch)
	var x0: float = main.runner.position.x
	main.apply_swipe(SwipeDetector.Dir.RIGHT)
	assert_eq(main.lane, 2, "입력 즉시 레인 바뀜")
	await wait_frames(3)
	assert_true(main.runner.position.x > x0, "몸이 바로 움직이기 시작 %f" % main.runner.position.x)
	main.queue_free()


func test_착지_출렁임_중_레인을_바꿔도_모양이_같음() -> void:
	var a := _simulate_actions(_jump_runner(), {0: "jump"}, 70)
	var moves := {}
	for f in range(38, 50):  # 착지 무렵 레인 이동
		moves[f] = RunLogic.LANE_WIDTH * (f - 37) / 12.0
	var b := _simulate_actions(_jump_runner(), {0: "jump"}, 70, moves)
	for i in a.size():
		assert_eq(b[i]["y"], a[i]["y"], "레인 이동은 몸 키에 영향 없음 (출렁임은 셰이더 기울기)")


func test_슬라이드는_옆으로_넓게_녹아_퍼지고_앞이_이끌고_뒤가_따라옴() -> void:
	var runner := _jump_runner()
	var frames := _simulate_actions(runner, {0: "slide"}, 26)
	var max_z := 0.0
	for f in frames:
		max_z = maxf(max_z, f["z"])
	var mid: Dictionary = frames[25]
	assert_true(absf(mid["z"] - Runner.SLIDE_STRETCH) < 0.05, "앞뒤 늘어남 %f" % mid["z"])
	assert_true(max_z > Runner.SLIDE_STRETCH + 0.03, "뒤가 따라오며 살짝 넘쳤다 돌아옴 %f" % max_z)
	assert_true(mid["x"] >= 1.4 and mid["x"] <= Runner.BODY_WIDTH_LIMIT, "뒤 카메라에서 보이게 옆으로 넓게 %f" % mid["x"])
	# 앞(-z)이 먼저 나가서 몸 중심이 앞쪽으로 쏠렸다가 뒤가 따라오면 돌아온다
	assert_true(frames[3]["pz"] < -0.03, "앞이 이끎 %f" % frames[3]["pz"])
	assert_true(absf(mid["pz"]) < 0.02, "뒤가 따라옴 %f" % mid["pz"])
	assert_true(runner._mat.get_shader_parameter("drag") > 0.0, "윗부분이 뒤로 끌림")
	runner.queue_free()


func test_넓게_퍼져도_옆_레인_장애물과_겹쳐_보이지_않음() -> void:
	# 옆 레인 장애물의 가장 안쪽 끝: 허들·막대(폭 1.3)가 레인 중심에서 0.85, 블록(1.1)은 0.95
	var gap := RunLogic.LANE_WIDTH - ObstacleField.BAR_WIDTH * 0.5
	var half := Runner.BODY_WIDTH_LIMIT * Runner.BODY_RADIUS * (1.0 + Runner.LAND_RIM_WAVE) + 0.006  # 테두리 물결·표면 물결까지
	assert_true(half < gap, "몸 반폭 %f < 옆 장애물 안쪽 %f" % [half, gap])
	var runner := _make_runner()  # 달리기 박자 눌림(옆으로 퍼짐)까지 켠다
	var frames := _simulate_actions(runner, {0: "jump", 40: "slide", 90: "jump"}, 160)
	for f in frames:
		assert_true(f["x"] <= Runner.BODY_WIDTH_LIMIT, "몸 폭 배율 %f" % f["x"])
	runner.queue_free()


func test_슬라이드_중_보이는_몸_높이는_판정_높이_이하() -> void:
	var runner := _make_runner()  # 달리기 박자도 그대로 켠다
	var ripple := 0.006  # jelly.gdshader 표면 물결 최대 높이
	var limit := PlayerAction.CROUCH_SCALE * Runner.BODY_HEIGHT
	var frames := _simulate_actions(runner, {5: "slide", 50: "slide", 70: "jump", 110: "slide"}, 160)
	var ducked := 0
	for f in frames:
		if f["ducking"]:
			ducked += 1
			var top: float = f["bottom"] + f["y"] * (Runner.BODY_HEIGHT + ripple + maxf(f["sag"], 0.0))  # 위아래 시차까지
			assert_true(top <= limit, "슬라이드 중 몸 높이 %f <= %f" % [top, limit])
	assert_true(ducked > 60, "슬라이드 프레임 수 %d" % ducked)
	runner.queue_free()


func test_슬라이드가_끝나면_위로_쭉_올라오며_출렁() -> void:
	var runner := _jump_runner()
	var base: float = runner._body.scale.y
	var frames := _simulate_actions(runner, {0: "slide"}, 80)
	var end := roundi(PlayerAction.SLIDE_TIME * 60.0)
	var peak := 0.0
	for i in range(end, frames.size()):
		peak = maxf(peak, frames[i]["y"] / base)
	assert_true(peak > 1.05, "끝날 때 위로 늘어남 %f" % peak)
	assert_true(absf(frames[-1]["y"] / base - 1.0) < 0.02, "결국 기본 모양 %f" % (frames[-1]["y"] / base))
	runner.queue_free()


func test_슬라이드_중_점프해도_모양이_튀지_않음() -> void:
	var frames := _simulate_actions(_jump_runner(), {0: "slide", 20: "jump"}, 60)
	var single := _simulate_actions(_jump_runner(), {0: "jump"}, 60)
	assert_true(_max_step(frames, 19, 60) <= _max_step(single, 0, 60) * 1.15, "슬라이드→점프 프레임 변화 %f" % _max_step(frames, 19, 60))


func test_공중에서는_바닥이_둥글고_착지하면_다시_평평하며_툭_튀지_않음() -> void:
	var runner := _jump_runner()
	var player := PlayerAction.new()
	var dt := 1.0 / 60.0
	var prev := runner._flat
	var max_air_step := 0.0
	var max_land_step := 0.0
	var air_min := 1.0
	var landed_at := -1
	player.jump()
	for f in 90:
		player.step(dt)
		var was_air := runner.lift > 0.0
		runner.lift = player.height()
		runner._process(dt)
		var step := absf(runner._flat - prev)
		prev = runner._flat
		if runner.lift > 0.0:
			max_air_step = maxf(max_air_step, step)
			air_min = minf(air_min, runner._flat)
			if f > 10:
				assert_eq(runner._flat, 0.0, "공중(0.17초 뒤)에서는 계속 둥근 바닥 (프레임 %d)" % f)
		else:
			if was_air:
				landed_at = f
			max_land_step = maxf(max_land_step, step)
	assert_eq(air_min, 0.0, "공중에서 완전히 둥글어짐")
	assert_true(landed_at > 0, "착지함")
	assert_eq(runner._flat, 1.0, "착지 뒤 다시 평평")
	assert_true(max_air_step <= dt / Runner.FLAT_CURL_TIME + 0.001, "말려 올라가는 한 프레임 변화 %f" % max_air_step)
	assert_true(max_land_step <= dt / Runner.FLAT_SPREAD_TIME + 0.001 and max_land_step < 0.5, "착지 한 프레임 변화 %f" % max_land_step)
	runner.queue_free()


func test_달리는_동안_바닥은_계속_평평() -> void:
	var runner := _make_runner()
	for i in 120:
		runner._process(1.0 / 60.0)
	assert_eq(runner._flat, 1.0)
	runner.queue_free()


func test_점프_그림자는_꼭대기에서_진하기_약_30퍼센트_크기_약_60퍼센트() -> void:
	var runner := _jump_runner()
	var ground_x: float = runner._shadow.scale.x / runner._body.scale.x
	assert_eq(runner._shadow_mat.get_shader_parameter("opacity"), 1.0, "땅에서는 그대로 진함")
	runner.lift = PlayerAction.JUMP_HEIGHT
	runner._animate()
	var top_size: float = runner._shadow.scale.x / runner._body.scale.x / ground_x
	var top_opacity: float = runner._shadow_mat.get_shader_parameter("opacity")
	assert_true(absf(top_opacity - 0.3) < 0.01, "꼭대기 진하기 %f" % top_opacity)
	assert_true(absf(top_size - 0.6) < 0.01, "꼭대기 크기 %f" % top_size)
	runner.lift = PlayerAction.JUMP_HEIGHT * 0.5
	runner._animate()
	var mid: float = runner._shadow_mat.get_shader_parameter("opacity")
	assert_true(mid > top_opacity and mid < 1.0, "중간 높이는 그 사이 %f" % mid)
	runner.lift = 0.0
	runner._animate()
	assert_eq(runner._shadow_mat.get_shader_parameter("opacity"), 1.0, "착지하면 다시 진함")
	runner.queue_free()


## 공중 프레임마다 몸 모양을 모은다: {flat, shape(body_shape)}. 달리기 박자는 켠 실제 게임 상태
func _air_shapes() -> Array[Dictionary]:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 136
	add_child(main)
	main.set_process(false)
	await wait_frames()
	main.apply_swipe(SwipeDetector.Dir.UP)
	var air: Array[Dictionary] = []
	for f in 200:
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
		if main.runner.lift <= 0.0:
			break
		air.append({"flat": main.runner._flat, "shape": main.runner.body_shape()})
	main.queue_free()
	return air


func test_공중에서_아래_둥근_깊이는_위_돔의_0_9배_이상이고_가장_넓은_곳은_45에서_50퍼센트() -> void:
	# ART_BIBLE.md 2-4 계란형. 바닥이 둥글게 말리는 시간(FLAT_CURL_TIME) 뒤 공중 모든 프레임, 위아래 시차까지 포함
	var air: Array[Dictionary] = await _air_shapes()
	assert_true(air.size() >= 30, "공중 프레임 수 %d" % air.size())
	var checked := 0
	for a in air:
		if a["flat"] > 0.0:
			continue
		checked += 1
		assert_true(a["shape"].y >= 0.9, "아래 깊이/위 돔 %f" % a["shape"].y)
		assert_true(a["shape"].x >= 0.45 and a["shape"].x <= 0.5, "가장 넓은 높이 %f" % a["shape"].x)
	assert_true(checked >= 25, "둥글어진 공중 프레임 수 %d" % checked)
	assert_true(air[air.size() / 2]["flat"] == 0.0, "꼭대기에서는 다 둥글어짐")


func test_시차가_가장_클_때도_아래_둥근_깊이는_위_돔의_0_9배_이상() -> void:
	var runner := Runner.new()
	add_child(runner)
	runner._flat = 0.0
	assert_true(absf(runner.body_shape().y - Runner.AIR_LOWER_DEPTH) < 1e-6, "시차 없을 때 %f" % runner.body_shape().y)
	runner._sag = Runner.SAG_MAX / Runner.SAG_GAIN  # 윗부분이 가장 위로 밀림 = 위 돔이 가장 길다
	assert_true(runner.body_shape().y >= 0.9, "최대 시차 %f" % runner.body_shape().y)
	runner.queue_free()


func test_땅_위_모양은_v0_2_6과_같음() -> void:
	# v0.2.6 _blob_point 식을 그대로 옮겨 비교: 가장 넓은 곳 37.5%, 평평한 바닥 80%
	for i in 257:
		var t := i / 256.0
		var c := 1.0 - minf(t / 0.375, 1.0)
		var expected := 0.8 + 0.2 * sqrt(1.0 - c * c)
		if t > 0.375:
			var u := (t - 0.375) / 0.625
			expected = sqrt(1.0 - u * u)
		assert_true(absf(Runner._profile(t, 1.0) - expected) < 1e-6, "t=%f: %f != %f" % [t, Runner._profile(t, 1.0), expected])
		assert_true(absf(Runner._blob_point(t, 0.0).x - expected * Runner.BODY_RADIUS) < 1e-6, "메시 t=%f" % t)
	var runner := Runner.new()
	add_child(runner)
	assert_true(absf(runner.body_shape().x - 0.375) < 1e-6, "땅 위 가장 넓은 높이 %f" % runner.body_shape().x)
	assert_true(runner._mat.get_shader_parameter("air_widest_t") == Runner.AIR_WIDEST_T, "셰이더에 공중 값 전달")
	runner.queue_free()


func test_공중_모양은_뜰때와_착지할때_툭_튀지_않음() -> void:
	# 프로필 전체(높이별 반지름)가 프레임마다 조금씩만 바뀐다: 뜰 때 0.1초, 착지 0.05초에 걸친 flat 변화
	var runner := Runner.new()
	add_child(runner)
	for air in [true, false]:
		runner.lift = 1.0 if air else 0.0
		var prev := smoothstep(0.0, 1.0, runner._flat)
		for f in 12:
			runner.step_shape(1.0 / 60.0)
			var now := smoothstep(0.0, 1.0, runner._flat)
			for i in 65:
				var d := absf(Runner._profile(i / 64.0, now) - Runner._profile(i / 64.0, prev))
				# 맨 아래·맨 위 끝은 √ 곡선이라 원래 빠르게 바뀌므로 몸통(높이 10~90%)만 본다
				if i >= 7 and i <= 57:
					assert_true(d < 0.2, "%s %d프레임 t=%f 변화 %f" % ["뜰 때" if air else "착지", f, i / 64.0, d])
			prev = now
	runner.queue_free()


# ---------- 공중 아래 스와이프 모양 ----------

func test_공중_아래_스와이프는_아래로_늘어나고_팬케이크_없이_슬라이드() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 136
	add_child(main)
	main.set_process(false)
	await wait_frames()
	main.runner.set_process(false)
	main.runner.running = false
	main.apply_swipe(SwipeDetector.Dir.UP)
	for i in 18:  # 꼭대기까지
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
	main.apply_swipe(SwipeDetector.Dir.DOWN)
	var peak := 0.0
	var natural_max := 1.47  # 보통 점프 키 배율 상한 근처
	while main.player.is_dropping():
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
		peak = maxf(peak, main.runner._body.scale.y)
	assert_true(peak > natural_max, "보통 점프보다 더 쭉 늘어남 %f" % peak)
	assert_true(main.player.is_sliding(), "닿자마자 슬라이드")
	assert_eq(main.runner._land_t, -1.0, "팬케이크 건너뜀")
	var body: MeshInstance3D = main.runner._body
	for i in 6:  # 0.1초 안에 슬라이드 모양
		main.advance(1.0 / 60.0)
		main.runner._process(1.0 / 60.0)
	assert_true(absf(body.scale.y - Runner.SLIDE_SQUASH) < 0.02, "녹아 흐르는 키 %f" % body.scale.y)
	assert_true(absf(body.scale.x - Runner.SLIDE_WIDEN) < 0.06, "옆으로 퍼짐 %f" % body.scale.x)
	assert_eq(main.runner._land_t, -1.0, "슬라이드 내내 팬케이크 없음")
	main.queue_free()
