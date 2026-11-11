extends TestCase
## 진동: 이벤트마다 패턴, 설정으로 끄기, 지원하지 않는 기기는 조용히 건너뜀.


func test_충돌은_세_번_PERFECT는_한_번_새_기록은_두_번() -> void:
	var h := Haptics.new(true)
	var pulses := func(p: Array) -> int: return (p.size() + 1) / 2
	assert_eq(pulses.call(h.fire(Haptics.Event.CRASH)), 3)
	assert_eq(pulses.call(h.fire(Haptics.Event.PERFECT)), 1)
	assert_eq(pulses.call(h.fire(Haptics.Event.NEW_BEST)), 2)
	assert_true(h.fire(Haptics.Event.PERFECT)[0] <= 15, "PERFECT는 아주 짧게")
	assert_eq(h.sent.size(), 4)


func test_끄거나_지원하지_않으면_보내지_않음() -> void:
	var off := Haptics.new(true)
	off.enabled = false
	assert_eq(off.fire(Haptics.Event.CRASH), [])
	var none := Haptics.new(false)
	assert_eq(none.fire(Haptics.Event.CRASH), [])
	assert_eq(off.sent.size() + none.sent.size(), 0)


func test_데스크톱은_지원하지_않음() -> void:
	assert_false(Haptics.detect().supported)
