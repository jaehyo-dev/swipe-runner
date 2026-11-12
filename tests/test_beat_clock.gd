extends TestCase
## 음악 시간 계산 테스트.

const DT := 1.0 / 60.0


func test_프레임_시간이_달라도_재생_위치만_따름() -> void:
	var clock := BeatClock.new()
	clock.update(1.0, 100.0)
	assert_eq(clock.time, 1.0)
	clock.update(1.5, 0.0)
	assert_eq(clock.time, 1.5)


## 재생 위치는 오디오 블록(여기서는 10ms)마다 계단처럼 오른다. 화면 시간은 프레임마다 고르게 흘러야 세상이 떨리지 않는다
func _steps_with_blocks(frame: float) -> Array[float]:
	var clock := BeatClock.new()
	var t := 0.0
	var last := 0.0
	var steps: Array[float] = []
	for i in 600:
		t += frame
		clock.update(floorf(t * 100.0) / 100.0, frame)
		var now := clock.smoothed(frame)
		assert_true(now >= last, "되돌아가지 않음")
		assert_true(absf(now - t) < 0.02, "실제 시간과 벌어지지 않음 %f" % (now - t))
		if i > 60:
			steps.append(absf(now - last - frame))
		last = now
	return steps


func test_블록_단위_재생_위치도_60Hz와_120Hz에서_고르게_흐름() -> void:
	for frame in [1.0 / 60.0, 1.0 / 120.0]:
		var worst := 0.0
		for step in _steps_with_blocks(frame):
			worst = maxf(worst, step)
		assert_true(worst < 0.002, "프레임 %f: 들쭉날쭉 %f초" % [frame, worst])


## 아이폰 WebKit 흉내: 재생 위치가 큰 계단(stair초)으로 오르고, 가끔 지연 값이 바뀌어 20ms 뒤로 간다(back). 프레임 간격도 ±1ms 흔들린다.
## 결과 {stalls: 세상이 거의 안 움직인 프레임 수(이동 < 프레임 시간의 절반), worst: 프레임마다 이동량이 프레임 시간과 다른 가장 큰 비율}
static func webkit_motion(frame: float, stair: float, back: bool, frames := 1200) -> Dictionary:
	var clock := BeatClock.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t := 0.0
	var last := 0.0
	var stalls := 0
	var worst := 0.0
	for i in frames:
		var dt := frame + rng.randf_range(-0.001, 0.001)
		t += dt
		var raw := floorf(t / stair) * stair - (0.02 if back and (i / 300) % 2 == 1 else 0.0)
		clock.update(raw, dt)
		var now := clock.smoothed(dt)
		if i > 120:  # 첫 소리 맞춤 뒤
			var moved := now - last
			if moved < dt * 0.5:
				stalls += 1
			worst = maxf(worst, absf(moved - dt) / dt)
		last = now
	return {"stalls": stalls, "worst": worst}


func test_WebKit처럼_큰_계단과_되돌림에도_멈춤_없이_고르게() -> void:
	for frame in [1.0 / 60.0, 1.0 / 120.0]:
		for stair in [0.010, 0.0213, 0.0427]:
			for back in [false, true]:
				var r := webkit_motion(frame, stair, back)
				var name := "%dHz 계단 %.1fms%s" % [roundi(1.0 / frame), stair * 1000.0, " 되돌림" if back else ""]
				assert_eq(r["stalls"], 0, name + " 멈춘 프레임")
				assert_true(r["worst"] <= 0.08, "%s 이동량 흔들림 %.1f%%" % [name, r["worst"] * 100.0])


func test_크게_벌어지면_바로_맞춤() -> void:
	var clock := BeatClock.new()
	clock.update(1.0, DT)
	clock.smoothed(DT)
	clock.update(2.0, DT)
	assert_eq(clock.smoothed(DT), 2.0, "긴 프레임 뒤")


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
	assert_true(after - before < 0.6, "한 박 안에서 맞춤 %f" % (after - before))
	var beats := (after - 2.1) / 0.6
	assert_true(absf(beats - roundf(beats)) < 0.000001, "박 격자 유지 %f" % beats)
	assert_true(is_equal_approx(clock.update(2.2, DT), after + 0.1), "그 뒤로는 재생 위치를 따름")


func test_가렸던_탭에서_돌아와_위치가_건너뛰면_그_자리로_감() -> void:
	var clock := BeatClock.new()
	clock.update(10.0, DT)
	assert_true(is_equal_approx(clock.update(40.0, DT), 40.0))


func test_멈춘_재생_위치의_읽기_오차를_오디오가_돌아온_것으로_착각하지_않음() -> void:
	# v0.3.0 웹: 위치가 멈춘 동안 1~2ms 흔들림을 복귀로 읽어 세상이 한 박씩 순간 이동했다
	var clock := BeatClock.new()
	var last := 0.0
	var t := 0.0
	for i in 60:  # 1초
		t = clock.update(0.002 + 0.001 * (i % 2), 1.0 / 60.0)
		assert_true(t - last < 0.03, "%d프레임: %f에서 %f로 튐" % [i, last, t])
		last = t


func test_첫_소리는_1초까지_기다리고_그_안에_나오면_순간_이동_없음() -> void:
	var clock := BeatClock.new()
	for i in 30:  # 0.5초 동안 오디오가 켜지는 중
		assert_eq(clock.update(-0.04, DT), 0.0, "기다리는 동안 세상은 출발하지 않음")
	var t := clock.update(0.0, DT)
	assert_true(t <= DT, "소리와 함께 0초에서 출발 %f" % t)


func test_첫_소리가_1초_넘게_안_나면_소리_없이도_출발() -> void:
	var clock := BeatClock.new()
	var t := 0.0
	for i in 90:
		t = clock.update(-0.04, DT)
	assert_true(t > 0.4, "프레임 시간으로 출발 %f" % t)


func test_240Hz에서도_오디오가_돌아온_것을_알아챔() -> void:
	# 프레임마다 4.17ms씩 늘어 READ_NOISE보다 작아도 멈춘 자리에서 쌓인 양으로 알아챈다
	var clock := BeatClock.new()
	var dt := 1.0 / 240.0
	clock.update(2.0, dt)
	for i in 240:  # 1초 멈춤
		clock.update(2.0, dt)
	var position := 2.0
	for i in 12:
		position += dt
		clock.update(position, dt)
	var beats := (clock.time - position) / 0.6
	assert_true(absf(beats - roundf(beats)) < 0.000001, "다시 재생 위치를 따름 %f" % beats)


func test_일시정지를_풀면_소리가_다시_흐를_때까지_앞서_나가지_않음() -> void:
	var clock := BeatClock.new()
	var t := 0.0
	for i in 60:  # 1초 동안 정상 재생
		t += 1.0 / 60.0
		clock.update(t, 1.0 / 60.0)
		clock.smoothed(1.0 / 60.0)
	var paused_at := clock.smooth
	clock.rehear()
	for i in 3:  # 다시 켰지만 소리가 아직 흐르지 않는 3프레임
		clock.update(t, 1.0 / 60.0)
		assert_eq(clock.smoothed(1.0 / 60.0), paused_at, "%d프레임: 소리를 기다린다" % i)
	t += 0.01
	clock.update(t, 1.0 / 60.0)
	assert_true(absf(clock.smoothed(1.0 / 60.0) - t) < 0.008, "소리가 흐르면 그 자리 근처 (한 프레임 안)")
