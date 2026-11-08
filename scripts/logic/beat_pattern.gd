class_name BeatPattern
extends RefCounted
## 배경 음악 구조에 맞춘 장애물 순서 (자동 테스트 대상). 박 번호는 음악 처음부터 센다.
## 앞 8마디(북·베이스): 2박마다, 레인 이동 위주. 뒤 8마디(멜로디): 1~2박마다, 세 동작이 골고루. 마디 첫 박엔 큰 동작이 더 자주.

const INTRO_BARS := 8
## 점프·슬라이드가 나올 확률: 앞 8마디, 앞 8마디 마디 첫 박, 뒤 8마디, 뒤 8마디 마디 첫 박
const BIG_INTRO := 0.2
const BIG_INTRO_BAR_START := 0.5
const BIG_MELODY := 2.0 / 3.0
const BIG_MELODY_BAR_START := 0.8
## 점프·슬라이드 다음에 비우는 박 수
const GAP_AFTER_BIG := 2

## 다음 장애물이 도착할 박
var beat := 0

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int, first_beat: int) -> void:
	_rng.seed = seed_value
	beat = first_beat


static func is_intro(at_beat: int) -> bool:
	return posmod(at_beat, BeatClock.BEATS_PER_BAR * BeatClock.LOOP_BARS) < BeatClock.BEATS_PER_BAR * INTRO_BARS


## 다음 장애물 {beat, lane, kind}를 돌려주고 다음 박으로 넘어간다.
func next() -> Dictionary:
	var kind := _pick_kind()
	var item := {"beat": beat, "lane": _rng.randi_range(0, RunLogic.LANE_COUNT - 1), "kind": kind}
	var gap := GAP_AFTER_BIG if kind != ObstacleField.Kind.BLOCK else (2 if is_intro(beat) else _rng.randi_range(1, 2))
	beat += gap
	if is_intro(beat) and beat % 2 == 1:  # 앞 8마디는 2박 격자에 다시 맞춘다
		beat += 1
	return item


func _pick_kind() -> ObstacleField.Kind:
	var bar_start := beat % BeatClock.BEATS_PER_BAR == 0
	var big: float
	if is_intro(beat):
		big = BIG_INTRO_BAR_START if bar_start else BIG_INTRO
	else:
		big = BIG_MELODY_BAR_START if bar_start else BIG_MELODY
	if _rng.randf() >= big:
		return ObstacleField.Kind.BLOCK
	return ObstacleField.Kind.LOW if _rng.randf() < 0.5 else ObstacleField.Kind.HIGH
