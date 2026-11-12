class_name ScoreBoard
extends RefCounted
## 점수·콤보·배수·아슬아슬 판정 (화면과 분리, 자동 테스트 대상). 값은 data/score.json 한 곳.
## 점수 = 이동 거리 × distance_points + 방울 orb_points × 배수 + PERFECT(아슬아슬) close_points × 배수 (v0.11.1부터 모두 0.5배, 소수점은 합친 뒤 버림). 배수는 방울을 먹어 콤보가 오른 뒤의 값으로 곱한다.

const DATA_PATH := "res://data/score.json"
## 마의 구간 (v0.11.1 배점): 넘는 순간 점수가 말랑 + 빛나고, 그 판은 연보라로 남는다. 공유 글에 10K+
const MILESTONE := 10000

static var _data := {}

var points := 0.0    # 방울과 아슬아슬로 얻은 점수 (거리 점수 제외). 방울 32.5점 때문에 소수
var combo := 0       # 연속으로 먹은 방울 수
var orbs := 0        # 이번 판에 먹은 방울 수
var missed := 0      # 이번 판에 놓친 방울 수
var close := 0       # 이번 판 아슬아슬 횟수
var trail_streak := 0  # 지금 방울 줄 안에서 연속으로 먹은 수 (소리 높이)
var top_multiplier := 1  # 이번 판에 닿은 가장 큰 배수 (스킨 해금)

var _trail := -1
var _last_jump := -INF
var _last_slide := -INF
var _last_move := -INF
var _move_from := -1


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return _data


## 콤보의 배수: 표의 단계, 그 뒤 multiplier_every마다 +1, 상한까지
static func multiplier(of_combo: int) -> int:
	var d := data()
	var from: Array = d["multiplier_from"]
	var level := 0
	for i in from.size():
		if of_combo >= from[i]:
			level = i + 1
	if level == from.size():
		level += (of_combo - int(from[-1])) / int(d["multiplier_every"])
	return mini(level, int(d["multiplier_max"]))


## 오늘의 판 공유 글: "SWIPE PULSE Daily #12 — 5320", 10000점 이상은 끝에 " · 10K+"
static func share_text(day_number: int, final_score: int) -> String:
	return "SWIPE PULSE Daily #%d — %d%s" % [day_number, final_score, " · 10K+" if final_score >= MILESTONE else ""]


func total(distance: float) -> int:
	return int(distance * float(data()["distance_points"]) + points)


## 방울을 먹었다. 얻은 점수를 돌려준다.
func take_orb(trail: int) -> float:
	trail_streak = trail_streak + 1 if trail == _trail else 1
	_trail = trail
	combo += 1
	orbs += 1
	top_multiplier = maxi(top_multiplier, multiplier(combo))
	var gained: float = data()["orb_points"] * multiplier(combo)
	points += gained
	return gained


## 방울을 놓쳤다. 콤보가 있었으면 true (끊김 소리·배수 떨어짐)
func miss_orb() -> bool:
	missed += 1
	var broke := combo > 0
	combo = 0
	trail_streak = 0
	_trail = -1
	return broke


func note_jump(t: float) -> void:
	_last_jump = t


func note_slide(t: float) -> void:
	_last_slide = t


func note_move(t: float, from_lane: int) -> void:
	_last_move = t
	_move_from = from_lane


## 장애물이 주인공 자리를 지났다 (부딪히지 않음). arrive: 도착 시각, lane: 그때 주인공 레인.
## 피한 동작의 입력이 도착 close_window초 안이었으면 아슬아슬: 보너스 점수를 돌려준다, 아니면 0.
##   턱·막대가 내 레인: 점프·슬라이드 입력 / 장애물이 방금 떠난 레인(옆 레인으로 스침): 레인 이동 입력
func passed(kind: ObstacleField.Kind, item_lane: int, arrive: float, lane: int) -> int:
	var input := -INF
	if item_lane == lane and kind == ObstacleField.Kind.LOW:
		input = _last_jump
	elif item_lane == lane and kind == ObstacleField.Kind.HIGH:
		input = _last_slide
	elif item_lane == _move_from and absi(item_lane - lane) == 1:
		input = _last_move
	var lead := arrive - input
	if lead < 0.0 or lead > data()["close_window"]:
		return 0
	close += 1
	var gained := int(data()["close_points"]) * multiplier(combo)
	points += gained
	return gained


## 한 프레임 처리 (화면과 자동 플레이가 같이 쓴다). 부딪힘 판정 뒤에 부른다.
## 닿은 방울은 먹고(taken = t), 주인공 자리를 지난 방울은 놓친다(missed = t). 판정 폭을 지난 장애물은 아슬아슬인지 본다(passed).
## 결과 {taken: 먹은 방울들, broke: 콤보가 끊겼나, close: [{item, points}]}
func watch(field: ObstacleField, x: float, height: float, crouch: float, lane: int, t: float, speed: float) -> Dictionary:
	var taken: Array[Dictionary] = []
	var broke := false
	for i in field.skipped_orbs:
		broke = miss_orb() or broke
	field.skipped_orbs = 0
	for orb in field.orbs:
		if orb.has("taken") or orb.has("missed"):
			continue
		if OrbTrail.touches(orb["y"], x - orb["x"], PlayerAction.swept_dz(orb, OrbTrail.PICK_Z), height, crouch):
			orb["taken"] = t
			orb["points"] = take_orb(orb["trail"])
			orb["streak"] = trail_streak
			taken.append(orb)
		elif orb["z"] > OrbTrail.PICK_Z:
			orb["missed"] = t  # 놓친 시각: 화면은 이때부터 작아지며 사라진다
			broke = miss_orb() or broke
	var closes: Array[Dictionary] = []
	for item in field.items:
		if item.has("passed") or item["z"] <= PlayerAction.HIT_Z:
			continue
		item["passed"] = true
		var gained := passed(item["kind"], item["lane"], t - item["z"] / speed, lane)
		if gained > 0:
			closes.append({"item": item, "points": gained})
	return {"taken": taken, "broke": broke, "close": closes}
