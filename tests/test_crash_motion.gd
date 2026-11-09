extends TestCase
## 충돌 시간표와 붙을 자리 계산 테스트.

const Kind := ObstacleField.Kind


func test_시간표는_느려짐_찰싹_붙음_흘러내림_순서() -> void:
	assert_eq(CrashMotion.stick(0.0), 0.0)
	assert_true(CrashMotion.stick(CrashMotion.SLOW_TIME - 0.001) < 0.36, "느려지는 동안엔 조금만")
	var snapped := CrashMotion.SLOW_TIME + CrashMotion.SNAP_TIME
	assert_true(absf(CrashMotion.stick(snapped) - 1.0) < 0.001, "찰싹 붙음")
	assert_eq(CrashMotion.stick(5.0), CrashMotion.stick(snapped), "그 뒤 그대로")
	assert_true(snapped < CrashMotion.FLOW_START, "붙은 뒤 흘러내림")
	assert_eq(CrashMotion.flow(CrashMotion.FLOW_START), 0.0)
	assert_eq(CrashMotion.flow(CrashMotion.FLOW_END), 1.0)


func test_느려지는_이동은_프레임을_어떻게_나눠도_같음() -> void:
	var total_for := func(dt: float) -> float:
		var t := 0.0
		var total := 0.0
		while t < 1.0:
			total += CrashMotion.slow_delta(t, dt)
			t += dt
		return total
	var expected := CrashMotion.SLOW_TIME * CrashMotion.SLOW_SCALE
	for dt: float in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0, 0.5]:
		assert_true(absf(total_for.call(dt) - expected) < 0.0001, "dt %f" % dt)


func test_화면_흔들림은_찰싹_순간_짧고_작게_한_번() -> void:
	assert_eq(CrashMotion.shake(0.0), Vector2.ZERO, "느려지는 동안엔 없음")
	assert_eq(CrashMotion.shake(CrashMotion.SLOW_TIME + CrashMotion.SHAKE_TIME), Vector2.ZERO, "끝남")
	assert_true(CrashMotion.SHAKE_TIME <= 0.2)
	var t := CrashMotion.SLOW_TIME
	var biggest := 0.0
	while t < CrashMotion.SLOW_TIME + CrashMotion.SHAKE_TIME:
		biggest = maxf(biggest, CrashMotion.shake(t).length())
		t += 0.005
	assert_true(biggest > 0.01 and biggest < 0.07, "크기 %f" % biggest)


func test_앞으로_달리다_부딪히면_세_종류_모두_앞면() -> void:
	for kind: Kind in [Kind.BLOCK, Kind.LOW, Kind.HIGH]:
		var c := CrashMotion.contact(kind, 0.0, 0.0, -0.6, 0.0)
		assert_eq(c["normal"], Vector3(0, 0, 1), "종류 %d" % kind)
	assert_true(absf(CrashMotion.contact(Kind.BLOCK, 0.0, 0.0, -0.6, 0.0)["face"] - (-0.05)) < 0.001)
	assert_true(absf(CrashMotion.contact(Kind.LOW, 0.0, 0.0, -0.6, 0.0)["face"] - (-0.35)) < 0.001)


func test_부딪힌_높이에_붙음() -> void:
	assert_eq(CrashMotion.BODY_MIDDLE, Runner.BODY_HEIGHT * 0.5, "몸 가운데 높이")
	assert_eq(CrashMotion.BODY_REACH, Runner.BODY_RADIUS, "몸 반폭")
	assert_eq(CrashMotion.contact(Kind.BLOCK, 0.0, 0.0, -0.6, 0.0)["y"], 0.4, "블록: 몸 가운데")
	assert_eq(CrashMotion.contact(Kind.LOW, 0.0, 0.0, -0.6, 0.0)["y"], 0.4, "허들: 몸 가운데")
	assert_eq(CrashMotion.contact(Kind.HIGH, 0.0, 0.0, -0.6, 0.0)["y"], ObstacleField.HIGH_BOTTOM, "막대: 몸이 낮아도 막대 높이")
	assert_eq(CrashMotion.contact(Kind.HIGH, 0.0, 0.0, -0.6, 1.6)["y"], ObstacleField.HIGH_TOP, "막대 위쪽을 넘어도 막대 안")
	assert_eq(CrashMotion.contact(Kind.BLOCK, 0.0, 0.0, -0.6, 1.0)["y"], 1.4, "기둥은 키가 커서 뛰던 높이에 그대로 붙음")
	assert_true(CrashMotion.contact(Kind.BLOCK, 0.0, 0.0, -0.6, PlayerAction.JUMP_HEIGHT)["y"] <= ObstacleField.BLOCK_HEIGHT, "기둥 높이 안")


func test_레인_이동_중_옆에서_부딪히면_옆면() -> void:
	var c := CrashMotion.contact(Kind.BLOCK, 1.5, 0.85, 0.2, 0.0)
	assert_eq(c["normal"], Vector3(-1, 0, 0), "왼쪽에서 오면 왼쪽 면")
	assert_true(absf(c["face"] - 0.95) < 0.001)
	assert_eq(c["along"], 0.0, "면 안쪽이면 앞뒤 위치 그대로")
	var r := CrashMotion.contact(Kind.BLOCK, -1.5, -0.85, 0.2, 0.0)
	assert_eq(r["normal"], Vector3(1, 0, 0), "오른쪽에서 오면 오른쪽 면")


func test_이미_지나간_허들에_걸리면_뒷면() -> void:
	var c := CrashMotion.contact(Kind.LOW, 0.0, 0.0, 0.4, 0.3)
	assert_eq(c["normal"], Vector3(0, 0, -1))
	assert_true(absf(c["face"] - 0.15) < 0.001)
