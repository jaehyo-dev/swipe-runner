class_name HumanPlayer
extends RefCounted
## 사람 흉내 자동 플레이어 (난이도 측정용, 웹 빌드에는 들어가지 않는다).
## 줄이 SEE초 앞까지 오면 반응하고, 반응 지연 뒤에 입력한다. 입력이 여러 개 필요한 줄(옮긴 뒤 점프 등)은 그만큼 일찍 반응한다 (멀리서 보이므로).
## 보통 모델은 두 줄 앞까지, 잘하는 모델은 네 줄 앞까지 보고 레인을 고른다. 안개 속 줄은 모른다 (RunSim이 보이는 줄만 준다): 보인 순간부터 반응 지연이 흐른다.

const SEE := 0.55           # 줄을 알아채는 순간 (도착까지 남은 시간). 평균 반응 뒤 약 0.3초 앞에서 입력하는 값
## delay: 반응 지연, jitter: ± 무작위, late: 이 확률로 LATE만큼 더 늦게 반응, look: 내다보는 줄 수, gap: 입력 간격(초)
## speed_lag: 속도 1당 늘어나는 반응 지연(초). 화면이 빨리 흐를수록 장애물을 알아보는 데 오래 걸린다는 가정 (시작 속도 15 기준)
const NORMAL := {"delay": 0.25, "jitter": 0.08, "late": 0.01, "look": 2, "gap": 0.28, "speed_lag": 0.02}
const GOOD := {"delay": 0.18, "jitter": 0.05, "late": 0.005, "look": 4, "gap": 0.24, "speed_lag": 0.0165}
const LAG_FROM_SPEED := 15.0
const LATE := 0.15
const CLEAR_AHEAD := 0.05   # 앞 줄을 다 지나기 이만큼 전에 움직이기 시작해도 된다 (레인 이동의 앞부분은 아직 제 레인 안이다)
const MAX_EXTRA_INPUTS := 2 # 한 줄에 더 필요할 수 있는 입력 수 (두 칸 이동 + 동작)

var _rng := RandomNumberGenerator.new()
var _model: Dictionary
var _handled := {}          # 이미 알아챈 줄의 박
var _queue: Array[Dictionary] = []  # {at, dir}: 낼 입력
var _last_input := -INF
var _plan_lane := -1        # 대기 중인 입력까지 반영한 레인


func _init(seed_value: int, model := NORMAL) -> void:
	_rng.seed = seed_value
	_model = model


func _delay(speed := LAG_FROM_SPEED) -> float:
	var delay: float = _model["delay"] + _model["speed_lag"] * maxf(speed - LAG_FROM_SPEED, 0.0) + _rng.randf_range(-_model["jitter"], _model["jitter"])
	if _rng.randf() < _model["late"]:
		delay += LATE
	return delay


## 시각 now에 낼 입력 (SwipeDetector.Dir)
func decide(now: float, items: Array, lane: int, player: PlayerAction, speed: float) -> int:
	if _queue.is_empty():
		_plan_lane = lane
	var rows := AutoPlayer.rows_ahead(items, speed)
	for i in rows.size():
		var row: Dictionary = rows[i]
		if row["eta"] > SEE + _model["gap"] * MAX_EXTRA_INPUTS:
			break
		if _handled.has(row["beat"]):
			continue
		var plan := _inputs(rows.slice(i, i + _model["look"]))
		if row["eta"] > SEE + _model["gap"] * maxi(plan.size() - 1, 0):
			break
		_handled[row["beat"]] = true
		# 앞 줄이 아직 지나가지 않았으면 그 줄을 지난 뒤에 옆으로 옮긴다 (사람도 앞 장애물에 몸을 먼저 들이밀지 않는다)
		var wait := 0.0
		if i > 0 and not plan.is_empty() and plan[0] in [SwipeDetector.Dir.LEFT, SwipeDetector.Dir.RIGHT]:
			wait = now + rows[i - 1]["eta"] + (PlayerAction.HIT_Z / speed) - CLEAR_AHEAD
		_react(now, plan, speed, wait)
	if _queue.is_empty() or now < _queue[0]["at"]:
		return SwipeDetector.Dir.NONE
	if now - _last_input < _model["gap"]:
		return SwipeDetector.Dir.NONE  # 손이 아직 못 따라간다
	_last_input = now
	var dir: int = _queue.pop_front()["dir"]
	# 공중에서 또 뛰거나 슬라이드 중 또 미끄러지는 입력은 사람이 내지 않는다
	if (dir == SwipeDetector.Dir.UP and player.is_jumping()) or (dir == SwipeDetector.Dir.DOWN and player.is_sliding()):
		return SwipeDetector.Dir.NONE
	return dir


## 이 줄을 지나려면 낼 입력들: 설 레인을 정하고, 옮긴 뒤 턱·막대면 동작까지
func _inputs(rows: Array) -> Array[int]:
	var lane := _plan_lane
	var target: int = AutoPlayer.best_path(rows, lane)[0]
	var inputs: Array[int] = []
	while target != lane:
		inputs.append(AutoPlayer.move_dir(lane, target))
		lane += signi(target - lane)
	var kind: int = rows[0]["lanes"].get(target, ObstacleField.Kind.BLOCK)
	if kind == ObstacleField.Kind.LOW:
		inputs.append(SwipeDetector.Dir.UP)
	elif kind == ObstacleField.Kind.HIGH:
		inputs.append(SwipeDetector.Dir.DOWN)
	return inputs


## 반응 지연 뒤로 입력을 예약한다. 입력끼리는 사람 입력 간격만큼 벌어진다.
func _react(now: float, inputs: Array[int], speed: float, not_before := 0.0) -> void:
	var at := maxf(now + _delay(speed), not_before)
	for dir in inputs:
		_queue.append({"at": at, "dir": dir})
		if dir == SwipeDetector.Dir.LEFT:
			_plan_lane -= 1
		elif dir == SwipeDetector.Dir.RIGHT:
			_plan_lane += 1
		at += _model["gap"]
