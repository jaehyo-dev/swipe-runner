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


## 페이지를 연 뒤의 쉬는 시간을 넘긴 판단기
func _ready_guard() -> QualityGuard:
	var guard := QualityGuard.new()
	_feed(guard, FAST, QualityGuard.GRACE)
	return guard


func test_3초_연속_밀릴_때만_한_단계씩_낮추고_이유를_남기며_마지막_단계에서_멈춤() -> void:
	var guard := _ready_guard()
	assert_eq(_feed(guard, 0.025, 2.9), 0, "3초 전에는 낮추지 않음")
	assert_eq(_feed(guard, 0.025, 0.2), 1, "3초 연속이면 1단계")
	assert_true(guard.reason.contains("25.0"), "이유에 99%% 프레임: " + guard.reason)
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE - 0.1), 0, "낮춘 뒤 쉬는 동안은 판단하지 않음")
	assert_eq(_feed(guard, 0.025, 3.2), 1, "쉰 뒤 다시 3초면 한 단계")
	assert_eq(guard.level, 2)
	_feed(guard, 0.025, 60.0)
	assert_eq(guard.level, QualityGuard.LEVELS, "마지막 단계에서 멈춤")
	_feed(guard, FAST, 20.0)
	assert_eq(guard.level, QualityGuard.LEVELS, "빨라져도 올리지 않음")


func test_느린_구간이_끊기면_처음부터_다시_셈() -> void:
	var guard := _ready_guard()
	for i in 5:
		_feed(guard, 0.025, 2.0)
		_feed(guard, FAST, 1.0)
	assert_eq(guard.level, 0, "2초 느림 + 1초 정상 반복")


func test_페이지를_연_뒤_탭에서_돌아온_뒤_화면_전환_뒤_5초는_판단하지_않음() -> void:
	var guard := QualityGuard.new()
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE + 2.9), 0, "연 뒤 5초 + 2.9초")
	guard.push(1.0)  # 탭이 가려졌다 돌아옴
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE + 2.9), 0, "돌아온 뒤 5초 + 2.9초")
	guard.hold()  # 화면 전환
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE + 2.9), 0, "전환 뒤 5초 + 2.9초")
	assert_eq(_feed(guard, 0.025, 0.2), 1, "그 뒤 3초 연속이면 낮춤")


func test_빛_줄기는_반사_다음에_줄어듦() -> void:
	assert_eq(QualityGuard.LEVELS, 4, "반사, 줄기, 넓은 빛 번짐, MSAA")
	assert_eq(QualityGuard.streaks(48.0, 0), 48)
	assert_eq(QualityGuard.streaks(48.0, 1), 48, "1단계는 반사만")
	assert_true(QualityGuard.streaks(48.0, 2) < 48, "2단계 줄기")


func test_기기_배율_2_0까지만_그림() -> void:
	var s := QualityGuard.render_scale(Vector2i(1179, 2556), 3.0)  # 아이폰 15 Pro
	assert_eq(Vector2i(roundi(1179 * s), roundi(2556 * s)), Vector2i(786, 1704))
	assert_eq(QualityGuard.render_scale(Vector2i(780, 1688), 2.0), 1.0, "배율 2는 그대로")
	assert_eq(QualityGuard.render_scale(Vector2i(1280, 720), 1.0), 1.0)


func test_설정_GRAPHICS() -> void:
	assert_eq(QualityGuard.level_for("auto", 2), 2)
	assert_eq(QualityGuard.level_for("high", 2), 0)
	assert_eq(QualityGuard.level_for("low", 0), QualityGuard.LEVELS)
