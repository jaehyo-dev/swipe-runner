extends TestCase
## 홈 화면 앱(PWA) 상태 읽기 테스트 (v0.12.0).


func test_상태_문자열_읽기() -> void:
	assert_eq(PwaState.parse(""), {"update": false, "hint": ""})
	assert_eq(PwaState.parse("update"), {"update": true, "hint": ""})
	assert_eq(PwaState.parse("install"), {"update": false, "hint": "install"})
	assert_eq(PwaState.parse("update,ios"), {"update": true, "hint": "ios"})
	assert_eq(PwaState.parse("install,ios")["hint"], "ios", "아이폰 안내가 먼저")
	assert_eq(PwaState.parse("엉뚱"), {"update": false, "hint": ""})


func test_안전_영역을_화면_단위로() -> void:
	# 아이폰 15 Pro 홈 화면 앱: 393x852, 위 59, 아래 34 (CSS px). 화면은 너비 720 기준 → 높이 1560.6
	var view := Vector2(720.0, 852.0 * 720.0 / 393.0)
	var got := PwaState.insets("59,0,34,0,393,852", view)
	assert_true(absf(got.x - 59.0 * 720.0 / 393.0) < 0.01, str(got))
	assert_true(absf(got.y - 34.0 * 720.0 / 393.0) < 0.01, str(got))
	assert_eq(PwaState.insets("", view), Vector2.ZERO)
	assert_eq(PwaState.insets("1,2,3", view), Vector2.ZERO, "칸이 모자라면 0")
	assert_eq(PwaState.insets("10,0,10,0,393,0", view), Vector2.ZERO, "창 높이 0이면 0")
	assert_eq(PwaState.insets("-5,0,-5,0,393,852", view), Vector2.ZERO, "음수는 0")
