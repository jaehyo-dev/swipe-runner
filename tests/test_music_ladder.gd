extends TestCase
## 음악 사다리: 속도·박·이동 거리·곡 예약 계산 테스트.

const LEAD := 1.0
const MIN_LEAD := 0.6


func test_표대로_BPM과_속도와_편곡_단계() -> void:
	var want := [[100, 9.0, 0], [105, 9.45, 0], [110, 9.9, 1], [115, 10.35, 1], [120, 10.8, 2], [125, 11.25, 2], [130, 11.7, 2]]
	assert_eq(MusicLadder.STEPS.size(), want.size())
	for i in want.size():
		var ladder := MusicLadder.new(i)
		assert_eq(MusicLadder.STEPS[i]["bpm"], want[i][0])
		assert_true(is_equal_approx(ladder.speed_at(1.0), want[i][1]), "속도 %f" % ladder.speed_at(1.0))
		assert_eq(MusicLadder.STEPS[i]["stage"], want[i][2])


func test_bpm_값으로_단계를_찾고_없는_값은_거름() -> void:
	assert_eq(MusicLadder.step_of_bpm(115), 3)
	assert_eq(MusicLadder.step_of_bpm(99), -1)
	assert_eq(MusicLadder.step_of_bpm(0), -1)


func _climb(ladder: MusicLadder, until: float) -> void:
	var t := 0.0
	while t < until:
		t += 1.0 / 60.0
		ladder.plan(t, LEAD, MIN_LEAD, true)


func test_한_바퀴가_끝나면_다음_BPM으로_130에서_멈춤() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 400.0)
	assert_eq(ladder.segments.size(), MusicLadder.STEPS.size())
	var at := 0.0
	for i in MusicLadder.STEPS.size():
		assert_true(absf(ladder.segments[i]["start"] - at) < 0.000001, "구간 %d 시작" % i)
		assert_eq(ladder.segments[i]["beat"], i * MusicLadder.LAP_BEATS)
		assert_eq(ladder.segments[i]["step"], i)
		at += MusicLadder.lap_time(i)


func test_이동_거리는_구간마다_속도_곱하기_시간을_더한_값과_같음() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 300.0)
	for t in [0.0, 1.0, 38.4, 39.0, 100.0, 180.0, 240.0, 299.0]:
		var sum := 0.0
		for i in ladder.segments.size():
			var seg: Dictionary = ladder.segments[i]
			var end: float = ladder.segments[i + 1]["start"] if i + 1 < ladder.segments.size() else INF
			if t > seg["start"]:
				sum += RunLogic.SPEED * MusicLadder.STEPS[seg["step"]]["bpm"] / 100.0 * (minf(t, end) - seg["start"])
		assert_true(absf(ladder.distance_at(t) - sum) < 0.0001, "시각 %f: %f, %f" % [t, ladder.distance_at(t), sum])


func test_속도는_경계_순간에만_바뀌고_거리는_끊기지_않음() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 40.0)
	var edge: float = ladder.segments[1]["start"]
	assert_eq(ladder.speed_at(edge - 0.001), 9.0)
	assert_eq(ladder.speed_at(30.0), 9.0, "바퀴 중간은 그대로")
	assert_true(is_equal_approx(ladder.speed_at(edge), 9.45))
	assert_true(absf(ladder.distance_at(edge) - ladder.distance_at(edge - 0.0001)) < 0.01)


## 경계 전에 생긴 장애물도 경계 뒤에 정확히 자기 박의 시각에 z=0에 닿는다
func test_경계를_넘는_장애물도_박에_도착() -> void:
	for start in MusicLadder.STEPS.size() - 1:
		var ladder := MusicLadder.new(start)
		var field := ObstacleField.new(11)
		var edge := MusicLadder.lap_time(start)
		ladder.plan(edge - 0.8, LEAD, MIN_LEAD, true)
		var crossing := []
		var t := edge - 2.0
		field.step(ladder.distance_at(t))
		for item in field.items:
			if ladder.time_of_beat(item["beat"]) > edge:
				crossing.append(item)
		assert_true(crossing.size() > 2, "넘는 장애물 %d개" % crossing.size())
		for item in crossing:
			var at := ladder.time_of_beat(item["beat"])
			field.step(ladder.distance_at(at))
			assert_true(absf(item["z"]) < 0.000001, "BPM %d 박 %d z %f" % [MusicLadder.STEPS[start]["bpm"], item["beat"], item["z"]])


func test_경계_시각이_가까워져야_예약하고_다음_곡이_없으면_한_바퀴_더() -> void:
	var ladder := MusicLadder.new()
	var edge := MusicLadder.lap_time(0)
	assert_true(ladder.plan(edge - 1.5, LEAD, MIN_LEAD, true).is_empty(), "아직 멀다")
	assert_true(ladder.plan(edge - 0.9, LEAD, MIN_LEAD, false).is_empty(), "곡이 아직 준비 안 됨")
	var plan := ladder.plan(edge - 0.9, LEAD, MIN_LEAD, true)
	assert_eq(plan["step"], 1)
	assert_true(absf(plan["at"] - edge) < 0.000001)
	assert_true(ladder.plan(edge - 0.7, LEAD, MIN_LEAD, true).is_empty(), "두 번 예약하지 않음")


func test_경계를_놓치면_같은_곡이_한_바퀴_더_돌아도_박이_맞음() -> void:
	var ladder := MusicLadder.new()
	var edge := MusicLadder.lap_time(0)
	assert_true(ladder.plan(edge + 0.1, LEAD, MIN_LEAD, true).is_empty(), "다음 경계는 아직 멀다")
	var plan := ladder.plan(edge * 2.0 - 0.8, LEAD, MIN_LEAD, true)
	assert_true(absf(plan["at"] - edge * 2.0) < 0.000001, "두 바퀴 끝")
	assert_eq(ladder.segments[-1]["beat"], MusicLadder.LAP_BEATS * 2)
	assert_true(absf(ladder.beat_at(edge * 2.0) - 128.0) < 0.000001)


func test_편곡_단계가_오른_구간에서만_경과_시간을_돌려줌() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 300.0)
	assert_eq(ladder.stage_up_age(10.0), -1.0, "첫 구간")
	assert_eq(ladder.stage_up_age(ladder.segments[1]["start"] + 0.1), -1.0, "105: BPM만")
	assert_true(absf(ladder.stage_up_age(ladder.segments[2]["start"] + 0.1) - 0.1) < 0.000001, "110: 원본 → A")
	assert_eq(ladder.stage_up_age(ladder.segments[3]["start"] + 0.1), -1.0, "115: BPM만")
	assert_true(absf(ladder.stage_up_age(ladder.segments[4]["start"] + 0.1) - 0.1) < 0.000001, "120: A → B")
	assert_eq(ladder.stage_up_age(ladder.segments[5]["start"] + 0.1), -1.0, "125: BPM만")
