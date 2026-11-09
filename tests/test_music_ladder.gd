extends TestCase
## 음악 사다리: 속도·박·이동 거리·색 진하기·곡 예약 계산 테스트.

const LEAD := 7.0
const MIN_LEAD := 6.2


func test_표대로_BPM과_속도와_편곡_단계() -> void:
	var want := []
	for i in 13:  # 100~160BPM, 5BPM마다 속도 +1 (12에서 24까지), 100~105 원본, 110~115 A, 120부터 B
		want.append([100 + 5 * i, 12.0 + i, 0 if i < 2 else (1 if i < 4 else 2)])
	assert_eq(MusicLadder.STEPS.size(), want.size())
	for i in want.size():
		var ladder := MusicLadder.new(i)
		assert_eq(MusicLadder.STEPS[i]["bpm"], want[i][0])
		assert_eq(ladder.speed_at(1.0), want[i][1])
		assert_eq(MusicLadder.STEPS[i]["stage"], want[i][2])


func test_bpm_값으로_단계를_찾고_없는_값은_거름() -> void:
	assert_eq(MusicLadder.step_of_bpm(115), 3)
	assert_eq(MusicLadder.step_of_bpm(160), 12)
	assert_eq(MusicLadder.step_of_bpm(99), -1)
	assert_eq(MusicLadder.step_of_bpm(0), -1)


func _climb(ladder: MusicLadder, until: float) -> void:
	var t := 0.0
	while t < until:
		t += 1.0 / 60.0
		ladder.plan(t, LEAD, MIN_LEAD, true)


func test_4마디가_끝나면_다음_BPM으로_160에서_멈춤() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 200.0)
	assert_eq(ladder.segments.size(), MusicLadder.STEPS.size())
	var at := 0.0
	for i in MusicLadder.STEPS.size():
		assert_true(absf(ladder.segments[i]["start"] - at) < 0.000001, "구간 %d 시작" % i)
		assert_eq(ladder.segments[i]["beat"], i * 16)
		assert_eq(ladder.segments[i]["step"], i)
		at += MusicLadder.span_time(i)
	assert_true(absf(ladder.segments[-1]["start"] - 92.07) < 0.1, "160BPM 도착 %f초" % ladder.segments[-1]["start"])


func test_새_곡은_같은_마디_위치에서_시작() -> void:
	var ladder := MusicLadder.new()
	var t := 0.0
	var froms := []
	while t < 200.0:
		t += 1.0 / 60.0
		var plan := ladder.plan(t, LEAD, MIN_LEAD, true)
		if not plan.is_empty():
			froms.append(plan["from"] / MusicLadder.span_time(plan["step"]))
	assert_eq(froms.size(), MusicLadder.STEPS.size() - 1)
	for i in froms.size():
		assert_true(absf(froms[i] - (i + 1) % 4) < 0.000001, "경계 %d: 곡 안 %f구간" % [i, froms[i]])


func test_이동_거리는_구간마다_속도_곱하기_시간을_더한_값과_같음() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 200.0)
	for t in [0.0, 1.0, 19.2, 19.5, 40.0, 100.0, 150.0, 199.0]:
		var sum := 0.0
		for i in ladder.segments.size():
			var seg: Dictionary = ladder.segments[i]
			var end: float = ladder.segments[i + 1]["start"] if i + 1 < ladder.segments.size() else INF
			if t > seg["start"]:
				sum += MusicLadder.STEPS[seg["step"]]["speed"] * (minf(t, end) - seg["start"])
		assert_true(absf(ladder.distance_at(t) - sum) < 0.0001, "시각 %f: %f, %f" % [t, ladder.distance_at(t), sum])


## 박 → 거리와 시간 → 거리는 같은 계산이어야 장애물과 물방울이 박에 닿는다
func test_박의_거리는_그_박_시각의_거리와_같음() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 200.0)
	for beat in [0.0, 0.5, 31.0, 31.5, 32.0, 32.5, 63.0, 64.0, 100.5, 192.0, 300.0]:
		assert_true(absf(ladder.distance_of_beat(beat) - ladder.distance_at(ladder.time_of_beat(beat))) < 0.0001, "박 %f" % beat)


func test_속도는_경계_순간에만_바뀌고_거리는_끊기지_않음() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 20.0)
	var edge: float = ladder.segments[1]["start"]
	assert_eq(ladder.speed_at(edge - 0.001), 12.0)
	assert_eq(ladder.speed_at(5.0), 12.0, "구간 중간은 그대로")
	assert_eq(ladder.speed_at(edge), 13.0)
	assert_true(absf(ladder.distance_at(edge) - ladder.distance_at(edge - 0.0001)) < 0.01)


## 경계 전에 생긴 장애물도 경계 뒤에 정확히 자기 박의 시각에 z=0에 닿는다
func test_경계를_넘는_장애물도_박에_도착() -> void:
	for start in MusicLadder.STEPS.size() - 1:
		var ladder := MusicLadder.new(start)
		var field := ObstacleField.new(11, ladder)
		var edge := MusicLadder.span_time(start)
		var t := 0.0
		var crossing := []
		while t < edge - 1.0:
			t += 1.0 / 60.0
			ladder.plan(t, LEAD, MIN_LEAD, true)
			field.step(ladder.distance_at(t))
		for item in field.items:
			if ladder.time_of_beat(item["beat"]) > edge:
				crossing.append(item)
		assert_true(crossing.size() > 0, "넘는 장애물 %d개" % crossing.size())
		for item in crossing:
			var at := ladder.time_of_beat(item["beat"])
			field.step(ladder.distance_at(at))
			assert_true(absf(item["z"]) < 0.000001, "BPM %d 박 %f z %f" % [MusicLadder.STEPS[start]["bpm"], item["beat"], item["z"]])


## 경계는 그 뒤 박의 장애물이 z -60에 나오기 전에 정해져야 도착 거리가 맞는다
func test_예약은_장애물이_나오는_거리보다_먼저() -> void:
	var slowest := 12.0
	assert_true(MIN_LEAD > -ObstacleField.SPAWN_Z / slowest, "가장 느린 속도에서 z -60까지 걸리는 시간보다 먼저")
	assert_eq(AudioManager.SCHEDULE_LEAD, LEAD)
	assert_eq(AudioManager.SCHEDULE_MIN, MIN_LEAD)


func test_경계_시각이_가까워져야_예약하고_다음_곡이_없으면_4마디_더() -> void:
	var ladder := MusicLadder.new()
	var edge := MusicLadder.span_time(0)
	assert_true(ladder.plan(edge - 7.5, LEAD, MIN_LEAD, true).is_empty(), "아직 멀다")
	assert_true(ladder.plan(edge - 6.9, LEAD, MIN_LEAD, false).is_empty(), "곡이 아직 준비 안 됨")
	var plan := ladder.plan(edge - 6.9, LEAD, MIN_LEAD, true)
	assert_eq(plan["step"], 1)
	assert_true(absf(plan["at"] - edge) < 0.000001)
	assert_true(ladder.plan(edge - 6.5, LEAD, MIN_LEAD, true).is_empty(), "두 번 예약하지 않음")


func test_경계를_놓치면_같은_곡이_4마디_더_돌아도_박이_맞음() -> void:
	var ladder := MusicLadder.new()
	var edge := MusicLadder.span_time(0)
	assert_true(ladder.plan(edge - 5.0, LEAD, MIN_LEAD, true).is_empty(), "늦었다: 다음 경계는 아직 멀다")
	var plan := ladder.plan(edge * 2.0 - 6.5, LEAD, MIN_LEAD, true)
	assert_true(absf(plan["at"] - edge * 2.0) < 0.000001, "8마디 끝")
	assert_true(absf(plan["from"] - 32.0 * 60.0 / 105.0) < 0.000001, "다음 곡의 8마디째")
	assert_eq(ladder.segments[-1]["beat"], 32)
	assert_true(absf(ladder.beat_at(edge * 2.0) - 32.0) < 0.000001)
	assert_true(absf(ladder.distance_at(edge * 2.0) - 32 * 7.2) < 0.000001, "놓친 구간은 옛 속도로 쌓임")


## 빠른 단계는 4마디(155BPM 6.19초)가 예약 거리보다 짧다. 앞 구간이 시작하기 전에도 다음 경계를 정해야 4마디를 놓치지 않는다
func test_빠른_단계도_경계를_놓치지_않고_모두_4마디씩() -> void:
	var ladder := MusicLadder.new(8)
	_climb(ladder, 60.0)
	assert_eq(ladder.segments[-1]["step"], 12)
	for i in range(1, ladder.segments.size()):
		assert_eq(ladder.segments[i]["beat"] - ladder.segments[i - 1]["beat"], 16, "구간 %d" % i)


func test_다음_경계를_미리_알_수_있고_맨_위에서는_없음() -> void:
	var edge := MusicLadder.new().next_edge(0.0, MIN_LEAD)
	assert_eq(edge["step"], 1)
	assert_eq(edge["beat"], 16)
	assert_true(MusicLadder.new(12).next_edge(0.0, MIN_LEAD).is_empty())


func test_편곡_단계가_오른_구간에서만_경과_시간을_돌려줌() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 200.0)
	assert_eq(ladder.stage_up_age(10.0), -1.0, "첫 구간")
	assert_eq(ladder.stage_up_age(ladder.segments[1]["start"] + 0.1), -1.0, "105: BPM만")
	assert_true(absf(ladder.stage_up_age(ladder.segments[2]["start"] + 0.1) - 0.1) < 0.000001, "110: 원본 → A")
	assert_eq(ladder.stage_up_age(ladder.segments[3]["start"] + 0.1), -1.0, "115: BPM만")
	assert_true(absf(ladder.stage_up_age(ladder.segments[4]["start"] + 0.1) - 0.1) < 0.000001, "120: A → B")
	assert_eq(ladder.stage_up_age(ladder.segments[5]["start"] + 0.1), -1.0, "125: BPM만")


func test_색_진하기는_BPM_계산대로이고_160BPM에서_1() -> void:
	for i in MusicLadder.STEPS.size():
		assert_true(is_equal_approx(MusicLadder.step_tint(i), i / 12.0), "단계 %d" % i)


func test_색_진하기는_2마디_동안_끊김_없이_따라감() -> void:
	var ladder := MusicLadder.new()
	_climb(ladder, 200.0)
	assert_eq(ladder.tint_at(-0.1), 0.0, "소리 나기 전")
	assert_eq(ladder.tint_at(5.0), 0.0)
	for i in range(1, MusicLadder.STEPS.size()):
		var seg: Dictionary = ladder.segments[i]
		var hold: float = MusicLadder.beat_time(i) * 4 * 2
		assert_true(absf(ladder.tint_at(seg["start"] - 0.0001) - MusicLadder.step_tint(i - 1)) < 0.0001, "경계 앞은 이전 값")
		assert_true(absf(ladder.tint_at(seg["start"]) - MusicLadder.step_tint(i - 1)) < 0.0001, "경계 순간 끊기지 않음")
		assert_true(absf(ladder.tint_at(seg["start"] + hold * 0.5) - (MusicLadder.step_tint(i - 1) + MusicLadder.step_tint(i)) * 0.5) < 0.0001, "2마디의 절반에 중간값")
		assert_eq(ladder.tint_at(seg["start"] + hold), MusicLadder.step_tint(i), "2마디 뒤 새 값")
	var t := 0.0
	var last := 0.0
	while t < 110.0:
		t += 1.0 / 60.0
		var now := ladder.tint_at(t)
		assert_true(now >= last and now - last < 0.005, "프레임마다 조금씩만 오름 %f → %f" % [last, now])
		last = now


func test_시작_단계를_바꿔도_진하기는_그_BPM부터() -> void:
	assert_eq(MusicLadder.new(3).tint_at(0.0), 0.25)
	assert_eq(MusicLadder.new(6).tint_at(0.0), 0.5)
	assert_eq(MusicLadder.new(12).tint_at(10.0), 1.0)
