extends TestCase
## 박자 패턴과 공정성 테스트 (시드 고정).

const Kind := ObstacleField.Kind
const SEEDS := [1, 7, 42, 136, 2026]


## 사다리가 오르지 않는 1단계(원본) 규칙만 보려면 start_step 0의 앞쪽 32 + 32박만 쓴다
func _sequence(seed_value: int, count: int, first := 0, start_step := 0) -> Array[Dictionary]:
	var pattern := BeatPattern.new(seed_value, first, start_step)
	var items: Array[Dictionary] = []
	for i in count:
		items.append(pattern.next())
	return items


## 1단계 한 판(16마디)을 시드를 바꿔 모은다
func _stage_one(seeds: int) -> Array[Array]:
	var runs: Array[Array] = []
	for s in range(1, seeds + 1):
		var pattern := BeatPattern.new(s, ObstacleField.FIRST_BEAT)
		var items := []
		while pattern.beat < MusicLadder.STEP_BEATS * 2:
			items.append(pattern.next())
		runs.append(items)
	return runs


func test_1단계_간격_규칙_점프_슬라이드_뒤_2박_레인_이동은_1박_이상() -> void:
	for items in _stage_one(200):
		for i in range(1, items.size()):
			var gap: float = items[i]["beat"] - items[i - 1]["beat"]
			assert_true(gap >= 1.0, "1박 이상")
			if items[i - 1]["kind"] != Kind.BLOCK:
				assert_true(gap >= 2.0, "큰 동작 뒤 박 %f 간격 %f" % [items[i - 1]["beat"], gap])
			assert_true(gap <= 3.0, "너무 비지 않음 %f" % gap)


func test_1단계_앞_4마디는_2박마다_다음_4마디에_1박이_가끔_뒤_8마디는_1에서_2박마다() -> void:
	var ones := 0
	var twos := 0
	var melody := {}
	for items in _stage_one(200):
		for i in range(1, items.size()):
			var prev: float = items[i - 1]["beat"]
			var now: float = items[i]["beat"]
			var gap := now - prev
			if now <= 16.0:
				assert_eq(gap, 2.0, "앞 4마디 박 %f" % prev)
				assert_eq(fmod(now, 2.0), 0.0, "2박 격자")
			elif prev >= 16.0 and now < 32.0:
				if items[i - 1]["kind"] == Kind.BLOCK:
					ones += 1 if gap == 1.0 else 0
					twos += 1 if gap == 2.0 else 0
			elif prev >= 32.0:
				melody[gap] = true
	assert_true(ones > 0 and ones < twos, "1박은 가끔: 1박 %d, 2박 %d" % [ones, twos])
	assert_true(melody.has(1.0) and melody.has(2.0), "뒤 8마디는 1박과 2박이 섞임")


func test_1단계_동작_비율_앞은_레인_이동_위주_뒤는_골고루_마디_첫_박엔_큰_동작이_늘어남() -> void:
	var count := {}
	for key in ["intro", "intro_first", "melody", "melody_first"]:
		count[key] = {Kind.BLOCK: 0, Kind.LOW: 0, Kind.HIGH: 0}
	for items in _stage_one(400):
		for item in items:
			var key: String = "intro" if BeatPattern.is_intro(item["beat"]) else "melody"
			if fmod(item["beat"], 4.0) == 0.0:
				key += "_first"
			count[key][item["kind"]] += 1
	var big := func(key: String) -> float:
		var c: Dictionary = count[key]
		return float(c[Kind.LOW] + c[Kind.HIGH]) / (c[Kind.BLOCK] + c[Kind.LOW] + c[Kind.HIGH])
	assert_true(big.call("intro") < 0.3, "앞: 점프·슬라이드는 가끔 %f" % big.call("intro"))
	assert_true(big.call("intro_first") > big.call("intro") + 0.15, "앞 마디 첫 박 %f" % big.call("intro_first"))
	assert_true(big.call("melody") > 0.55 and big.call("melody") < 0.8, "뒤: 세 동작 골고루 %f" % big.call("melody"))
	assert_true(big.call("melody_first") > big.call("melody") + 0.05, "뒤 마디 첫 박 %f" % big.call("melody_first"))
	var low: int = count["melody"][Kind.LOW]
	var high: int = count["melody"][Kind.HIGH]
	assert_true(absf(low - high) < (low + high) * 0.15, "점프 %d, 슬라이드 %d" % [low, high])


## 박 → 그 박의 장애물들. start_step부터 사다리가 오르는 순서 그대로
func _rows(seed_value: int, last_beat: float, start_step := 0) -> Dictionary:
	var pattern := BeatPattern.new(seed_value, ObstacleField.FIRST_BEAT, start_step)
	var rows := {}
	while true:
		var item := pattern.next()
		if item["beat"] > last_beat:
			return rows
		if not rows.has(item["beat"]):
			rows[item["beat"]] = []
		rows[item["beat"]].append(item)
	return rows


func _is_big(item: Dictionary) -> bool:
	return item["kind"] != Kind.BLOCK


func _big_of(row: Array) -> bool:
	return row.any(_is_big)


func _bpm_of(beat: float, start_step := 0) -> int:
	return MusicLadder.STEPS[MusicLadder.scheduled_step(start_step, beat)]["bpm"]


func test_2단계는_1박_간격이_기본이고_겹줄과_이동_뒤_동작이_나옴() -> void:
	var one := 0
	var more := 0
	var doubles := 0
	var follows := 0
	for s in SEEDS:
		var rows := _rows(s, 96.0)
		var beats: Array = rows.keys()
		beats.sort()
		for i in range(1, beats.size()):
			if beats[i - 1] < 64.0 or beats[i] >= 96.0:
				continue
			if beats[i] - beats[i - 1] == 1.0:
				one += 1
				if not _big_of(rows[beats[i - 1]]) and _big_of(rows[beats[i]]):
					follows += 1
			else:
				more += 1
			var blocks: Array = rows[beats[i]].filter(func(item): return item["kind"] == Kind.BLOCK)
			doubles += 1 if blocks.size() == 2 else 0
	assert_true(one > more * 3, "1박이 기본: 1박 %d, 그 외 %d" % [one, more])
	assert_true(doubles > 0, "같은 박에 2개")
	assert_true(follows > 0, "레인 이동 → 다음 박 점프/슬라이드")


func test_3단계는_벽이_나오고_반_박은_120BPM에서만() -> void:
	var walls := 0
	var halves := 0
	for s in SEEDS:
		var rows := _rows(s, 400.0)
		var beats: Array = rows.keys()
		beats.sort()
		for i in beats.size():
			var row: Array = rows[beats[i]]
			var blocks: Array = row.filter(func(item): return item["kind"] == Kind.BLOCK)
			if blocks.size() == 2 and _big_of(row):
				assert_true(_bpm_of(beats[i]) >= 120, "벽은 3단계만")
				walls += 1
			if i > 0 and beats[i] - beats[i - 1] == 0.5:
				assert_eq(_bpm_of(beats[i]), 120, "박 %f" % beats[i])
				assert_eq(blocks.size(), 2, "반 박 줄은 두 레인을 막아 이동을 강제")
				halves += 1
			if fmod(beats[i], 1.0) != 0.0:
				assert_eq(_bpm_of(beats[i]), 120, "반 박은 120BPM만")
	assert_true(walls > 0, "벽")
	assert_true(halves > 0, "반 박 2연속")


## 공정성 규칙: 모든 시드, 끝까지
func test_열린_레인이_항상_있고_점프_슬라이드끼리는_2박_이상_벌어짐() -> void:
	for s in range(1, 41):
		for start in [0, 2, 4, 6]:
			var rows := _rows(s, 500.0, start)
			var last_big := -INF
			var beats: Array = rows.keys()
			beats.sort()
			for beat: float in beats:
				var blocked := {}
				for item: Dictionary in rows[beat]:
					assert_false(blocked.has(item["lane"]) and item["kind"] == Kind.BLOCK, "한 레인에 기둥 둘")
					if item["kind"] == Kind.BLOCK:
						blocked[item["lane"]] = true
				assert_true(blocked.size() < RunLogic.LANE_COUNT, "박 %f 세 레인이 모두 막힘" % beat)
				assert_true(rows[beat].filter(_is_big).size() <= 1, "한 박에 동작은 하나")
				if _big_of(rows[beat]):
					assert_true(beat - last_big >= BeatPattern.GAP_AFTER_BIG, "시드 %d 박 %f 앞 동작 %f" % [s, beat, last_big])
					last_big = beat


func test_반복이_지나도_같은_구조() -> void:
	assert_true(BeatPattern.is_intro(0))
	assert_true(BeatPattern.is_intro(31))
	assert_false(BeatPattern.is_intro(32))
	assert_false(BeatPattern.is_intro(63))
	assert_true(BeatPattern.is_intro(64))


## 사람 입력 간격(0.28초)만 쓰는 완벽한 자동 플레이어가 부딪히지 않으면 풀 수 없는 패턴이 없다는 증거다.
func test_완벽한_자동_플레이어가_시드_5개_4분_충돌_없음() -> void:
	for s in [11, 143, 2024, 7777, 90001]:
		var result := RunSim.run(s, "perfect", 240.0)
		assert_true(result["hit"].is_empty(), "시드 %d: %.1f초에 충돌" % [s, result["time"]])
		assert_true(result["min_gap"] >= 0.28 - 0.001, "입력 간격 %f" % result["min_gap"])
		assert_eq(result["ladder"].segments[-1]["step"], MusicLadder.STEPS.size() - 1, "130까지 오름")


func test_모든_시작_BPM과_더_많은_시드에서_풀림() -> void:
	for s in range(1, 21):
		for start in MusicLadder.STEPS.size():
			var result := RunSim.run(s, "perfect", 70.0, start)
			assert_true(result["hit"].is_empty(), "시드 %d 시작 %d: %.1f초 %s" % [s, MusicLadder.STEPS[start]["bpm"], result["time"], str(result["hit"])])


func test_사람_모델은_중앙값_45에서_90초_25퍼센트가_1단계를_넘김() -> void:
	var times := []
	for s in range(1, 51):
		times.append(RunSim.run(s, HumanPlayer.new(s), 600.0)["time"])
	times.sort()
	var median: float = times[24]
	var quarter: float = times[12]
	var stage_one: float = MusicLadder.span_time(0) + MusicLadder.span_time(1)
	assert_true(median >= 45.0 and median <= 90.0, "중앙값 %f" % median)
	assert_true(quarter > stage_one, "25%% %f, 1단계 끝 %f" % [quarter, stage_one])


func test_늦어서_길이_없어도_열린_레인을_돌려줌() -> void:
	var rows := [{"beat": 8.0, "eta": 0.05, "lanes": {0: Kind.BLOCK, 1: Kind.BLOCK}}]
	assert_eq(AutoPlayer.best_path(rows, 0), [2] as Array[int], "한 칸 안에 길이 없어도 멈추지 않음")
	assert_eq(AutoPlayer.best_path(rows, 2), [2] as Array[int], "이미 열린 레인이면 그대로")


func test_사람_모델은_반응_지연을_지킴() -> void:
	var human := HumanPlayer.new(5)
	var delays := []
	for i in 2000:
		delays.append(human._delay())
	var late := delays.filter(func(d): return d > 0.33 + 0.0001).size()
	for d: float in delays:
		assert_true(d >= 0.17 and d <= 0.48 + 0.0001, "지연 %f" % d)
	assert_true(late >= 2 and late <= 60, "1%% 안팎으로 늦음: %d" % late)
	var seeded := HumanPlayer.new(5)
	assert_eq(seeded._delay(), delays[0], "시드 고정")


## 130BPM에서도 동작 사이 2박이 동작 시간보다 길어야 연달아 피할 수 있다.
func test_130BPM의_2박이_점프와_슬라이드보다_김() -> void:
	var two_beats := MusicLadder.beat_time(MusicLadder.STEPS.size() - 1) * BeatPattern.GAP_AFTER_BIG
	assert_true(absf(two_beats - 0.923) < 0.001)
	assert_true(two_beats > PlayerAction.SLIDE_TIME and two_beats > PlayerAction.JUMP_TIME)
