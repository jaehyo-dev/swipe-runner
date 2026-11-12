extends TestCase
## 오디오 끊김 추정 테스트 (v0.11.2).


func test_고른_시계는_끊김_0_계단_흔들림도_0() -> void:
	var m := AudioGapMeter.new()
	for i in 40:
		m.push(-5000.0, i * 0.5)  # 묶음 최댓값은 WebKit 계단에도 같은 값
	assert_eq(m.count(20.0), 0)
	m.push(-5010.0, 20.5)
	assert_eq(m.count(20.5), 0, "15ms 이하 밀림은 셈하지 않음")


func test_오디오_시계가_서면_한_번_세고_10초_뒤_사라짐() -> void:
	var m := AudioGapMeter.new()
	m.push(-5000.0, 0.0)
	m.push(-5030.0, 0.5)
	m.push(-5030.0, 1.0)
	assert_eq(m.count(1.0), 1, "30ms 밀림 한 번, 그 뒤 새 기준")
	m.push(-5060.0, 1.5)
	assert_eq(m.count(1.5), 2)
	assert_eq(m.count(11.2), 1, "10초 지난 것은 버림")
	assert_eq(m.count(12.0), 0)


func test_일시정지가_끼면_기준을_새로_잡음() -> void:
	var m := AudioGapMeter.new()
	m.push(-5000.0, 0.0)
	m.push(null, 0.5)
	m.push(-9000.0, 4.0)  # 멈춘 동안 오디오 시계가 섰다: 끊김이 아니다
	assert_eq(m.count(4.0), 0)


func test_표시_글자() -> void:
	assert_eq(AudioGapMeter.text(48000.0, 0.0253, 2), "AUDIO 48.0kHz\n25 ms · GAP 2/10s")
	assert_eq(AudioGapMeter.text(44100.0, 0.015, -1), "AUDIO 44.1kHz\n15 ms · GAP -/10s")
