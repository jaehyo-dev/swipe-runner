class_name BeatPattern
extends RefCounted
## 음악 구조와 압박 단계에 맞춘 장애물 순서 (자동 테스트 대상). 박 번호는 음악 처음부터 센다. 반 박은 x.5.
## 줄의 종류
##   기둥 줄: 기둥 1개, 또는 기둥 2개(한 레인만 열림)
##   동작 줄: 턱·막대 1개 / 혼합 겹줄(기둥+턱, 기둥+막대, 턱+막대, 나머지 한 레인은 빈다) / 벽(세 레인을 다 채운다, 앞을 한 박 비운다)
##   특별 줄: 반 박이 입력 간격(0.22초) 이상인 BPM은 반 박 레인 이동 2연속(지그재그), 그보다 빠르면 1박 간격 콤보(압박 단계에 따라 2~4줄)
##   흐름 줄: 레인 이동 → 점프·슬라이드 → 레인 이동, 또는 점프 → 2박 뒤 슬라이드
## 압박 단계는 8마디마다 1씩 끝없이 오르고 확률은 data/difficulty.json의 [단계별 기본, 압박당 증가, 상한]이다. 8마디 중 한 마디는 숨 고르기(장애물 1개, 2박 간격).
## 공정성: _path는 "이 순서를 풀 수 있는 레인"의 증거다. 줄마다 이 레인에서 한 칸 안에 지나갈 곳을 둔다. 턱·막대가 있는 줄끼리는 2박 이상 벌린다.
## 줄 읽기는 열린 줄이 보이는 시간 안에 들어올 때만 낸다 (can_read).
## 옆 동작(v0.8.1): 콤보·섞인 동작·기둥 둘 줄의 "기둥 둘" 중 하나를 side_big 확률로 턱·막대로 바꾼다. 빈 레인은 그대로라
## 피할 길은 같고, 기둥 비율만 내려간다(45% 이하). 이 턱·막대는 꼭 해야 하는 동작이 아니라 2박 규칙에서 빠진다 (item["side"]).

const Kind := ObstacleField.Kind
const SPECIAL_FROM := 12.0  # 이 박 전에는 특별 줄을 내지 않는다: 첫 3마디는 읽을 시간을 준다
const GAP_AFTER_BIG := 2    # 턱·막대가 있는 줄 사이의 박 수 (160BPM 0.75초 > 슬라이드 0.65초)
const MIN_INPUT_GAP := 0.22 # 사람 입력 간격(초)
const LONGEST_ROWS := 6     # 여러 줄 패턴이 차지하는 가장 긴 박 수 (섞인 동작: 빈 박 1 + 동작 + 2박 + 동작 = 5박 뒤까지)
const READ_LEAD := 0.66     # 줄 읽기: 첫 가운데 기둥이 이만큼(초) 앞일 때 두 칸 건너기를 시작해야 한다 (입력 간격 두 번 + 레인 이동)
const BLOCK_ROW_LIMIT := 0.5  # (v0.8.1: 0.6 → 0.5) 기둥 비율이 이보다 높으면 기둥 줄을 내지 않는다: 동작 줄 몫을 남긴다
const WALL_MIXED := 1.0     # 벽은 기둥+턱+막대 (v0.8.1: 기둥 비율 45% 이하를 위해 기둥 2개 + 동작은 내지 않음)
const SINGLE_BIG := 0.7    # 장애물 하나 줄(숨 고르기·기둥 줄)이 기둥 대신 턱·막대일 확률 (v0.8.1, 기둥 비율 45% 이하)
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
var _shape := ""                    # 지금 만드는 줄의 종류 (난이도 표의 사망 원인)


func _init(seed_value: int, first_beat: int, start_step := 0) -> void:
	_rng.seed = seed_value
	beat = first_beat
	_start_step = start_step


## 박의 압박 단계: 음악 처음부터 8마디마다 1씩, 상한 없음 (?bpm으로 시작한 판도 0부터)
static func pressure(at_beat: float) -> int:
	return floori(maxf(at_beat, 0.0) / (BeatClock.BEATS_PER_BAR * MusicLadder.data()["pressure_bars"]))


## 숨 고르기 마디인가 (압박 단계 안의 정해진 한 마디)
static func is_breather(at_beat: float) -> bool:
	var bar := floori(maxf(at_beat, 0.0) / BeatClock.BEATS_PER_BAR)
	return posmod(bar, MusicLadder.data()["pressure_bars"]) == MusicLadder.data()["breather_bar"]


## 다음 숨 고르기 마디가 시작할 때까지 남은 박. 여러 줄 패턴이 그 마디로 넘어가지 않게 쓴다.
static func beats_to_breather(at_beat: float) -> float:
	var bars: int = MusicLadder.data()["pressure_bars"]
	var group := floori(maxf(at_beat, 0.0) / (BeatClock.BEATS_PER_BAR * bars))
	return (group * bars + int(MusicLadder.data()["breather_bar"])) * BeatClock.BEATS_PER_BAR - at_beat


## 확률 name: 편곡 단계 기본값 + 압박 단계당 증가, 상한까지
static func rate(name: String, stage: int, level: int) -> float:
	var r: Array = MusicLadder.data()["pattern"][name]
	return minf(r[0][stage] + r[1] * level, r[2])


## 1박 콤보의 줄 수: 압박 단계에 따라 2 → 3 → 4
static func combo_length(level: int) -> int:
	var d := MusicLadder.data()
	return mini(2 + level / int(d["combo_every"]), int(d["combo_max"]))


## 반 박이 입력 간격 이상이라 지그재그를 낼 수 있는 BPM인가
static func can_zigzag(bpm: int) -> bool:
	return 30.0 / bpm >= MIN_INPUT_GAP


## 가운데 기둥 count줄 뒤의 열린 줄이, 두 칸 건너기를 시작해야 할 때 이미 알아볼 수 있는가 (안개에서 반쯤 진해진 때)
static func can_read(count: int, step: int) -> bool:
	var seen: float = MusicLadder.visible_time(step) - MusicLadder.data()["fade"] * 0.5
	return count * 0.5 * MusicLadder.beat_time(step) + READ_LEAD <= seen


## 다음 장애물 {beat, lane, kind}를 돌려준다. 같은 박에 여러 개면 차례로 나온다.
func next() -> Dictionary:
	while _queue.is_empty():
		_make_row()
	return _queue.pop_front()


func _make_row() -> void:
	var step := MusicLadder.scheduled_step(_start_step, beat)
	var info := MusicLadder.info(step)
	var stage: int = info["stage"]
	var bpm: int = info["bpm"]
	var level := pressure(beat)
	if is_breather(beat):
		_shape = "숨 고르기"
		_single_block()
		beat += 2
		return
	var can_big: bool = beat - _last_big >= GAP_AFTER_BIG
	var share := float(_blocks) / maxi(_total, 1)
	var room := beats_to_breather(beat)
	var roomy := room < 0.0 or room >= LONGEST_ROWS  # 숨 고르기 마디 바로 앞에서는 한 줄짜리만
	var read_roll := _rng.randf()
	var deep := rate("read_deep", stage, level)
	if roomy and read_roll < deep and can_read(4, step):
		_shape = "줄 읽기"
		_read_rows(4)
	elif roomy and beat >= SPECIAL_FROM and read_roll < deep + rate("read_shallow", stage, level) and can_read(2, step):
		_shape = "줄 읽기"
		_read_rows(2)
	elif roomy and can_big and beat >= SPECIAL_FROM and _rng.randf() < rate("special", stage, level):
		if can_zigzag(bpm):
			_shape = "반 박 이동"
			_zigzag_rows()
		else:
			_shape = "1박 콤보"
			_combo_rows(combo_length(level))
	elif roomy and can_big and beat >= SPECIAL_FROM and _rng.randf() < rate("flow", stage, level):
		_shape = "섞인 동작"
		_flow_rows()
	elif can_big and (share > BLOCK_ROW_LIMIT or _rng.randf() < rate("big", stage, level)):
		_shape = "동작 줄"
		_big_row(stage, level, room < 0.0 or room >= 2.0)
	elif share > BLOCK_ROW_LIMIT and _total > 0:
		beat += 1  # 다음 박이면 동작 줄을 낼 수 있다
	else:
		_shape = "기둥 줄"
		var gap := _gap(stage, level)
		_block_row(stage, level, gap)
		beat += gap


func _gap(stage: int, level: int) -> int:
	return 1 if _rng.randf() < rate("one_beat", stage, level) else 2


func _add(at_beat: float, lane: int, kind: Kind, side := false) -> void:
	var item := {"beat": at_beat, "lane": lane, "kind": kind, "shape": _shape}
	if side:
		item["side"] = true
	_queue.append(item)
	_total += 1
	_blocks += 1 if kind == Kind.BLOCK else 0
	if kind != Kind.BLOCK and not side:
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


## gap: 다음 줄까지 박 수 (2박 이상이면 어느 레인의 옆 동작에서도 다음 길로 건너갈 수 있다)
func _block_row(stage: int, level: int, gap: int) -> void:
	if _rng.randf() < rate("double", stage, level):
		_wall_pair(beat, _near_path(), -1, gap >= 2)
	else:
		_single_block()


## 장애물 하나: SINGLE_BIG 확률로 턱·막대(두 레인이 비어 꼭 하지 않아도 되는 옆 동작), 아니면 기둥
func _single_block() -> void:
	var lane := _rng.randi_range(0, RunLogic.LANE_COUNT - 1)
	var big := _rng.randf() < SINGLE_BIG
	_add(beat, lane, _random_big() if big else Kind.BLOCK, big)
	_step_aside(lane)  # 턱·막대여도 풀이 레인은 동작이 필요 없는 옆 레인으로


## can_wall: 벽은 한 박 비운 뒤에 놓이므로 숨 고르기 마디 바로 앞 박에서는 내지 않는다
func _big_row(stage: int, level: int, can_wall: bool) -> void:
	var roll := _rng.randf()
	var wall := rate("wall", stage, level) if can_wall else 0.0
	if roll < wall:
		_shape = "겹줄"
		_wall_row()
		return
	if roll < wall + rate("pair", stage, level):
		_pair_row(beat, _near_path(), _mixed_pair())
	else:
		_add(beat, _near_path(), _random_big())
	beat += _gap(stage, level)


func _mixed_pair() -> Array:
	return MIXED_PAIRS[_rng.randi_range(0, MIXED_PAIRS.size() - 1)]


## 열린 레인 open 하나만 비우고 나머지 두 레인에 kinds를 무작위 순서로 놓는다
func _pair_row(at_beat: float, open: int, kinds: Array, side := false) -> void:
	var order := kinds if _rng.randf() < 0.5 else [kinds[1], kinds[0]]
	var used := 0
	for lane in RunLogic.LANE_COUNT:
		if lane != open:
			_add(at_beat, lane, order[used], side)
			used += 1
	_path = open


## 기둥 둘 줄. side_big 확률로 기둥 하나(또는 둘 다)를 옆 동작(턱·막대)으로 바꾼다.
## 옆 동작 레인은 다음 풀이 레인에서 한 칸 안이어야 한다: 멀면 거기서 동작하다 1박 뒤 줄(안개 속이라 아직 안 보임)에 갇힌다.
## next: 다음 줄의 빈 레인(모르면 -1 → 다음 패턴의 풀이 레인은 open에서 한 칸 안 어디든). free: 다음 줄이 2박 이상 뒤라 어느 레인이든 된다
func _wall_pair(at_beat: float, open: int, next := -1, free := false) -> void:
	var nexts := [next] if next >= 0 else range(maxi(open - 1, 0), mini(open + 2, RunLogic.LANE_COUNT))
	var safe := []
	for lane in RunLogic.LANE_COUNT:
		if lane != open and (free or nexts.all(func(p): return absi(lane - p) <= 1)):
			safe.append(lane)
	var step := MusicLadder.scheduled_step(_start_step, beat)
	if safe.is_empty() or _rng.randf() >= rate("side_big", MusicLadder.info(step)["stage"], pressure(beat)):
		_pair_row(at_beat, open, [Kind.BLOCK, Kind.BLOCK])
		return
	var both := safe.size() == 2 and _rng.randf() < 0.5
	var big := _random_big()
	var pick: int = safe[_rng.randi_range(0, safe.size() - 1)]
	for lane in RunLogic.LANE_COUNT:
		if lane == open:
			continue
		if both:
			_add(at_beat, lane, big, true)
			big = Kind.LOW if big == Kind.HIGH else Kind.HIGH
		else:
			_add(at_beat, lane, big if lane == pick else Kind.BLOCK, lane == pick)
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


## 1박 간격 count연속: 열린 레인이 매 박 옮겨 간다. 짝수 번째 줄은 섞고 홀수 번째는 기둥 둘 (턱·막대 줄끼리 2박 규칙)
func _combo_rows(count: int) -> void:
	var open := _near_path()
	for i in count:
		var next := _beside(open)
		if i % 2 == 0:
			_pair_row(beat + i, open, _mixed_pair())
		else:
			_wall_pair(beat + i, open, next if i < count - 1 else -1)
		open = next
	beat += count


## 섞인 동작 콤보 두 가지
##   레인 이동 → (1박) 점프·슬라이드 → (1박) 레인 이동: 동작 중에 옆으로 옮긴다
##   점프·슬라이드 → 2박 뒤 반대 동작: 한 레인에서 동작 둘을 잇는다 (앞을 한 박 비운다)
func _flow_rows() -> void:
	if _rng.randf() < 0.5:
		var open := _beside(_path)
		var next := _beside(open)
		_pair_row(beat, open, [Kind.BLOCK, Kind.BLOCK])  # 1박 뒤 이 레인에서 꼭 동작해야 해서 옆 동작을 두지 않는다
		_wall_pair(beat + 1, open, next)
		_add(beat + 1, open, _random_big())
		_wall_pair(beat + 2, next)
		beat += 3
	else:
		beat += 1
		var open := _near_path()
		var first := _random_big()
		_wall_pair(beat, open, open)
		_add(beat, open, first)
		_wall_pair(beat + GAP_AFTER_BIG, open, -1, true)  # 다음 줄은 2박 뒤
		_add(beat + GAP_AFTER_BIG, open, Kind.LOW if first == Kind.HIGH else Kind.HIGH)
		beat += GAP_AFTER_BIG * 2


## 줄 읽기: 한 박 비운 뒤 가운데 기둥 count줄(반 박 간격: 건너갈 틈이 없는 긴 벽), 그다음 한쪽 끝만 열린 줄.
## 열린 쪽은 _path의 반대편이다: 빈 박 덕분에 벽이 닿기 전에 두 칸을 건널 시간(2박 >= 0.75초 > 입력 2번)이 있다.
func _read_rows(count: int) -> void:
	beat += 1
	var open := 2 - _path if _path != 1 else (0 if _rng.randf() < 0.5 else 2)
	for i in count:
		_add(beat + i * 0.5, 1, Kind.BLOCK)
	_pair_row(beat + count * 0.5, open, [Kind.BLOCK, Kind.BLOCK])
	beat += count * 0.5 + 1.0
