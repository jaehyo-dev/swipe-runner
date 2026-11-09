class_name RunSim
extends RefCounted
## 화면 없이 실제 판정·동작·사다리로 한 판을 달린다 (자동 플레이어 공정성 테스트, 난이도 표). 레인 이동은 runner.gd와 같은 0.18초 사인 곡선.

const DT := 1.0 / 60.0


## player: "perfect" 또는 HumanPlayer. 결과 {time, hit: 부딪힌 장애물(없으면 빈 값), step: 그때 단계, gaps: 최소 입력 간격, ladder}
static func run(seed_value: int, player: Variant, seconds: float, start_step := 0) -> Dictionary:
	var ladder := MusicLadder.new(start_step)
	var field := ObstacleField.new(seed_value, ladder)
	var action := PlayerAction.new()
	var lane := RunLogic.START_LANE
	var x := RunLogic.lane_x(lane)
	var from_x := x
	var move_t := Runner.MOVE_TIME
	var t := 0.0
	var last_input := -INF
	var min_gap := INF
	while t < seconds:
		t += DT
		ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
		field.step(ladder.distance_at(t), ladder.spawn_distance_at(t))
		action.step(DT)
		move_t = minf(move_t + DT, Runner.MOVE_TIME)
		x = lerpf(from_x, RunLogic.lane_x(lane), (1.0 - cos(PI * move_t / Runner.MOVE_TIME)) * 0.5)
		for item in field.items:
			if PlayerAction.hits(item["kind"], x - RunLogic.lane_x(item["lane"]), PlayerAction.swept_dz(item), action.height(), action.is_ducking()):
				return {"time": t, "hit": item, "step": ladder.segment_at(t)["step"], "min_gap": min_gap, "ladder": ladder}
		var speed := ladder.speed_at(t)
		var seen := visible_items(field.items, ladder, t)
		var dir: int
		if player is HumanPlayer:
			dir = player.decide(t, seen, lane, action, speed)
		else:
			dir = AutoPlayer.decide(seen, lane, action, speed, t - last_input)
		if dir == SwipeDetector.Dir.NONE:
			continue
		min_gap = minf(min_gap, t - last_input)
		last_input = t
		match dir:
			SwipeDetector.Dir.LEFT, SwipeDetector.Dir.RIGHT:
				var next := RunLogic.move_lane(lane, -1 if dir == SwipeDetector.Dir.LEFT else 1)
				if next != lane:
					lane = next
					from_x = x
					move_t = 0.0
			SwipeDetector.Dir.UP:
				action.jump()
			SwipeDetector.Dir.DOWN:
				action.slide()
	return {"time": t, "hit": {}, "step": ladder.segment_at(t)["step"], "min_gap": min_gap, "ladder": ladder}


## 플레이어가 알아볼 수 있는 장애물: 안개에서 반쯤 진해진 것까지 (나타나는 0.15초의 가운데)
static func visible_items(items: Array, ladder: MusicLadder, t: float) -> Array:
	var seen_from := (ladder.fog_at(t) + ladder.fog_clear_at(t)) * 0.5
	return items.filter(func(item: Dictionary) -> bool: return -item["z"] <= seen_from)
