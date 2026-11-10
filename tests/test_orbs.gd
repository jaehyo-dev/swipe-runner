extends TestCase
## 빛 방울 배치·공정성, 점수·콤보·배수·아슬아슬 테스트 (v0.8.0)

const Kind := ObstacleField.Kind
const PRESSURE_END := 13 * 32.0  # 압박 단계 0~12 끝 박
const DT := 1.0 / 60.0


## seed의 장애물과 방울 줄을 압박 단계 12 끝까지 만들고, 그 판의 사다리(경계 포함)와 함께 돌려준다
static func _field_until(seed_value: int, end_beat: float) -> Dictionary:
	var ladder := MusicLadder.new()
	var field := ObstacleField.new(seed_value, ladder)
	field.keep_trails = true
	var items: Array[Dictionary] = []
	var t := 0.0
	while ladder.beat_at(t) < end_beat + 4.0:
		t += DT
		ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
		items.append_array(field.step(ladder.distance_at(t), ladder.spawn_distance_at(t))["spawned"])
	return {"ladder": ladder, "items": items, "trails": field.trails.filter(func(tr): return tr["orbs"][-1]["beat"] < end_beat)}


## 방울 줄 하나를 정상 동작으로 다 먹을 수 있는지 따로 달려 본다 (배치 쪽 계산과 다른 방법: 실제 사다리의 시간, 방울과 맞지 않는 1/60초 프레임).
## 첫 방울 LEAD 박 전부터 첫 레인에 서서(그보다 앞의 장애물은 보통 플레이), 줄에 적힌 입력만 낸다. 결과: 빈 문자열이면 성공, 아니면 실패 이유
static func check_trail(trail: Dictionary, items: Array, ladder: MusicLadder) -> String:
	var orbs: Array = trail["orbs"]
	var t := ladder.time_of_beat(trail["start"] - OrbTrail.LEAD) - PlayerAction.SLIDE_TIME
	var t_end := ladder.time_of_beat(orbs[-1]["beat"] + OrbTrail.TAIL)
	var inputs: Array = trail["inputs"].map(func(i: Array) -> Array: return [ladder.time_of_beat(i[0]), i[1]])
	var last_input := -INF
	for i: Array in inputs:
		if i[0] - last_input < BeatPattern.MIN_INPUT_GAP - 0.001:
			return "입력 간격 %.3f" % (i[0] - last_input)
		last_input = i[0]
	var near := items.filter(func(it): return it["beat"] >= trail["start"] - OrbTrail.LEAD and it["beat"] <= orbs[-1]["beat"] + OrbTrail.TAIL + 0.5)
	var action := PlayerAction.new()
	var lane: int = trail["lane0"]
	var x := RunLogic.lane_x(lane)
	var from_x := x
	var move_t := Runner.MOVE_TIME
	var taken := {}
	var prev := {}
	var next := 0
	while t < t_end:
		t += DT
		action.step(DT)
		move_t = minf(move_t + DT, Runner.MOVE_TIME)
		x = lerpf(from_x, RunLogic.lane_x(lane), (1.0 - cos(PI * move_t / Runner.MOVE_TIME)) * 0.5)
		var now := ladder.distance_at(t)
		for it: Dictionary in near:
			var z := now - ladder.distance_of_beat(it["beat"])
			var dz := PlayerAction.swept_dz({"z": z, "prev_z": prev.get(it, z)})
			prev[it] = z
			if PlayerAction.hits(it["kind"], x - RunLogic.lane_x(it["lane"]), dz, action.height(), action.is_ducking()):
				return "박 %.1f 레인 %d %s에 부딪힘" % [it["beat"], it["lane"], Kind.keys()[it["kind"]]]
		for k in orbs.size():
			var o: Dictionary = orbs[k]
			var z := now - ladder.distance_of_beat(o["beat"])
			var dz := PlayerAction.swept_dz({"z": z, "prev_z": prev.get(o, z)})
			prev[o] = z
			if OrbTrail.touches(o["y"], x - o["x"], dz, action.height(), action.crouch()):
				taken[k] = true
			elif z > OrbTrail.PICK_Z and not taken.has(k):
				return "방울 %d (박 %.1f) 놓침" % [k, o["beat"]]
		while next < inputs.size() and inputs[next][0] <= t:
			match inputs[next][1]:
				SwipeDetector.Dir.LEFT, SwipeDetector.Dir.RIGHT:
					from_x = x
					lane += -1 if inputs[next][1] == SwipeDetector.Dir.LEFT else 1
					move_t = 0.0
				SwipeDetector.Dir.UP:
					action.jump()
				SwipeDetector.Dir.DOWN:
					action.slide()
			next += 1
	return "" if taken.size() == orbs.size() else "다 먹지 못함 %d/%d" % [taken.size(), orbs.size()]


func test_모든_방울_줄을_정상_동작으로_다_먹을_수_있음_시드_40_압박_0에서_12() -> void:
	var total := 0
	var fails := 0
	for s in range(1, 41):
		var run := _field_until(s, PRESSURE_END)
		assert_true(run["trails"].size() > 40, "시드 %d 줄 수 %d" % [s, run["trails"].size()])
		for trail: Dictionary in run["trails"]:
			total += 1
			var why := check_trail(trail, run["items"], run["ladder"])
			if not why.is_empty():
				fails += 1
				if fails <= 5:
					assert_true(false, "시드 %d 줄 박 %.1f: %s" % [s, trail["start"], why])
	assert_eq(fails, 0, "실패한 줄 / 전체 %d" % total)


func test_방울_줄은_4에서_8개_반_박_간격이고_장애물_판정_안에_없음() -> void:
	var run := _field_until(5, PRESSURE_END)
	for trail: Dictionary in run["trails"]:
		var orbs: Array = trail["orbs"]
		assert_true(orbs.size() >= 4 and orbs.size() <= 8, "개수 %d" % orbs.size())
		for k in range(1, orbs.size()):
			assert_eq(orbs[k]["beat"] - orbs[k - 1]["beat"], OrbTrail.SLOT)
		for o: Dictionary in orbs:
			for it: Dictionary in run["items"]:
				if it["beat"] != o["beat"] or absf(RunLogic.lane_x(it["lane"]) - o["x"]) > 0.7:
					continue
				match it["kind"]:
					Kind.BLOCK:
						assert_true(false, "기둥 안 방울 박 %.1f" % o["beat"])
					Kind.LOW:
						assert_true(o["y"] > ObstacleField.LOW_TOP + 0.2, "턱 위 방울 높이 %.2f" % o["y"])
					Kind.HIGH:
						assert_true(o["y"] < ObstacleField.HIGH_BOTTOM - 0.2, "막대 아래 방울 높이 %.2f" % o["y"])


func test_네_가지_모양이_다_나옴_레인_이동_턱_위_막대_아래_장애물_옆() -> void:
	var shapes := {}
	for s in range(1, 6):
		var run := _field_until(s, 200.0)
		for trail: Dictionary in run["trails"]:
			for o: Dictionary in trail["orbs"]:
				if absf(o["x"] - RunLogic.lane_x(o["lane"])) > 0.3:
					shapes["이동"] = true
				if o["y"] > 1.0:
					shapes["턱 위"] = true
				if o["y"] < 0.3:
					shapes["막대 아래"] = true
				for it: Dictionary in run["items"]:
					if it["beat"] == o["beat"] and absi(it["lane"] - o["lane"]) == 1:
						shapes["옆"] = true
	assert_eq(shapes.size(), 4, str(shapes.keys()))


func test_같은_시드는_같은_방울이고_장애물은_패턴과_같음() -> void:
	var a := _field_until(9, 100.0)
	var b := _field_until(9, 100.0)
	assert_eq(str(a["trails"]), str(b["trails"]))
	var pattern := BeatPattern.new(9, ObstacleField.FIRST_BEAT)
	for it: Dictionary in a["items"]:
		var want := pattern.next()
		assert_eq([it["beat"], it["lane"], it["kind"]], [want["beat"], want["lane"], want["kind"]])


func test_먹기_범위는_몸_높이를_따라감() -> void:
	assert_true(OrbTrail.touches(0.4, 0.0, 0.0, 0.0, 0.0))
	assert_false(OrbTrail.touches(0.4, 0.7, 0.0, 0.0, 0.0), "옆 레인")
	assert_false(OrbTrail.touches(0.4, 0.0, 0.7, 0.0, 0.0), "앞뒤")
	assert_false(OrbTrail.touches(2.0, 0.0, 0.0, 0.0, 0.0), "서 있으면 공중 방울 못 먹음")
	assert_true(OrbTrail.touches(2.0, 0.0, 0.0, 1.5, 0.0), "뛰면 먹음")
	assert_false(OrbTrail.touches(0.9, 0.0, 0.0, 0.0, 1.0), "슬라이드 중 높은 방울")


func test_배수표() -> void:
	var want := {0: 1, 9: 1, 10: 2, 19: 2, 20: 3, 34: 3, 35: 4, 54: 4, 55: 5, 84: 5, 85: 6, 115: 7, 145: 8, 400: 8}
	for combo: int in want:
		assert_eq(ScoreBoard.multiplier(combo), want[combo], "콤보 %d" % combo)


func test_점수는_거리와_방울_곱하기_배수() -> void:
	var board := ScoreBoard.new()
	for i in 9:
		assert_eq(board.take_orb(0), 65)
	assert_eq(board.take_orb(0), 130, "10번째 방울은 x2")
	assert_eq(board.points, 715)
	assert_eq(board.total(152.7), 867)
	assert_eq(board.orbs, 10)


func test_놓치면_콤보가_끊기고_줄_안_음높이도_처음으로() -> void:
	var board := ScoreBoard.new()
	board.take_orb(3)
	board.take_orb(3)
	assert_eq(board.trail_streak, 2)
	assert_true(board.miss_orb(), "콤보가 있었으면 끊김")
	assert_false(board.miss_orb(), "이미 0")
	assert_eq(board.combo, 0)
	board.take_orb(3)
	assert_eq(board.trail_streak, 1)
	board.take_orb(4)
	assert_eq(board.trail_streak, 1, "다음 줄은 처음 음")
	assert_eq(board.combo, 2)


func test_PERFECT는_도착_0_16초_안의_입력만() -> void:
	var board := ScoreBoard.new()
	board.note_jump(10.0)
	assert_eq(board.passed(Kind.LOW, 1, 10.15, 1), 100, "0.15초 전 점프")
	assert_eq(board.passed(Kind.LOW, 1, 10.2, 1), 0, "0.2초 전 (v0.8.0에서는 PERFECT)")
	board.note_slide(20.0)
	assert_eq(board.passed(Kind.HIGH, 1, 20.15, 1), 100)
	assert_eq(board.passed(Kind.HIGH, 0, 20.1, 1), 0, "다른 레인 막대는 슬라이드와 상관없음")
	board.note_move(30.0, 1)
	assert_eq(board.passed(Kind.BLOCK, 1, 30.1, 2), 100, "방금 떠난 레인의 기둥")
	assert_eq(board.passed(Kind.BLOCK, 0, 30.1, 2), 0, "멀리 떨어진 레인")
	assert_eq(board.passed(Kind.BLOCK, 2, 30.1, 2), 0, "내 레인")
	assert_eq(board.close, 3)


func test_PERFECT_보너스도_배수를_곱함() -> void:
	var board := ScoreBoard.new()
	for i in 20:
		board.take_orb(0)
	board.note_jump(5.0)
	assert_eq(board.passed(Kind.LOW, 0, 5.1, 0), 300)


## v0.8.1 목표 (시드 50, 중앙값): 욕심쟁이(잘하는 모델 + 방울 쫓기)는 안전 모델(잘하는 모델) 점수의 1.25배 이상이고 버틴 시간은 조금 짧다.
## 도전 모델(잘하는 모델 + 점프·슬라이드를 늦게)은 PERFECT를 더 많이 받고 버틴 시간은 조금 짧다. 안전 모델의 PERFECT는 한 판 평균 10회 이하.
func test_욕심쟁이와_도전_모델은_위험만큼_점수를_더_받음() -> void:
	var med := func(runs: Array, key: String) -> float:
		var v: Array = runs.map(func(r): return float(r[key]))
		v.sort()
		return v[v.size() / 2]
	var runs := {"safe": [], "greedy": [], "dare": []}
	for s in range(1, 51):
		runs["safe"].append(RunSim.run(s, HumanPlayer.new(s, HumanPlayer.GOOD), 600.0))
		runs["greedy"].append(RunSim.run(s, HumanPlayer.new(s, HumanPlayer.GREEDY), 600.0))
		runs["dare"].append(RunSim.run(s, HumanPlayer.new(s, HumanPlayer.DARE), 600.0))
	var perfect := func(key: String) -> float: return runs[key].reduce(func(a, r): return a + r["close"], 0) / float(runs[key].size())
	var safe_time: float = med.call(runs["safe"], "time")
	assert_true(perfect.call("safe") <= 10.0, "안전 모델 PERFECT %.1f" % perfect.call("safe"))
	assert_true(med.call(runs["greedy"], "score") >= med.call(runs["safe"], "score") * 1.25, "점수 %d vs %d" % [med.call(runs["greedy"], "score"), med.call(runs["safe"], "score")])
	for key in ["greedy", "dare"]:
		var t: float = med.call(runs[key], "time")
		assert_true(t < safe_time and t >= safe_time * 0.8, "%s 시간 %.1f vs %.1f" % [key, t, safe_time])
	assert_true(perfect.call("dare") >= perfect.call("safe") * 2.0, "도전 PERFECT %.1f vs %.1f" % [perfect.call("dare"), perfect.call("safe")])
	assert_true(med.call(runs["dare"], "score") > med.call(runs["safe"], "score"), "도전 점수")


## 시간이 크게 건너뛰어(탭 전환) 처리 전에 지워진 방울도 놓친 것으로 센다 (Codex 리뷰)
func test_처리_전에_지워진_방울도_놓침으로_콤보가_끊김() -> void:
	var ladder := MusicLadder.new()
	var field := ObstacleField.new(3, ladder)
	var board := ScoreBoard.new()
	board.combo = 15
	field.step(ladder.distance_at(1.0), ladder.spawn_distance_at(1.0))
	field.step(ladder.distance_at(6.0), ladder.spawn_distance_at(6.0))
	assert_true(field.orbs.size() > 0, "방울이 길 위에 있음")
	var before := field.orbs.size()
	field.step(ladder.distance_at(30.0), 0.0)  # 한 프레임에 24초: 지금 방울은 모두 카메라 뒤
	assert_true(field.skipped_orbs >= before, "지워진 방울 %d" % field.skipped_orbs)
	var result := board.watch(field, 0.0, 0.0, 0.0, 1, 30.0, 15.0)
	assert_true(result["broke"], "콤보 15가 끊김")
	assert_true(board.missed >= before, "놓침 %d" % board.missed)
	assert_eq(field.skipped_orbs, 0, "한 번만 센다")
