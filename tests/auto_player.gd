class_name AutoPlayer
extends RefCounted
## 패턴을 끝까지 피해 가는 자동 플레이어 (공정성 테스트와 review/ 기록에 쓴다). 웹 빌드에는 들어가지 않는다.

const LANE_LOOK := 0.3    # 블록 도착 이만큼 전(초)에 옆으로
const JUMP_LOOK := 0.25
const SLIDE_LOOK := 0.28


## 지금 내야 할 입력 (SwipeDetector.Dir)
static func decide(items: Array, lane: int, player: PlayerAction) -> int:
	for item: Dictionary in items:
		if item["lane"] != lane or item["z"] > ObstacleField.BLOCK_SIZE:
			continue
		var eta: float = -item["z"] / RunLogic.SPEED
		match item["kind"]:
			ObstacleField.Kind.BLOCK:
				if eta < LANE_LOOK:
					return _dodge(items, lane)
			ObstacleField.Kind.LOW:
				if eta < JUMP_LOOK and not player.is_jumping():
					return SwipeDetector.Dir.UP
			ObstacleField.Kind.HIGH:
				if eta < SLIDE_LOOK and not player.is_sliding() and not player.is_dropping():
					return SwipeDetector.Dir.DOWN
	return SwipeDetector.Dir.NONE


## 곧 장애물이 오지 않는 옆 레인으로
static func _dodge(items: Array, lane: int) -> int:
	for dir: int in ([-1, 1] if lane == 1 else ([1] if lane == 0 else [-1])):
		var free := true
		for item: Dictionary in items:
			var eta: float = -item["z"] / RunLogic.SPEED
			if item["lane"] == lane + dir and eta > -0.15 and eta < 0.45:
				free = false
		if free:
			return SwipeDetector.Dir.LEFT if dir < 0 else SwipeDetector.Dir.RIGHT
	return SwipeDetector.Dir.LEFT if lane > 0 else SwipeDetector.Dir.RIGHT
