class_name HumanPlayer
extends RefCounted
## 사람 흉내 자동 플레이어 (난이도 측정용, 웹 빌드에는 들어가지 않는다).
## 줄이 SEE초 앞까지 오면 반응하고, 반응 지연 뒤에 입력한다. 입력이 여러 개 필요한 줄(옮긴 뒤 점프 등)은 그만큼 일찍 반응한다 (멀리서 보이므로).
## 한 번에 두 줄 앞까지만 보고 레인을 고른다.

const SEE := 0.55           # 줄을 알아채는 순간 (도착까지 남은 시간). 평균 반응 뒤 약 0.3초 앞에서 입력하는 값
const DELAY := 0.25         # 반응 지연
const JITTER := 0.08        # ± 무작위
const LATE_CHANCE := 0.01   # 이 확률로
const LATE := 0.15          # 이만큼 더 늦게 반응
const MIN_GAP := 0.28       # 입력 간격
const LOOK_ROWS := 2        # 내다보는 줄 수
const MAX_EXTRA_INPUTS := 2 # 한 줄에 더 필요할 수 있는 입력 수 (두 칸 이동 + 동작)

var _rng := RandomNumberGenerator.new()
var _handled := {}          # 이미 알아챈 줄의 박
var _queue: Array[Dictionary] = []  # {at, dir}: 낼 입력
var _last_input := -INF
var _plan_lane := -1        # 대기 중인 입력까지 반영한 레인


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func _delay() -> float:
	var delay := DELAY + _rng.randf_range(-JITTER, JITTER)
	if _rng.randf() < LATE_CHANCE:
		delay += LATE
	return delay


## 시각 now에 낼 입력 (SwipeDetector.Dir)
func decide(now: float, items: Array, lane: int, player: PlayerAction, speed: float) -> int:
	if _queue.is_empty():
		_plan_lane = lane
	var rows := AutoPlayer.rows_ahead(items, speed)
	for i in rows.size():
		var row: Dictionary = rows[i]
		if row["eta"] > SEE + MIN_GAP * MAX_EXTRA_INPUTS:
			break
		if _handled.has(row["beat"]):
			continue
		var plan := _inputs(rows.slice(i, i + LOOK_ROWS))
		if row["eta"] > SEE + MIN_GAP * maxi(plan.size() - 1, 0):
			break
		_handled[row["beat"]] = true
		_react(now, plan)
	if _queue.is_empty() or now < _queue[0]["at"]:
		return SwipeDetector.Dir.NONE
	if now - _last_input < MIN_GAP:
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
func _react(now: float, inputs: Array[int]) -> void:
	var at := now + _delay()
	for dir in inputs:
		_queue.append({"at": at, "dir": dir})
		if dir == SwipeDetector.Dir.LEFT:
			_plan_lane -= 1
		elif dir == SwipeDetector.Dir.RIGHT:
			_plan_lane += 1
		at += MIN_GAP
