extends TestCase
## 음악 단계가 오를 때의 난간·대시 빛남 계산 (화면 없이).


func test_단계_빛남은_평소보다_밝고_상한을_넘지_않음() -> void:
	assert_eq(StageLight.energy(1.0, 0.0), 1.0, "평소 그대로")
	assert_true(is_equal_approx(StageLight.energy(1.0, 1.0), 1.0 + StageLight.STAGE_BOOST), "가장 밝을 때")
	assert_true(is_equal_approx(StageLight.energy(1.0, 0.5), 1.0 + StageLight.STAGE_BOOST * 0.5), "빛이 줄어드는 중")
	assert_eq(StageLight.energy(1.4, 1.0), StageLight.PEAK_MAX, "상한")
	assert_true(StageLight.PEAK_MAX > StageLight.ROAD_PEAK)
