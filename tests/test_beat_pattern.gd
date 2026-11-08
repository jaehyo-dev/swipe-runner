extends TestCase
## 박자 패턴과 공정성 테스트 (시드 고정).

const Kind := ObstacleField.Kind
const SEEDS := [1, 7, 42, 136, 2026]


func _sequence(seed_value: int, count: int, first := 0) -> Array[Dictionary]:
	var pattern := BeatPattern.new(seed_value, first)
	var items: Array[Dictionary] = []
	for i in count:
		items.append(pattern.next())
	return items


func test_첫_박은_항상_마디_첫_박() -> void:
	for t in [0.0, 0.1, 7.3, 38.39, 100.0]:
		var beat := BeatPattern.first_beat(t, 6.67)
		assert_eq(beat % 4, 0, "시각 %f" % t)
		assert_true(beat * BeatClock.BEAT >= t + 6.67, "시각 %f" % t)


func test_간격_규칙_점프_슬라이드_뒤_2박_레인_이동은_1박_이상() -> void:
	for s in SEEDS:
		var items := _sequence(s, 3000)
		for i in range(1, items.size()):
			var gap: int = items[i]["beat"] - items[i - 1]["beat"]
			assert_true(gap >= 1, "1박 이상")
			if items[i - 1]["kind"] != Kind.BLOCK:
				assert_true(gap >= 2, "큰 동작 뒤 박 %d 간격 %d" % [items[i - 1]["beat"], gap])
			assert_true(gap <= 3, "너무 비지 않음 %d" % gap)


func test_앞_8마디는_2박마다_뒤_8마디는_1에서_2박마다() -> void:
	var gaps := {true: {}, false: {}}
	for s in SEEDS:
		var items := _sequence(s, 3000)
		for i in range(1, items.size()):
			var prev: int = items[i - 1]["beat"]
			var now: int = items[i]["beat"]
			if BeatPattern.is_intro(prev) and BeatPattern.is_intro(now):
				assert_eq(now - prev, 2, "앞 8마디 박 %d" % prev)
				assert_eq(now % 2, 0, "2박 격자")
			elif not BeatPattern.is_intro(prev) and not BeatPattern.is_intro(now):
				gaps[false][now - prev] = true
	assert_eq(gaps[false].keys().size(), 2, "뒤 8마디는 1박과 2박이 섞임")


func test_동작_비율_앞은_레인_이동_위주_뒤는_골고루_마디_첫_박엔_큰_동작이_늘어남() -> void:
	var count := {}
	for key in ["intro", "intro_first", "melody", "melody_first"]:
		count[key] = {Kind.BLOCK: 0, Kind.LOW: 0, Kind.HIGH: 0}
	for s in SEEDS:
		for item in _sequence(s, 6000):
			var key: String = "intro" if BeatPattern.is_intro(item["beat"]) else "melody"
			if item["beat"] % 4 == 0:
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
	assert_true(absf(low - high) < (low + high) * 0.1, "점프 %d, 슬라이드 %d" % [low, high])


func test_반복이_지나도_같은_구조() -> void:
	assert_true(BeatPattern.is_intro(0))
	assert_true(BeatPattern.is_intro(31))
	assert_false(BeatPattern.is_intro(32))
	assert_false(BeatPattern.is_intro(63))
	assert_true(BeatPattern.is_intro(64))


func test_한_박에_장애물은_하나뿐이라_세_레인이_동시에_막히지_않음() -> void:
	var seen := {}
	for item in _sequence(5, 3000):
		assert_false(seen.has(item["beat"]), "박 %d" % item["beat"])
		seen[item["beat"]] = true


## 실제 판정·동작 코드로 3분을 달려 본다. 사람이 낼 수 있는 입력만으로 한 번도 부딪히지 않아야 공정하다.
func test_자동_플레이어가_3분_동안_부딪히지_않음() -> void:
	var dt := 1.0 / 60.0
	for s in SEEDS:
		var field := ObstacleField.new(s)
		var player := PlayerAction.new()
		var lane := 1
		var x := RunLogic.lane_x(lane)
		var hits := 0
		var seen := 0
		for frame in int(180.0 / dt):
			seen += field.step(dt)["spawned"].size()
			player.step(dt)
			var dir := AutoPlayer.decide(field.items, lane, player)
			match dir:
				SwipeDetector.Dir.LEFT:
					lane = RunLogic.move_lane(lane, -1)
				SwipeDetector.Dir.RIGHT:
					lane = RunLogic.move_lane(lane, 1)
				SwipeDetector.Dir.UP:
					player.jump()
				SwipeDetector.Dir.DOWN:
					player.slide()
			x = move_toward(x, RunLogic.lane_x(lane), RunLogic.LANE_WIDTH / Runner.MOVE_TIME * dt)
			for item in field.items:
				if PlayerAction.hits(item["kind"], x - RunLogic.lane_x(item["lane"]), item["z"], player.height(), player.is_ducking()):
					hits += 1
					break
		assert_eq(hits, 0, "시드 %d" % s)
		assert_true(seen > 120, "장애물 수 %d" % seen)
