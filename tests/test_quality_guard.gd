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


## v0.12.1 아이폰(배율 3): 여유가 있으면 2.0 → 2.5 (v0.12.2: AUTO는 2.5까지, 3.0은 HIGH만)
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
	assert_eq(_feed(guard, FAST, 30.0, 0.004), 0, "AUTO는 2.5가 끝 (발열)")
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
	assert_eq(guard.dpr_cap, 2.5)
	assert_eq(_feed(guard, 0.025, QualityGuard.GRACE + 3.2, 0.004), 1, "밀리면 배율을 먼저 (올린 뒤 쉬는 시간 포함)")
	assert_eq([guard.dpr_cap, guard.level], [2.0, 0])
	assert_eq(_feed(guard, FAST, 50.0, 0.004), 0, "오르내림 반복 금지: 내린 배율은 다시 올리지 않음")
	_feed(guard, 0.025, 3.2, 0.004)
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
	assert_eq(QualityGuard.top_for(3.0), 2.5, "AUTO는 2.5까지")
	assert_eq(QualityGuard.top_for(2.75), 2.5, "칸 아래로")
	assert_eq(QualityGuard.top_for(1.0), 2.0)
	assert_eq(QualityGuard.cap_for("auto", 2.5), 2.5)
	assert_eq(QualityGuard.cap_for("high", 2.0), 3.0)
	assert_eq(QualityGuard.cap_for("low", 3.0), 2.0)


## v0.12.2 아이폰 저전력 모드 실측: 33.3ms 사이에 가끔 46ms. 예전에는 99% 프레임 46 > 40ms로 3초마다 낮춰 Q4까지 갔다
func test_30Hz에서_가끔_46ms는_낮추지_않음() -> void:
	var guard := _phone_guard()
	var changes := 0
	for i in 30 * 300:  # 5분
		changes += 1 if guard.push(0.046 if i % 25 == 0 else 1.0 / 30.0, 0.012) else 0
	assert_eq(changes, 1, "30Hz를 알아챈 한 단계만")
	assert_eq([guard.level, guard.dpr_cap], [1, 2.0])


func _feed_heat(guard: QualityGuard, seconds: float, work: float) -> int:
	return _feed(guard, FAST, seconds, work)


func test_열_신호_1분_평균이_처음보다_20퍼센트_길면_한_단계() -> void:
	var guard := _phone_guard()
	_feed(guard, FAST, 3.2, 0.004)
	assert_eq(guard.dpr_cap, 2.5, "여유로 2.5")
	assert_eq(_feed_heat(guard, 125.0, 0.008), 0, "처음 1분이 기준, 같은 값이면 그대로")
	assert_eq(_feed_heat(guard, 61.0, 0.0094), 0, "17% 늘어남은 그대로")
	assert_eq(_feed_heat(guard, 61.0, 0.0097), 1, "21%면 한 단계")
	assert_true(guard.reason.begins_with("열"), guard.reason)
	assert_eq([guard.dpr_cap, guard.level], [2.0, 0], "배율부터")
	assert_eq(_feed_heat(guard, 200.0, 0.004), 0, "식어도 다시 올리지 않음")
	assert_eq(guard.dpr_cap, 2.0)


func test_열_신호는_판이_바뀌어도_이어지고_조건이_바뀌면_새로_잼() -> void:
	var guard := _ready_guard()
	guard.top_cap = QualityGuard.MAX_DPR  # 배율 2 화면: 여유로 배율이 오르지 않게
	_feed_heat(guard, 40.0, 0.008)
	guard.hold()  # 판이 끝나고 다음 판 (쉬는 5초는 세지 않는다)
	_feed_heat(guard, QualityGuard.GRACE + 21.0, 0.008)
	assert_eq(_feed_heat(guard, 61.0, 0.010), 1, "두 판에 걸친 1분이 기준")
	assert_eq(guard.level, 1)
	assert_eq(_feed_heat(guard, QualityGuard.GRACE + 61.0, 0.012), 0, "단계가 바뀌면 그 뒤 1분이 새 기준")
	assert_eq(_feed_heat(guard, 61.0, 0.016), 1)
	assert_eq(guard.level, 2)


func test_30Hz에서도_열_신호로는_낮춤() -> void:
	var guard := _phone_guard()
	_feed(guard, 1.0 / 30.0, 1.1, 0.012)
	assert_eq(guard.level, 1)
	_feed(guard, 1.0 / 30.0, QualityGuard.GRACE + 61.0, 0.012)
	assert_eq(_feed(guard, 1.0 / 30.0, 61.0, 0.016), 1)
	assert_eq(guard.level, 2)
