class_name AutoPlayer
extends RefCounted
## 패턴을 끝까지 피해 가는 완벽한 자동 플레이어 (공정성 테스트와 review/ 기록에 쓴다). 웹 빌드에는 들어가지 않는다.
## 앞으로 올 줄들을 보고 레인 경로를 찾는다. 사람이 낼 수 있는 입력 간격(MIN_GAP)만 쓰므로 부딪히지 않으면 풀 수 있다는 증거다.

const LANE_LOOK := 0.26   # 기둥 도착 이만큼 전(초)에 옆으로
const BIG_LANE_LOOK := 0.44  # 점프·슬라이드할 레인으로는 동작 입력 간격만큼 먼저 옮겨 둔다
const JUMP_LOOK := 0.25
const SLIDE_LOOK := 0.28
const MIN_GAP := 0.28     # 사람 기준 입력 간격
const PLAN_ROWS := 4      # 내다보는 줄 수


## 지금 내야 할 입력 (SwipeDetector.Dir). since_input: 지난 입력 뒤 흐른 시간
static func decide(items: Array, lane: int, player: PlayerAction, speed: float, since_input := INF) -> int:
	if since_input < MIN_GAP:
		return SwipeDetector.Dir.NONE
	var rows := rows_ahead(items, speed)
	if rows.is_empty():
		return SwipeDetector.Dir.NONE
	var row: Dictionary = rows[0]
	var target: int = best_path(rows.slice(0, PLAN_ROWS), lane)[0]
	var kinds: Dictionary = row["lanes"]
	if target != lane:
		if row["eta"] < (BIG_LANE_LOOK if kinds.has(target) else LANE_LOOK) + (absi(target - lane) - 1) * MIN_GAP:
			return move_dir(lane, target)
		return SwipeDetector.Dir.NONE
	return big_input(kinds.get(lane, ObstacleField.Kind.BLOCK), row["eta"], player, JUMP_LOOK, SLIDE_LOOK)


static func move_dir(lane: int, target: int) -> int:
	return SwipeDetector.Dir.LEFT if target < lane else SwipeDetector.Dir.RIGHT


## 지금 줄이 턱·막대면 때가 됐을 때의 입력
static func big_input(kind: ObstacleField.Kind, eta: float, player: PlayerAction, jump_look: float, slide_look: float) -> int:
	match kind:
		ObstacleField.Kind.LOW:
			if eta < jump_look and not player.is_jumping():
				return SwipeDetector.Dir.UP
		ObstacleField.Kind.HIGH:
			if eta < slide_look and not player.is_sliding() and not player.is_dropping():
				return SwipeDetector.Dir.DOWN
	return SwipeDetector.Dir.NONE


## 아직 지나가지 않은 줄들을 가까운 순서로: {beat, eta, lanes: {레인: 종류}}. 같은 레인의 기둥이 먼저 잡히면 그대로 둔다.
static func rows_ahead(items: Array, speed: float) -> Array[Dictionary]:
	var by_beat := {}
	for item: Dictionary in items:
		if item["z"] > PlayerAction.HIT_Z:
			continue
		if not by_beat.has(item["beat"]):
			by_beat[item["beat"]] = {"beat": item["beat"], "eta": -item["z"] / speed, "lanes": {}}
		by_beat[item["beat"]]["lanes"][item["lane"]] = item["kind"]
	var rows: Array[Dictionary] = []
	rows.assign(by_beat.values())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["beat"] < b["beat"])
	return rows


## 줄마다 설 레인을 고른다. 기둥은 못 서고, 움직임과 동작이 적은 쪽을 고른다.
static func best_path(rows: Array, lane: int) -> Array[int]:
	var best := {"cost": INF, "path": [] as Array[int]}
	_search(rows, 0, lane, 0.0, [] as Array[int], best, rows[0]["eta"])
	if best["path"].is_empty():  # 이미 늦었다 (사람 모델이 늦게 반응한 경우): 가장 가까운 열린 레인으로 간다
		var open: int = lane
		for next in RunLogic.LANE_COUNT:
			var free: bool = rows[0]["lanes"].get(next, -1) != ObstacleField.Kind.BLOCK
			if free and (absi(next - lane) < absi(open - lane) or rows[0]["lanes"].get(open, -1) == ObstacleField.Kind.BLOCK):
				open = next
		best["path"] = [open] as Array[int]
	return best["path"]


static func _search(rows: Array, i: int, lane: int, cost: float, path: Array[int], best: Dictionary, prev_eta: float) -> void:
	if cost >= best["cost"]:
		return
	if i == rows.size():
		best["cost"] = cost
		best["path"] = path.duplicate()
		return
	var row: Dictionary = rows[i]
	var kinds: Dictionary = row["lanes"]
	# 한 칸은 언제든, 두 칸은 입력 간격 두 번에 여유가 있을 때만
	var reach := 2 if (i == 0 and row["eta"] > 0.5) or (i > 0 and row["eta"] - prev_eta > 0.7) else 1
	if i == 0 and row["eta"] < 0.1:
		reach = 0
	for next in RunLogic.LANE_COUNT:
		if absi(next - lane) > reach or kinds.get(next, -1) == ObstacleField.Kind.BLOCK:
			continue
		path.append(next)
		_search(rows, i + 1, next, cost + absi(next - lane) + (0.5 if kinds.has(next) else 0.0), path, best, row["eta"])
		path.pop_back()
