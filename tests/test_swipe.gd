extends TestCase
## 스와이프 방향 판정 테스트. 손가락을 떼기 전에 임계 거리를 넘는 순간 반응해야 한다.

const Dir := SwipeDetector.Dir


func test_네_방향_판정() -> void:
	assert_eq(SwipeDetector.classify(Vector2(100, 0)), Dir.RIGHT)
	assert_eq(SwipeDetector.classify(Vector2(-100, 0)), Dir.LEFT)
	assert_eq(SwipeDetector.classify(Vector2(0, 100)), Dir.DOWN)
	assert_eq(SwipeDetector.classify(Vector2(0, -100)), Dir.UP)


func test_최소_거리보다_짧으면_무시() -> void:
	assert_eq(SwipeDetector.classify(Vector2(SwipeDetector.MIN_DISTANCE - 1.0, 0)), Dir.NONE)
	assert_eq(SwipeDetector.classify(Vector2(SwipeDetector.MIN_DISTANCE, 0)), Dir.RIGHT, "정확히 임계 거리면 인정")
	assert_eq(SwipeDetector.classify(Vector2.ZERO), Dir.NONE)


func test_지배_축이_뚜렷하지_않은_대각선은_무시() -> void:
	assert_eq(SwipeDetector.classify(Vector2(100, 90)), Dir.NONE)
	assert_eq(SwipeDetector.classify(Vector2(-80, -80)), Dir.NONE)


func test_조금_비스듬해도_주된_축이_뚜렷하면_인정() -> void:
	assert_eq(SwipeDetector.classify(Vector2(100, 30)), Dir.RIGHT)
	assert_eq(SwipeDetector.classify(Vector2(20, -100)), Dir.UP)


func test_손가락을_떼지_않고_임계_거리를_넘는_순간_바로_반응() -> void:
	var swipe := SwipeDetector.new()
	swipe.press(Vector2(300, 600))
	assert_eq(swipe.move(Vector2(320, 602)), Dir.NONE, "아직 짧음")
	assert_eq(swipe.move(Vector2(300 + SwipeDetector.MIN_DISTANCE, 600)), Dir.RIGHT, "넘는 순간 (뗌 없이)")


func test_한_번_반응한_뒤_기준점이_옮겨져_이어서_다시_스와이프할_수_있음() -> void:
	var swipe := SwipeDetector.new()
	swipe.press(Vector2(300, 600))
	assert_eq(swipe.move(Vector2(360, 600)), Dir.RIGHT)
	assert_eq(swipe.move(Vector2(365, 600)), Dir.NONE, "같은 동작이 연달아 반응하면 안 됨")
	assert_eq(swipe.move(Vector2(300, 600)), Dir.LEFT, "되돌아가면 왼쪽")


func test_손가락을_뗀_뒤나_누르기_전의_움직임은_무시() -> void:
	var swipe := SwipeDetector.new()
	assert_eq(swipe.move(Vector2(500, 0)), Dir.NONE, "누르기 전")
	swipe.press(Vector2.ZERO)
	swipe.release()
	assert_eq(swipe.move(Vector2(500, 0)), Dir.NONE, "뗀 뒤")
