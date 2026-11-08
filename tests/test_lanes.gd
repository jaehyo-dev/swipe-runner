extends TestCase
## 레인 이동 한계, 레인 좌표, 거리 계산 테스트.


func test_왼쪽_끝에서_더_왼쪽으로_가도_0() -> void:
	assert_eq(RunLogic.move_lane(0, -1), 0)


func test_오른쪽_끝에서_더_오른쪽으로_가도_2() -> void:
	assert_eq(RunLogic.move_lane(2, 1), 2)


func test_한_칸씩_이동() -> void:
	assert_eq(RunLogic.move_lane(1, -1), 0)
	assert_eq(RunLogic.move_lane(1, 1), 2)
	assert_eq(RunLogic.move_lane(0, 1), 1)


func test_아무리_많이_밀어도_0에서_2_사이() -> void:
	var lane := RunLogic.START_LANE
	for i in 10:
		lane = RunLogic.move_lane(lane, 1)
		assert_true(lane >= 0 and lane <= 2, "오른쪽 %d번째" % (i + 1))
	assert_eq(lane, 2)
	for i in 10:
		lane = RunLogic.move_lane(lane, -1)
		assert_true(lane >= 0 and lane <= 2, "왼쪽 %d번째" % (i + 1))
	assert_eq(lane, 0)


func test_이동량이_커도_한_칸만_이동() -> void:
	assert_eq(RunLogic.move_lane(0, 5), 1)


func test_레인_좌표는_가운데가_0이고_폭_1_5() -> void:
	assert_eq(RunLogic.lane_x(1), 0.0)
	assert_eq(RunLogic.lane_x(0), -1.5)
	assert_eq(RunLogic.lane_x(2), 1.5)


