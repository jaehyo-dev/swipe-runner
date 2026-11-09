class_name BeatPattern
extends RefCounted
## 음악 구조와 편곡 단계에 맞춘 장애물 순서 (자동 테스트 대상). 박 번호는 음악 처음부터 센다. 반 박은 x.5.
## 줄의 종류
##   기둥 줄: 기둥 1개, 또는 기둥 2개(한 레인만 열림)
##   동작 줄: 턱·막대 1개 / 혼합 겹줄(기둥+턱, 기둥+막대, 턱+막대, 나머지 한 레인은 빈다) / 벽(세 레인을 다 채운다, 앞을 한 박 비운다)
##   특별 줄: 반 박이 입력 간격(0.28초) 이상인 BPM은 반 박 레인 이동 2연속(지그재그), 그보다 빠르면 1박 간격 3연속 콤보
## 맨 위 단계(160BPM)에 도착한 뒤에는 4마디마다 밀도만 오른다 (상한 있음).
## 공정성: _path는 "이 순서를 풀 수 있는 레인"의 증거다. 줄마다 이 레인에서 한 칸 안에 지나갈 곳을 둔다. 턱·막대가 있는 줄끼리는 2박 이상 벌린다.
## 비율은 사람 모델 두 종류로 맞췄다 (review/v0.5.1/difficulty.md).

const Kind := ObstacleField.Kind
## 편곡 단계(0 원본, 1 A, 2 B)별 비율
const ONE_BEAT: Array[float] = [0.55, 0.8, 0.9]  # 다음 줄이 1박 뒤일 확률 (나머지는 2박)
const BIG: Array[float] = [0.5, 0.7, 0.9]     # 허용될 때 동작 줄이 나올 확률
const PAIR: Array[float] = [0.3, 0.55, 0.65]      # 동작 줄 중 혼합 겹줄
const WALL: Array[float] = [0.0, 0.1, 0.2]       # 동작 줄 중 벽
const DOUBLE: Array[float] = [0.1, 0.15, 0.1]     # 기둥 줄 중 기둥 2개
## 줄 읽기: 가운데 레인에 긴 기둥 벽이 이어지다가 한쪽만 열린다. 처음에 맞는 쪽으로 가야 살므로 몇 줄 앞을 읽는 만큼 안전하다.
## 얕은 것(열린 줄이 3~4번째)은 두 줄 앞만 보는 사람에게, 깊은 것(5번째)은 네 줄 앞까지 보는 사람에게 어렵다.
const READ_SHALLOW: Array[float] = [0.0, 0.012, 0.03]
const READ_DEEP_FROM_BPM := 130
const READ_DEEP := 0.011
const DENSITY_READ_DEEP := 0.01
const SPECIAL := 0.05       # 특별 줄이 나올 확률 (BPM에 상관없이 같다)
const SPECIAL_FROM := 12.0  # 이 박 전에는 특별 줄을 내지 않는다: 첫 3마디는 읽을 시간을 준다
const GAP_AFTER_BIG := 2    # 턱·막대가 있는 줄 사이의 박 수 (160BPM 0.75초 > 슬라이드 0.65초)
const MIN_INPUT_GAP := 0.28 # 사람 입력 간격(초)
const BLOCK_LIMIT := 0.43   # 기둥 비율이 이보다 높으면 줄 읽기를 내지 않는다 (목표 45% 이하)
const BLOCK_ROW_LIMIT := 0.3  # 기둥 비율이 이보다 높으면 기둥 줄을 내지 않는다: 줄 읽기 몫을 남긴다
const WALL_MIXED := 0.7     # 벽 중 기둥+턱+막대 (나머지는 기둥 2개 + 동작)
## 160BPM 도착 뒤 밀도: 4마디마다 한 칸, 칸마다 더하는 값
const DENSITY_MAX := 6
const DENSITY_ONE_BEAT := 0.015
const DENSITY_BIG := 0.03
const DENSITY_WALL := 0.03
const DENSITY_SPECIAL := 0.01
const MIXED_PAIRS: Array[Array] = [[Kind.BLOCK, Kind.LOW], [Kind.BLOCK, Kind.HIGH], [Kind.LOW, Kind.HIGH]]

## 다음 줄이 도착할 박
var beat := 0.0

var _rng := RandomNumberGenerator.new()
var _start_step := 0
var _queue: Array[Dictionary] = []  # 만든 줄의 장애물들, 하나씩 꺼낸다
var _path := RunLogic.START_LANE    # 풀 수 있는 레인의 증거
var _last_big := -INF               # 턱·막대가 있었던 마지막 줄의 박
var _blocks := 0                    # 지금까지 나온 기둥 수
var _total := 0                     # 지금까지 나온 장애물 수


func _init(seed_value: int, first_beat: int, start_step := 0) -> void:
	_rng.seed = seed_value
	beat = first_beat
	_start_step = start_step


## 박의 160BPM 뒤 밀도 칸 (0~DENSITY_MAX)
func density(at_beat: float) -> int:
	var top_beat: int = (MusicLadder.STEPS.size() - 1 - _start_step) * MusicLadder.STEP_BEATS
	return clampi(floori((at_beat - top_beat) / MusicLadder.STEP_BEATS), 0, DENSITY_MAX)


## 반 박이 입력 간격 이상이라 지그재그를 낼 수 있는 BPM인가
static func can_zigzag(bpm: int) -> bool:
	return 30.0 / bpm >= MIN_INPUT_GAP


## 다음 장애물 {beat, lane, kind}를 돌려준다. 같은 박에 여러 개면 차례로 나온다.
func next() -> Dictionary:
	while _queue.is_empty():
		_make_row()
	return _queue.pop_front()


func _make_row() -> void:
	var step := MusicLadder.scheduled_step(_start_step, beat)
	var stage: int = MusicLadder.STEPS[step]["stage"]
	var level := density(beat)
	var can_big: bool = beat - _last_big >= GAP_AFTER_BIG
	var share := float(_blocks) / maxi(_total, 1)
	var too_many_blocks := share > BLOCK_LIMIT
	var bpm: int = MusicLadder.STEPS[step]["bpm"]
	var read_roll := _rng.randf()
	var deep: float = READ_DEEP + DENSITY_READ_DEEP * level
	if not too_many_blocks and bpm >= READ_DEEP_FROM_BPM and read_roll < deep:
		_read_rows(4)
	elif not too_many_blocks and beat >= SPECIAL_FROM and read_roll < deep + READ_SHALLOW[stage]:
		_read_rows(2)
	elif can_big and beat >= SPECIAL_FROM and _rng.randf() < SPECIAL + DENSITY_SPECIAL * level:
		if can_zigzag(bpm):
			_zigzag_rows()
		else:
			_combo_rows()
	elif can_big and (share > BLOCK_ROW_LIMIT or _rng.randf() < BIG[stage] + DENSITY_BIG * level):
		_big_row(stage, level)
	elif share > BLOCK_ROW_LIMIT and _total > 0:
		beat += 1  # 다음 박이면 동작 줄을 낼 수 있다
	else:
		_block_row(stage)
		beat += _gap(stage, level)


func _gap(stage: int, level: int) -> int:
	return 1 if _rng.randf() < ONE_BEAT[stage] + DENSITY_ONE_BEAT * level else 2


func _add(at_beat: float, lane: int, kind: Kind) -> void:
	_queue.append({"beat": at_beat, "lane": lane, "kind": kind})
	_total += 1
	_blocks += 1 if kind == Kind.BLOCK else 0
	if kind != Kind.BLOCK:
		_last_big = at_beat


func _random_big() -> Kind:
	return Kind.LOW if _rng.randf() < 0.5 else Kind.HIGH


## _path에서 한 칸 안의 레인을 무작위로
func _near_path() -> int:
	return clampi(_path + _rng.randi_range(-1, 1), 0, RunLogic.LANE_COUNT - 1)


## lane의 옆 레인 하나
func _beside(lane: int) -> int:
	return 1 if lane != 1 else (0 if _rng.randf() < 0.5 else 2)


## _path가 lane에 막혔으면 옆 레인으로 비킨다
func _step_aside(lane: int) -> void:
	if lane == _path:
		_path = _beside(lane)


func _block_row(stage: int) -> void:
	if _rng.randf() < DOUBLE[stage]:
		_pair_row(beat, _near_path(), [Kind.BLOCK, Kind.BLOCK])
	else:
		var lane := _rng.randi_range(0, RunLogic.LANE_COUNT - 1)
		_add(beat, lane, Kind.BLOCK)
		_step_aside(lane)


func _big_row(stage: int, level: int) -> void:
	var roll := _rng.randf()
	var wall: float = WALL[stage] + DENSITY_WALL * level
	if roll < wall:
		_wall_row()
		return
	if roll < wall + PAIR[stage]:
		_pair_row(beat, _near_path(), _mixed_pair())
	else:
		_add(beat, _near_path(), _random_big())
	beat += _gap(stage, level)


func _mixed_pair() -> Array:
	return MIXED_PAIRS[_rng.randi_range(0, MIXED_PAIRS.size() - 1)]


## 열린 레인 open 하나만 비우고 나머지 두 레인에 kinds를 무작위 순서로 놓는다
func _pair_row(at_beat: float, open: int, kinds: Array) -> void:
	var order := kinds if _rng.randf() < 0.5 else [kinds[1], kinds[0]]
	var used := 0
	for lane in RunLogic.LANE_COUNT:
		if lane != open:
			_add(at_beat, lane, order[used])
			used += 1
	_path = open


## 벽: 세 레인을 다 채운다. 앞을 한 박 더 비워 읽을 시간을 준다. 기둥이 아닌 레인으로 가서 뛰거나 미끄러진다.
func _wall_row() -> void:
	beat += 1
	var open := _near_path()  # 동작으로 지나갈 레인
	if _rng.randf() < WALL_MIXED:
		var block := _beside(open)
		var other := 3 - open - block
		_add(beat, block, Kind.BLOCK)
		var first := _random_big()
		_add(beat, open, first)
		_add(beat, other, Kind.LOW if first == Kind.HIGH else Kind.HIGH)
	else:
		_pair_row(beat, open, [Kind.BLOCK, Kind.BLOCK])
		_add(beat, open, _random_big())
	_path = open
	beat += GAP_AFTER_BIG


## 반 박 간격으로 열린 레인이 옆으로 옮겨 가는 기둥 두 줄: 레인 이동을 연달아 두 번
func _zigzag_rows() -> void:
	var first := _near_path()
	_pair_row(beat, first, [Kind.BLOCK, Kind.BLOCK])
	_pair_row(beat + 0.5, _beside(first), [Kind.BLOCK, Kind.BLOCK])
	beat += 2


## 1박 간격 3연속: 열린 레인이 매 박 옮겨 간다. 처음과 끝 줄은 섞고 가운데는 기둥 둘 (턱·막대 줄끼리 2박 규칙)
func _combo_rows() -> void:
	var open := _near_path()
	_pair_row(beat, open, _mixed_pair())
	open = _beside(open)
	_pair_row(beat + 1, open, [Kind.BLOCK, Kind.BLOCK])
	open = _beside(open)
	_pair_row(beat + 2, open, _mixed_pair())
	beat += 3


## 줄 읽기: 한 박 비운 뒤 가운데 기둥 count줄(반 박 간격: 건너갈 틈이 없는 긴 벽), 그다음 한쪽 끝만 열린 줄.
## 열린 쪽은 _path의 반대편이다: 빈 박 덕분에 벽이 닿기 전에 두 칸을 건널 시간(2박 >= 0.75초 > 입력 2번)이 있다.
func _read_rows(count: int) -> void:
	beat += 1
	var open := 2 - _path if _path != 1 else (0 if _rng.randf() < 0.5 else 2)
	for i in count:
		_add(beat + i * 0.5, 1, Kind.BLOCK)
	_pair_row(beat + count * 0.5, open, [Kind.BLOCK, Kind.BLOCK])
	beat += count * 0.5 + 1.0
