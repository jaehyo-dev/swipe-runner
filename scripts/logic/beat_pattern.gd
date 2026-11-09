class_name BeatPattern
extends RefCounted
## 음악 구조와 편곡 단계에 맞춘 장애물 순서 (자동 테스트 대상). 박 번호는 음악 처음부터 센다. 반 박은 x.5.
## 1단계(원본): 앞 8마디 2박마다·레인 이동 위주, 뒤 8마디 1~2박마다·세 동작 골고루. 앞 8마디의 뒤 4마디에 1박 간격이 가끔.
## 2단계(A): 1박 간격이 기본. 같은 박에 2개(한 레인만 열림), 레인 이동 → 다음 박 점프/슬라이드.
## 3단계(B): 2단계 + 벽(두 레인 기둥 + 열린 레인에 턱·막대), 120BPM에서만 반 박 간격 레인 이동 2연속.
## 공정성: _path는 "이 순서를 풀 수 있는 레인"의 증거다. 줄마다 이 레인에서 한 칸 안에 열린 곳을 둔다.

const INTRO_BARS := 8
## 1단계: 점프·슬라이드가 나올 확률: 앞 8마디, 앞 8마디 마디 첫 박, 뒤 8마디, 뒤 8마디 마디 첫 박
const BIG_INTRO := 0.2
const BIG_INTRO_BAR_START := 0.5
const BIG_MELODY := 2.0 / 3.0
const BIG_MELODY_BAR_START := 0.8
## 점프·슬라이드 다음 점프·슬라이드까지 비우는 박 수 (130BPM 0.92초 > 슬라이드 0.65초). 1단계는 다음 장애물 전체에 적용한다.
const GAP_AFTER_BIG := 2
## 1단계 앞 8마디 안의 뒤 4마디: 기둥 다음 1박 간격이 나올 확률
const INTRO_BACK_BARS := 4
const INTRO_ONE_BEAT := 0.25
## 편곡 단계(1: A, 2: B)별 비율. 사람 모델로 조절한다 (review/v0.5.0/difficulty.md에 기록)
const DOUBLE := {1: 0.60, 2: 0.70}      # 같은 박에 기둥 2개
const FOLLOW_BIG := {1: 0.55, 2: 0.55}  # 기둥 줄 다음 박에, 열린 레인으로 점프·슬라이드
const SINGLE_BIG := {1: 0.25, 2: 0.25}  # 혼자 나오는 점프·슬라이드
const ONE_BEAT := {1: 0.90, 2: 1.0}    # 다음 줄이 1박 뒤일 확률 (나머지는 2박)
const WALL := 0.35        # 3단계: 벽 (앞을 2박 비워 읽을 시간을 준다)
const ZIGZAG := 0.10      # 120BPM: 반 박 간격 레인 이동 2연속
const ZIGZAG_BPM := 120
const ZIGZAG_GAP := 0.5   # 반 박

## 다음 줄이 도착할 박
var beat := 0.0

var _rng := RandomNumberGenerator.new()
var _start_step := 0
var _queue: Array[Dictionary] = []  # 만든 줄의 장애물들, 하나씩 꺼낸다
var _path := RunLogic.START_LANE    # 풀 수 있는 레인의 증거
var _last_big := -INF               # 마지막 점프·슬라이드의 박
var _last_was_block := false        # 바로 앞 줄이 기둥 줄이었나


func _init(seed_value: int, first_beat: int, start_step := 0) -> void:
	_rng.seed = seed_value
	beat = first_beat
	_start_step = start_step


static func is_intro(at_beat: float) -> bool:
	return fposmod(at_beat, BeatClock.BEATS_PER_BAR * BeatClock.LOOP_BARS) < BeatClock.BEATS_PER_BAR * INTRO_BARS


## 앞 8마디 안의 뒤 4마디인가
static func is_intro_back(at_beat: float) -> bool:
	return is_intro(at_beat) and fposmod(at_beat, BeatClock.BEATS_PER_BAR * BeatClock.LOOP_BARS) >= BeatClock.BEATS_PER_BAR * (INTRO_BARS - INTRO_BACK_BARS)


## 다음 장애물 {beat, lane, kind}를 돌려준다. 같은 박에 여러 개면 차례로 나온다.
func next() -> Dictionary:
	if _queue.is_empty():
		var step := MusicLadder.scheduled_step(_start_step, beat)
		var stage: int = MusicLadder.STEPS[step]["stage"]
		if stage == 0:
			_original_row()
		else:
			_drive_row(stage, step)
	return _queue.pop_front()


func _add(at_beat: float, lane: int, kind: ObstacleField.Kind) -> void:
	_queue.append({"beat": at_beat, "lane": lane, "kind": kind})


func _random_big() -> ObstacleField.Kind:
	return ObstacleField.Kind.LOW if _rng.randf() < 0.5 else ObstacleField.Kind.HIGH


## _path에서 한 칸 안의 레인을 무작위로
func _near_path() -> int:
	return clampi(_path + _rng.randi_range(-1, 1), 0, RunLogic.LANE_COUNT - 1)


## _path가 lane에 막혔으면 옆 레인으로 비킨다
func _step_aside(lane: int) -> void:
	if lane == _path:
		_path = 1 if _path != 1 else (0 if _rng.randf() < 0.5 else 2)


## 1단계 줄 하나
func _original_row() -> void:
	var kind := _pick_original_kind()
	var lane := _rng.randi_range(0, RunLogic.LANE_COUNT - 1)
	_add(beat, lane, kind)
	var big := kind != ObstacleField.Kind.BLOCK
	if big:
		_last_big = beat
	else:
		_step_aside(lane)
	_last_was_block = not big
	var gap: float
	if big:
		gap = GAP_AFTER_BIG
	elif is_intro_back(beat):
		gap = 1 if _rng.randf() < INTRO_ONE_BEAT else 2
	elif is_intro(beat):
		gap = 2
	else:
		gap = _rng.randi_range(1, 2)
	beat += gap
	if is_intro(beat) and not is_intro_back(beat) and fmod(beat, 2.0) == 1.0:  # 앞 8마디의 앞 4마디는 2박 격자에 다시 맞춘다
		beat += 1


func _pick_original_kind() -> ObstacleField.Kind:
	var bar_start := fmod(beat, BeatClock.BEATS_PER_BAR) == 0.0
	var big: float
	if is_intro(beat):
		big = BIG_INTRO_BAR_START if bar_start else BIG_INTRO
	else:
		big = BIG_MELODY_BAR_START if bar_start else BIG_MELODY
	return _random_big() if _rng.randf() < big else ObstacleField.Kind.BLOCK


## 2·3단계 줄 하나
func _drive_row(stage: int, step: int) -> void:
	var can_big: bool = beat - _last_big >= GAP_AFTER_BIG
	var roll := _rng.randf()
	if stage == 2 and can_big and _rng.randf() < WALL:
		_wall_row()
	elif MusicLadder.STEPS[step]["bpm"] == ZIGZAG_BPM and _rng.randf() < ZIGZAG:
		_zigzag_rows()
	elif can_big and _last_was_block and roll < FOLLOW_BIG[stage]:
		_big_row(_path)
	elif can_big and roll < SINGLE_BIG[stage]:
		_big_row(_rng.randi_range(0, RunLogic.LANE_COUNT - 1))
	elif _rng.randf() < DOUBLE[stage]:
		_double_row(beat, _near_path())
		_last_was_block = true
		beat += _drive_gap(stage)
	else:
		var lane := _rng.randi_range(0, RunLogic.LANE_COUNT - 1)
		_add(beat, lane, ObstacleField.Kind.BLOCK)
		_step_aside(lane)
		_last_was_block = true
		beat += _drive_gap(stage)


func _drive_gap(stage: int) -> int:
	return 1 if _rng.randf() < ONE_BEAT[stage] else 2


func _big_row(lane: int) -> void:
	_add(beat, lane, _random_big())
	_last_big = beat
	_last_was_block = false
	beat += 1


## 열린 레인 open 하나만 남기고 기둥 2개
func _double_row(at_beat: float, open: int) -> void:
	for lane in RunLogic.LANE_COUNT:
		if lane != open:
			_add(at_beat, lane, ObstacleField.Kind.BLOCK)
	_path = open


## 벽: 앞을 한 박 더 비워 읽을 시간을 주고, 두 레인을 기둥으로 막고 열린 레인에 턱이나 막대
func _wall_row() -> void:
	beat += 1
	var open := _near_path()
	_double_row(beat, open)
	_add(beat, open, _random_big())
	_last_big = beat
	_last_was_block = false
	beat += GAP_AFTER_BIG


## 반 박 간격으로 열린 레인이 옆으로 옮겨 가는 기둥 두 줄: 레인 이동을 연달아 두 번
func _zigzag_rows() -> void:
	var first := _near_path()
	_double_row(beat, first)
	var second := 1 if first != 1 else (0 if _rng.randf() < 0.5 else 2)
	_double_row(beat + ZIGZAG_GAP, second)
	_last_was_block = true
	beat += 2
