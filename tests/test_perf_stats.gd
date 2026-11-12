extends TestCase
## 숨은 성능 표시 계산 테스트 (v0.11.1).


func test_최근_1초의_FPS_평균_최대와_주사율() -> void:
	var p := PerfStats.new()
	for i in 240:
		p.push(1.0 / 120.0)
	p.push(0.03)
	assert_true(absf(p.fps() - 120.0) < 3.0, "FPS %f" % p.fps())
	assert_eq(p.refresh_rate(), 120, "밀린 프레임 하나에 흔들리지 않음")
	assert_true(is_equal_approx(p.worst(), 0.03))
	for i in 120:
		p.push(1.0 / 60.0)
	assert_eq(p.refresh_rate(), 60, "1초 지난 값은 버림")
	assert_true(absf(p.average() - 1.0 / 60.0) < 0.0005)


func test_빠른_세_번_탭만_켜고_끔() -> void:
	var p := PerfStats.new()
	assert_false(p.tap(0.0))
	assert_false(p.tap(0.2))
	assert_true(p.tap(0.4), "세 번째")
	assert_false(p.tap(0.5), "다시 처음부터")
	assert_false(p.tap(1.5), "느린 탭은 이어지지 않음")
	assert_false(p.tap(1.7))
	assert_true(p.tap(1.9))


func test_탭_자리는_일시정지_버튼과_겹치지_않음() -> void:
	var pause := Rect2(TitleScreen.SOUND_MARGIN, TitleScreen.SOUND_MARGIN, TitleScreen.SOUND_SIDE, TitleScreen.SOUND_SIDE)
	assert_false(PerfStats.TAP_ZONE.intersects(pause))


func test_표시_글자() -> void:
	var p := PerfStats.new()
	for i in 60:
		p.push(1.0 / 60.0)
	assert_eq(p.text(Vector2i(786, 1704), 1, "auto", 3.0), "FPS 60 · 60Hz · 16.7 / 16.7 ms\n3D 786x1704 · Q1 AUTO · DPR 3.00")
