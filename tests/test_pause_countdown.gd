extends TestCase
## 이어 하기 3·2·1: 숫자는 한 박 간격, 음악은 다음 음악 박이 "1"에서 한 박 뒤에 오도록 다시 튼다.


func test_숫자는_한_박마다_3_2_1() -> void:
	var c := PauseCountdown.new(0.5, 0.0)
	assert_eq(c.digit(0.0), 3)
	assert_eq(c.digit(0.49), 3)
	assert_eq(c.digit(0.5), 2)
	assert_eq(c.digit(0.99), 2)
	assert_eq(c.digit(1.0), 0, "박 위에서 멈췄으면 '1'이 나오는 순간 다시 튼다")
	assert_true(c.done(1.0))


func test_박_사이에서_멈췄으면_다음_음악_박이_1에서_한_박_뒤() -> void:
	for phase: float in [0.1, 0.5, 0.9]:
		var beat := 0.375  # 160BPM
		var c := PauseCountdown.new(beat, phase)
		assert_eq(c.digit(2.0 * beat + 0.001), 1, "phase %.1f: '1'이 보임" % phase)
		var resume := c.resume_at()
		var next_music_beat := resume + (1.0 - phase) * beat  # 다시 튼 뒤 남은 박 조각
		assert_true(absf(next_music_beat - 3.0 * beat) < 1e-6, "phase %.1f: 다음 박 %.4f" % [phase, next_music_beat])
		assert_false(c.done(resume - 0.001))
		assert_true(c.done(resume))
		assert_eq(c.digit(resume), 0)
