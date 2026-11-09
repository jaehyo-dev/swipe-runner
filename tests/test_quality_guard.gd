extends TestCase
## 렉 줄이기 판단: 3D 해상도 상한, 프레임이 밀릴 때 단계 낮추기.

const FAST := 1.0 / 60.0


func _feed(guard: QualityGuard, frame: float, seconds: float) -> int:
	var raised := 0
	var t := 0.0
	while t < seconds:
		t += frame
		raised += 1 if guard.push(frame) else 0
	return raised


func test_작은_창은_그대로이고_큰_창은_상한까지만_그림() -> void:
	assert_eq(QualityGuard.render_scale(Vector2i(780, 1688)), 1.0, "휴대폰")
	assert_eq(QualityGuard.render_scale(Vector2i(1280, 800)), 1.0)
	var tall := QualityGuard.render_scale(Vector2i(1080, 2400))
	assert_true(absf(2400 * tall - 1920.0) < 0.01, "세로 상한 %f" % tall)
	var wide := QualityGuard.render_scale(Vector2i(3420, 2138))
	assert_true(3420 * wide * 2138 * wide <= QualityGuard.MAX_PIXELS + 1.0, "화소 수 상한")
	assert_true(2138 * wide <= QualityGuard.MAX_HEIGHT, "세로도 상한 안")
	assert_eq(QualityGuard.render_scale(Vector2i.ZERO), 1.0, "창 크기를 모를 때")


func test_빠르면_낮추지_않음() -> void:
	var guard := QualityGuard.new()
	assert_eq(_feed(guard, FAST, 30.0), 0)
	assert_eq(_feed(guard, 1.0 / 120.0, 30.0), 0, "120Hz")
	assert_eq(guard.level, 0)


func test_밀리면_2초마다_한_단계씩_낮추고_마지막_단계에서_멈추며_올리지_않음() -> void:
	var guard := QualityGuard.new()
	assert_eq(_feed(guard, 0.025, 1.9), 0, "2초 전에는 판단하지 않음")
	assert_eq(_feed(guard, 0.025, 0.2), 1, "2초가 차면 1단계")
	assert_eq(_feed(guard, 0.025, 2.1), 1)
	assert_eq(guard.level, 2)
	_feed(guard, 0.025, 20.0)
	assert_eq(guard.level, QualityGuard.LEVELS, "마지막 단계에서 멈춤")
	_feed(guard, FAST, 20.0)
	assert_eq(guard.level, QualityGuard.LEVELS, "빨라져도 올리지 않음")


func test_한두_번_끊김이나_탭_전환은_낮추지_않음() -> void:
	var guard := QualityGuard.new()
	_feed(guard, FAST, 1.0)
	guard.push(0.03)
	_feed(guard, FAST, 3.0)
	assert_eq(guard.level, 0, "2초에 한 번")
	guard.push(5.0)
	_feed(guard, FAST, 3.0)
	assert_eq(guard.level, 0, "긴 멈춤은 렉이 아님")


func test_빛_줄기가_가장_먼저_줄어듦() -> void:
	assert_eq(QualityGuard.LEVELS, 4, "줄기, 반사, MSAA, 빛 번짐")
	assert_eq(QualityGuard.streaks(48.0, 0), 48)
	assert_true(QualityGuard.streaks(48.0, 1) < 48, "1단계 줄기")
