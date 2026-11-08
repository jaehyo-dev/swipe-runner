extends TestCase
## 음악 시간 계산 테스트.

const DT := 1.0 / 60.0


func test_박자_수치() -> void:
	assert_true(is_equal_approx(BeatClock.BEAT, 0.6))
	assert_true(is_equal_approx(BeatClock.BAR, 2.4))
	assert_true(is_equal_approx(BeatClock.LOOP, 38.4))
	assert_true(is_equal_approx(RunLogic.SPEED * BeatClock.BEAT, 5.4), "속도 9: 한 박에 5.4")


func test_프레임_시간이_달라도_재생_위치만_따름() -> void:
	var clock := BeatClock.new()
	clock.update(1.0, 100.0)
	assert_eq(clock.time, 1.0)
	clock.update(1.5, 0.0)
	assert_eq(clock.time, 1.5)


func test_반복_지점을_4번_넘어도_이어짐() -> void:
	var clock := BeatClock.new()
	var heard := 0.0
	for frame in int(180.0 / DT):
		heard += DT
		var t := clock.update(fposmod(heard, BeatClock.LOOP), DT)
		assert_true(absf(t - heard) < 0.000001, "%f / %f" % [t, heard])
	assert_true(clock.time > BeatClock.LOOP * 4.0)


func test_지연_보정으로_위치가_음수여도_반복_지점에서_이어짐() -> void:
	var clock := BeatClock.new()
	clock.update(-0.05, DT)
	clock.update(BeatClock.LOOP - 0.06, DT)
	assert_true(is_equal_approx(clock.update(-0.05, DT), BeatClock.LOOP - 0.05), "반복 뒤 위치 -0.05")


func test_읽은_값이_살짝_뒤로_가도_시간은_되돌리지_않음() -> void:
	var clock := BeatClock.new()
	clock.update(5.0, DT)
	assert_eq(clock.update(4.99, DT), 5.0)
	assert_eq(clock.update(5.01, DT), 5.01)


func test_재생_위치가_멈추면_프레임_시간으로_이어_가고_돌아오면_다시_맞춤() -> void:
	var clock := BeatClock.new()
	clock.update(2.0, DT)
	for i in 60:  # 1초 동안 위치가 그대로
		clock.update(2.0, DT)
	assert_true(clock.time > 2.5, "게임이 멈추지 않음 %f" % clock.time)
	var before := clock.time
	var after := clock.update(2.1, DT)
	assert_true(after >= before, "오디오가 돌아와도 시간은 되돌아가지 않음 %f → %f" % [before, after])
	assert_true(after - before < BeatClock.BEAT, "한 박 안에서 맞춤 %f" % (after - before))
	var beats := (after - 2.1) / BeatClock.BEAT
	assert_true(absf(beats - roundf(beats)) < 0.000001, "박 격자 유지 %f" % beats)
	assert_true(is_equal_approx(clock.update(2.2, DT), after + 0.1), "그 뒤로는 재생 위치를 따름")


func test_가렸던_탭에서_돌아와_위치가_건너뛰어도_시간이_되돌아가지_않음() -> void:
	var clock := BeatClock.new()
	clock.update(10.0, DT)
	assert_true(is_equal_approx(clock.update(1.6, DT), BeatClock.LOOP + 1.6), "한 바퀴 넘게 지남")
