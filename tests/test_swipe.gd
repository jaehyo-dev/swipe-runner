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


## 손가락을 대고 끝까지 밀며 지나간 위치들을 넣고, 돌아온 판정(NONE 제외)을 모은다.
func _drag(swipe: SwipeDetector, from: Vector2, to: Vector2, steps: int, index := 0) -> Array:
	var got := []
	swipe.press(from, index)
	for i in steps:
		var dir := swipe.move(from.lerp(to, float(i + 1) / steps), index)
		if dir != Dir.NONE:
			got.append(dir)
	return got


func test_한_번에_길게_밀어도_한_번만_반응() -> void:
	var swipe := SwipeDetector.new()
	# 화면 폭 거의 끝까지(임계 거리의 10배 이상) 잘게 밀기
	assert_eq(_drag(swipe, Vector2(40, 600), Vector2(700, 600), 60), [Dir.RIGHT], "오른쪽 한 번")
	swipe.release()
	assert_eq(_drag(swipe, Vector2(700, 600), Vector2(40, 600), 60), [Dir.LEFT], "왼쪽 한 번")


func test_한_번_반응한_뒤_되돌아가거나_방향을_바꿔도_무시() -> void:
	var swipe := SwipeDetector.new()
	swipe.press(Vector2(300, 600))
	assert_eq(swipe.move(Vector2(360, 600)), Dir.RIGHT)
	assert_eq(swipe.move(Vector2(500, 600)), Dir.NONE, "더 밀어도 무시")
	assert_eq(swipe.move(Vector2(100, 600)), Dir.NONE, "되돌아가도 무시")
	assert_eq(swipe.move(Vector2(100, 100)), Dir.NONE, "위로 꺾어도 무시")


func test_떼고_다시_밀면_다음_동작() -> void:
	var swipe := SwipeDetector.new()
	assert_eq(_drag(swipe, Vector2(300, 600), Vector2(600, 600), 20), [Dir.RIGHT])
	swipe.release()
	assert_eq(_drag(swipe, Vector2(300, 600), Vector2(600, 600), 20), [Dir.RIGHT], "두 번째 스와이프도 인정")


func test_위로_길게_밀어도_점프는_한_번() -> void:
	var swipe := SwipeDetector.new()
	assert_eq(_drag(swipe, Vector2(360, 1200), Vector2(360, 100), 80), [Dir.UP])
	swipe.release()
	assert_eq(_drag(swipe, Vector2(360, 100), Vector2(360, 1200), 80), [Dir.DOWN], "아래도 같은 규칙")


func test_다른_손가락은_따로_한_번씩_인정() -> void:
	var swipe := SwipeDetector.new()
	assert_eq(_drag(swipe, Vector2(100, 600), Vector2(400, 600), 10, 0), [Dir.RIGHT], "첫 손가락")
	# 첫 손가락을 떼지 않은 채 두 번째 손가락이 새로 스와이프
	assert_eq(_drag(swipe, Vector2(500, 600), Vector2(200, 600), 10, 1), [Dir.LEFT], "두 번째 손가락")
	assert_eq(swipe.move(Vector2(700, 600), 0), Dir.NONE, "첫 손가락은 여전히 무시")
	swipe.release(1)
	assert_eq(swipe.move(Vector2(0, 600), 0), Dir.NONE, "다른 손가락을 떼도 첫 손가락은 그대로 무시")


func test_손가락을_뗀_뒤나_누르기_전의_움직임은_무시() -> void:
	var swipe := SwipeDetector.new()
	assert_eq(swipe.move(Vector2(500, 0)), Dir.NONE, "누르기 전")
	swipe.press(Vector2.ZERO)
	swipe.release()
	assert_eq(swipe.move(Vector2(500, 0)), Dir.NONE, "뗀 뒤")
