class_name OrbTrail
extends RefCounted
## 빛 방울 줄 배치 (화면과 분리, 자동 테스트 대상). 값은 data/score.json.
## 방울 줄 = 반 박 간격 방울 4~8개. 줄의 레인 순서를 무작위로 몇 개 만들어 보고, 그 길을 따라가는 '기준 플레이어'를
## 실제 판정(PlayerAction, 레인 이동 곡선)으로 달려 본다. 부딪히지 않고 입력 간격(0.22초)을 지킨 후보만 쓰고,
## 방울은 기준 플레이어의 몸 가운데가 그 박에 있는 자리에 놓는다. 그래서 모든 방울 줄은 정상 동작으로 다 먹을 수 있다.
##   레인 이동 경로: 옮기는 방울은 두 레인 사이(이동 중 몸 자리)
##   턱 위 포물선: 턱 레인을 지나면 기준 점프(꼭대기가 턱에)의 궤적
##   막대 아래: 막대 레인을 지나면 기준 슬라이드의 낮은 몸 가운데
## 후보 중 장애물 옆·동작·이동이 많은 '위험한' 길을 고른다: 안전한 길만 고르면 일부를 놓친다.
## 장애물 패턴(BeatPattern)과 따로 무작위 값을 써서 장애물 배치는 v0.7.0과 같다.

const SLOT := 0.5          # 방울 간격(박)
const PICK_X := 0.6        # 먹기 범위: 가로 (몸 반폭 0.5 + 방울 반지름 정도)
const PICK_Z := 0.6        # 앞뒤
const PICK_PAD := 0.3      # 위아래: 몸 아래 끝 ~ 위 끝에서 이만큼 더
const BODY_H := 0.8        # Runner.BODY_HEIGHT
const LEAD := 1.0          # 첫 방울 이 박 전부터 첫 레인에 서 있다고 보고 달려 본다 (그 전 장애물은 보통 플레이)
const TAIL := 1.0          # 마지막 방울 뒤 이 박까지 같은 레인에서 달려 본다
const TRIES := 16          # 줄마다 만들어 보는 후보 수
const DT_MAX := 1.0 / 60.0

var next_beat := float(ObstacleField.FIRST_BEAT)  # 다음 줄을 놓기 시작할 수 있는 박
var _rng := RandomNumberGenerator.new()
var _start_step := 0
var _next_id := 0
var _pending := {}  # 계획 중인 줄 {s0, end, step, candidates, next}


func _init(seed_value: int, start_step := 0) -> void:
	_rng.seed = hash([seed_value, "orbs"])
	_start_step = start_step


## 이번 줄이 쓰는 장애물 박의 끝: ObstacleField는 이 박까지 패턴을 꺼내 둔 뒤 work를 부른다
func horizon() -> float:
	return next_beat + data_max_orbs() * SLOT + TAIL + 1.0


static func data_max_orbs() -> int:
	return ScoreBoard.data()["trail_orbs"][1]


## 방울이 주인공 몸에 닿았는가. dx, dz: 가로·앞뒤 거리, height: 뜬 높이, crouch: 슬라이드로 낮아진 정도
static func touches(orb_y: float, dx: float, dz: float, height: float, crouch: float) -> bool:
	if absf(dx) > PICK_X or absf(dz) > PICK_Z:
		return false
	return orb_y >= height - PICK_PAD and orb_y <= height + body_height(crouch) + PICK_PAD


static func body_height(crouch: float) -> float:
	return BODY_H * (1.0 - crouch * (1.0 - PlayerAction.CROUCH_SCALE))


## 줄 계획을 한 걸음 진행한다: 후보 하나만 달려 본다 (여러 후보의 계산이 한 프레임에 몰리지 않게). obstacles: 지금까지 꺼낸 장애물 {beat, lane, kind} (horizon까지).
## 줄이 정해지면 {id, lane0, start, inputs: [[박, 방향]], orbs: [{beat, x, y, lane, trail, index}]}, 아직이거나 이 자리를 포기했으면 빈 값 (다음 걸음에서 이어서)
func work(obstacles: Array) -> Dictionary:
	if _pending.is_empty() and not _begin(obstacles):
		return {}
	var p := _pending
	var lanes: Array[int] = p["candidates"][p["next"]][1]
	p["next"] += 1
	var best := simulate(lanes, p["s0"], p["step"], obstacles)
	if best.is_empty():
		if p["next"] >= p["candidates"].size():
			_pending = {}
			next_beat = p["s0"] + SLOT  # 이 자리는 포기하고 반 박 뒤에서 다시
		return {}
	_pending = {}
	best["id"] = _next_id
	for orb: Dictionary in best["orbs"]:
		orb["trail"] = _next_id
	_next_id += 1
	var d := ScoreBoard.data()
	next_beat = p["end"] + SLOT + _rng.randi_range(d["trail_gap"][0], d["trail_gap"][1])
	return best


## 새 줄의 자리·개수·후보(위험한 것부터)를 정한다. 4마디 경계를 걸치면 false
func _begin(obstacles: Array) -> bool:
	var d := ScoreBoard.data()
	var s0 := ceilf(next_beat / SLOT) * SLOT
	var count := _rng.randi_range(d["trail_orbs"][0], d["trail_orbs"][1])
	var end := s0 + (count - 1) * SLOT
	# shortcut: 줄 안에서 템포가 일정하다고 보고 계산한다. 4마디 경계(템포·속도가 바뀜)를 걸치는 줄은 내지 않는다.
	var span := MusicLadder.STEP_BEATS
	if floori((s0 - LEAD) / span) != floori((end + TAIL) / span):
		next_beat = floorf((end + TAIL) / span) * span + LEAD
		return false
	var candidates: Array = []
	for i in TRIES:
		var lanes := _random_lanes(count)
		candidates.append([_risk(lanes, s0, obstacles) + _rng.randf() * 0.5, lanes])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	_pending = {"s0": s0, "end": end, "step": MusicLadder.scheduled_step(_start_step, s0), "candidates": candidates, "next": 0}
	return true


## 방울마다 레인. 옮기는 방울은 -1 - 도착 레인(음수)로 표시: 앞뒤 방울 사이 이동 중의 자리다.
func _random_lanes(count: int) -> Array[int]:
	var rate: float = ScoreBoard.data()["move_rate"]
	var lane := _rng.randi_range(0, RunLogic.LANE_COUNT - 1)
	var lanes: Array[int] = [lane]
	var k := 1
	while k < count:
		if k + 1 < count and _rng.randf() < rate:
			var dir := (-1 if _rng.randf() < 0.5 else 1) if lane == 1 else (1 if lane == 0 else -1)
			lane += dir
			lanes.append(-1 - lane)
			lanes.append(lane)
			k += 2
		else:
			lanes.append(lane)
			k += 1
	return lanes


static func _lane_of(code: int) -> int:
	return code if code >= 0 else -1 - code


## 위험 점수: 옆 레인에 장애물이 있는 방울, 턱·막대를 지나는 방울, 옮기는 방울이 많을수록 높다
static func _risk(lanes: Array[int], s0: float, obstacles: Array) -> float:
	var score := 0.0
	for k in lanes.size():
		var beat := s0 + k * SLOT
		var lane := _lane_of(lanes[k])
		if lanes[k] < 0:
			score += 1.0
		for item: Dictionary in obstacles:
			if item["beat"] != beat:
				continue
			if item["lane"] == lane:
				score += 2.0
			elif absi(item["lane"] - lane) == 1:
				score += 1.0
	return score


## 기준 플레이어로 달려 본다. 부딪히거나 입력이 너무 붙으면 빈 값. 성공하면 입력과 방울 자리.
## 레인 이동은 옮기는 방울 박에 몸이 두 레인 가운데 오도록, 점프는 꼭대기가, 슬라이드는 가운데가 장애물 박에 오도록 입력한다.
## 입력이 한 프레임 이르거나 늦어도 부딪히지 않고 방울을 다 먹어야 통과: 사람 손과 프레임 격자의 오차를 견딘다.
static func simulate(lanes: Array[int], s0: float, step: int, obstacles: Array) -> Dictionary:
	var bt := MusicLadder.beat_time(step)
	var speed: float = MusicLadder.info(step)["speed"]
	var count := lanes.size()
	var end := s0 + (count - 1) * SLOT
	var t0 := -LEAD * bt - PlayerAction.SLIDE_TIME - 0.1
	var t1 := (end - s0 + TAIL) * bt
	var inputs: Array = []  # [시각(s0 = 0초), 방향]
	for k in count:
		if lanes[k] < 0:
			var dir := SwipeDetector.Dir.LEFT if _lane_of(lanes[k]) < _lane_of(lanes[k - 1]) else SwipeDetector.Dir.RIGHT
			inputs.append([k * SLOT * bt - Runner.MOVE_TIME * 0.5, dir])
	var near: Array = []  # 이 창에서 지나가는 장애물 [도착 시각, 레인, 종류]
	for item: Dictionary in obstacles:
		var at: float = (item["beat"] - s0) * bt
		if item["beat"] < s0 - LEAD or at > t1 + PlayerAction.HIT_Z / speed:
			continue  # 그보다 앞의 장애물은 보통 플레이: 첫 방울 LEAD박 전까지 첫 레인에 오면 된다
		near.append([at, item["lane"], item["kind"]])
		var k := clampi(roundi((item["beat"] - s0) / SLOT), 0, count - 1)
		if lanes[k] < 0:
			if item["lane"] == _lane_of(lanes[k]) or item["lane"] == _lane_of(lanes[k - 1]):
				return {}  # 옮기는 중에 두 레인 사이로 스치는 길은 프레임 격자에 따라 갈린다
			continue
		if item["lane"] != lanes[k]:
			continue
		match item["kind"]:
			ObstacleField.Kind.LOW:
				inputs.append([at - PlayerAction.JUMP_TIME * 0.5, SwipeDetector.Dir.UP])
			ObstacleField.Kind.HIGH:
				inputs.append([at - PlayerAction.SLIDE_TIME * 0.5, SwipeDetector.Dir.DOWN])
			_:
				return {}
	inputs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in inputs.size():
		if inputs[i][0] < t0 or (i > 0 and inputs[i][0] - inputs[i - 1][0] < BeatPattern.MIN_INPUT_GAP):
			return {}
	var orbs := _run(lanes, s0, bt, speed, near, inputs, t0, t1, 0.0, [])
	if orbs.is_empty():
		return {}
	for offset in [-DT_MAX, DT_MAX]:
		if _run(lanes, s0, bt, speed, near, inputs, t0, t1, offset, orbs).is_empty():
			return {}
	var beats_inputs: Array = inputs.map(func(i: Array) -> Array: return [s0 + i[0] / bt, i[1]])
	return {"lane0": _lane_of(lanes[0]), "start": s0, "inputs": beats_inputs, "orbs": orbs}


## 한 번 달린다. check가 비었으면 방울 박마다 몸 가운데를 방울로 남기고, 아니면 그 방울을 다 먹는지 본다.
## 실패하면 빈 배열. offset: 모든 입력을 이만큼 늦춘다 (음수면 이르게)
static func _run(lanes: Array[int], s0: float, bt: float, speed: float, near: Array, inputs: Array, t0: float, t1: float, offset: float, check: Array[Dictionary]) -> Array[Dictionary]:
	var count := lanes.size()
	# 방울 박이 프레임 격자에 오도록 프레임 시간을 맞춘다
	var per_slot := ceili(SLOT * bt / DT_MAX)
	var dt := SLOT * bt / per_slot
	var first := floori(t0 / dt)
	var last := ceili(t1 / dt)
	var action := PlayerAction.new()
	var lane := _lane_of(lanes[0])
	var x := RunLogic.lane_x(lane)
	var from_x := x
	var move_t := Runner.MOVE_TIME
	var next_input := 0
	var orbs: Array[Dictionary] = []
	var taken := {}
	var lo := 0
	for f in range(first, last + 1):
		var t := f * dt
		if f > first:
			action.step(dt)
		move_t = minf(move_t + dt, Runner.MOVE_TIME)
		x = lerpf(from_x, RunLogic.lane_x(lane), (1.0 - cos(PI * move_t / Runner.MOVE_TIME)) * 0.5)
		while lo < near.size() and (t - near[lo][0]) * speed - dt * speed > PlayerAction.HIT_Z:
			lo += 1  # 이미 지나간 장애물은 다시 보지 않는다 (near는 도착 순서)
		for i in range(lo, near.size()):
			var o: Array = near[i]
			var z: float = (t - o[0]) * speed
			if z < -PlayerAction.HIT_Z:
				break  # 뒤의 것은 더 멀다
			if z < -PlayerAction.HIT_Z or z - dt * speed > PlayerAction.HIT_Z:
				continue  # 판정 폭 밖 (앞이거나 지난 프레임에 이미 지나감)
			if z > PlayerAction.HIT_Z and z - dt * speed >= -PlayerAction.HIT_Z:
				continue  # 지난 프레임에 판정 폭 안에서 이미 판정했다. 통째로 건너뛰었으면 0으로 판정 (PlayerAction.swept_dz)
			if PlayerAction.hits(o[2], x - RunLogic.lane_x(o[1]), minf(z, 0.0) if z > PlayerAction.HIT_Z else z, action.height(), action.is_ducking()):
				return []
		if check.is_empty():
			if f >= 0 and f % per_slot == 0 and f / per_slot < count:
				var k := f / per_slot
				var y := action.height() + body_height(action.crouch()) * 0.5
				orbs.append({"beat": s0 + k * SLOT, "x": x, "y": y, "lane": _lane_of(lanes[k]), "index": k})
		else:
			for k in check.size():
				var dz: float = (t - (check[k]["beat"] - s0) * bt) * speed
				if OrbTrail.touches(check[k]["y"], x - check[k]["x"], dz, action.height(), action.crouch()):
					taken[k] = true
		while next_input < inputs.size() and inputs[next_input][0] + offset <= t + dt * 0.5:
			match inputs[next_input][1]:
				SwipeDetector.Dir.LEFT, SwipeDetector.Dir.RIGHT:
					from_x = x
					lane += -1 if inputs[next_input][1] == SwipeDetector.Dir.LEFT else 1
					move_t = 0.0
				SwipeDetector.Dir.UP:
					action.jump()
				SwipeDetector.Dir.DOWN:
					action.slide()
			next_input += 1
	if not check.is_empty():
		return check if taken.size() == check.size() else []
	return orbs
