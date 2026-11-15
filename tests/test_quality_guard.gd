extends TestCase
## 렉 줄이기 판단: 3D 해상도 상한, 프레임이 밀릴 때 단계 낮추기.

const FAST := 1.0 / 60.0


func _feed(guard: QualityGuard, frame: float, seconds: float, work := -1.0) -> int:
	var raised := 0
	var t := 0.0
	while t < seconds:
		t += frame
		raised += 1 if guard.push(frame, work) else 0
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


## v0.12.1 아이폰(배율 3): 여유가 있으면 2.0 → 2.5 → 3.0
func _phone_guard() -> QualityGuard:
	var guard := QualityGuard.new()
	guard.top_cap = QualityGuard.top_for(3.0)
	_feed(guard, FAST, QualityGuard.GRACE, 0.004)
	return guard


func test_여유가_3초_이어지면_배율을_한_칸씩_올림() -> void:
	var guard := _phone_guard()
	assert_eq(guard.dpr_cap, 2.0, "2.0에서 시작")
	assert_eq(_feed(guard, FAST, 2.9, 0.004), 0, "3초 전에는 그대로")
	assert_eq(_feed(guard, FAST, 0.2, 0.004), 1)
	assert_eq(guard.dpr_cap, 2.5)
	assert_eq(_feed(guard, FAST, QualityGuard.GRACE + 3.2, 0.004), 1, "바꾼 뒤 쉬고 다시 3초")
	assert_eq(guard.dpr_cap, 3.0)
	assert_eq(_feed(guard, FAST, 30.0, 0.004), 0, "3.0이 끝")
	assert_eq(guard.level, 0)


func test_여유가_없거나_모르면_올리지_않음() -> void:
	var guard := _phone_guard()
	assert_eq(_feed(guard, FAST, 30.0, 0.012), 0, "일하는 시간 12ms > 간격의 70%% 11.7ms")
	assert_eq(_feed(guard, FAST, 30.0), 0, "일하는 시간을 모름")
	var desk := QualityGuard.new()  # 배율 2 이하 화면: 올릴 것이 없다
	desk.top_cap = QualityGuard.top_for(2.0)
	assert_eq(_feed(desk, FAST, 30.0, 0.002), 0)
	assert_eq(desk.dpr_cap, 2.0)


func test_밀리면_배율부터_내리고_다시_올리지_않음() -> void:
	var guard := _phone_guard()
	_feed(guard, FAST, 3.2, 0.004)
	_feed(guard, FAST, QualityGuard.GRACE + 3.2, 0.004)
	assert_eq(guard.dpr_cap, 3.0)
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE + 3.2, 0.004), 1, "밀리면 배율을 먼저 (올린 뒤 쉬는 시간 포함)")
	assert_eq([guard.dpr_cap, guard.level], [2.5, 0])
	assert_eq(_feed(guard, FAST, 120.0, 0.004), 0, "오르내림 반복 금지: 내린 배율은 다시 올리지 않음")
	_feed(guard, 0.025, 3.2, 0.004)
	assert_eq([guard.dpr_cap, guard.level], [2.0, 0], "2.0까지 내린 뒤에야 (앞 120초 동안 쉬는 시간은 끝났다)")
	_feed(guard, 0.025, QualityGuard.GRACE + 3.2, 0.004)
	assert_eq([guard.dpr_cap, guard.level], [2.0, 1], "효과를 낮춘다")
	assert_true(guard.reason.contains("효과 1단계"), guard.reason)


func test_30Hz_화면은_한_단계만_낮추고_느림으로_보지_않음() -> void:
	var guard := _phone_guard()
	assert_eq(_feed(guard, 1.0 / 30.0, 1.1, 0.004), 1, "30Hz를 알아채면 한 단계")
	assert_eq([guard.level, guard.dpr_cap], [1, 2.0])
	assert_true(guard.reason.contains("30Hz"), guard.reason)
	assert_eq(_feed(guard, 1.0 / 30.0, 60.0, 0.004), 0, "33ms 프레임을 느림으로 보지 않고, 올리지도 않음")
	assert_true(absf(guard.interval - 1.0 / 30.0) < 0.0001)
	assert_eq(_feed(guard, 0.045, 3.0 + QualityGuard.GRACE, 0.004), 1, "30Hz에서도 40ms를 넘게 밀리면 낮춤")
	assert_eq(guard.level, 2)
	_feed(guard, FAST, 3.0)
	assert_true(absf(guard.interval - 1.0 / 60.0) < 0.0001, "저전력 모드를 끄면 60Hz 기준으로")
	var other := QualityGuard.new()  # 60Hz에서 들쭉날쭉 밀리는 기기(16·33·50ms)는 30Hz로 보지 않는다
	for i in 600:
		other.push([FAST, 0.033, 0.05][i % 3])
	assert_true(other.interval < 0.02)
	assert_true(other.level > 0, "느림으로 낮춤")


func test_배율_상한별_그리기_크기() -> void:
	var size := Vector2i(1179, 2556)  # 아이폰 15 Pro
	assert_eq(QualityGuard.render_scale(size, 3.0, 3.0), 1.0, "3.0이면 기기 그대로")
	var s := QualityGuard.render_scale(size, 3.0, 2.5)
	assert_eq(Vector2i(roundi(1179 * s), roundi(2556 * s)), Vector2i(983, 2130))
	assert_eq(QualityGuard.top_for(3.0), 3.0)
	assert_eq(QualityGuard.top_for(2.75), 2.5, "칸 아래로")
	assert_eq(QualityGuard.top_for(1.0), 2.0)
	assert_eq(QualityGuard.cap_for("auto", 2.5), 2.5)
	assert_eq(QualityGuard.cap_for("high", 2.0), 3.0)
	assert_eq(QualityGuard.cap_for("low", 3.0), 2.0)
