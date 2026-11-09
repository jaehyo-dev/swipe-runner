class_name Shatter
extends RefCounted
## 지나간 장애물이 빛 조각으로 부서지는 계산 (자동 테스트 대상, ART_BIBLE.md 10-1). 무작위는 시드로 고정한다.

const COUNT_MIN := 8
const COUNT_MAX := 14
const LIFE := 0.35         # 이 시간 안에 사라진다(초)
const SIZE := Vector2(0.09, 0.2)      # 조각 크기 범위
const SIDE_SPEED := Vector2(1.2, 3.6) # 바깥으로 흩어지는 속도 범위
const BACK_SHARE := Vector2(0.45, 0.9)  # 뒤로 가는 속도: 세상 속도의 이 비율 (세상과 같이 흘러가다 뒤로 빠진다)
const FALL := 5.0          # 아래로 끌리는 힘
const MARK_SHARE := 0.3    # 기호 자리에서 나오는 조각 비율. 조금 더 밝다
const MARK_SPREAD := 0.55  # 기호 자리: 앞면 가운데 55%


## 장애물 종류의 앞면 영역: {center, half}. 원점은 레인 가운데 바닥.
static func face(kind: ObstacleField.Kind) -> Dictionary:
	match kind:
		ObstacleField.Kind.BLOCK:
			return {"center": Vector2(0.0, ObstacleField.BLOCK_HEIGHT * 0.5), "half": Vector2(ObstacleField.BLOCK_SIZE, ObstacleField.BLOCK_HEIGHT) * 0.5}
		ObstacleField.Kind.LOW:
			return {"center": Vector2(0.0, ObstacleField.LOW_TOP * 0.5), "half": Vector2(ObstacleField.BAR_WIDTH, ObstacleField.LOW_TOP) * 0.5}
		_:
			var height := ObstacleField.HIGH_TOP - ObstacleField.HIGH_BOTTOM
			return {"center": Vector2(0.0, ObstacleField.HIGH_BOTTOM + height * 0.5), "half": Vector2(ObstacleField.BAR_WIDTH, height) * 0.5}


## 조각 목록: {from(장애물 원점 기준), velocity, size, spin, mark}. speed: 지금 세상 속도
static func burst(kind: ObstacleField.Kind, seed_value: int, speed: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var area := face(kind)
	var center: Vector2 = area["center"]
	var half: Vector2 = area["half"]
	var shards: Array[Dictionary] = []
	for i in rng.randi_range(COUNT_MIN, COUNT_MAX):
		var mark := i < int(COUNT_MAX * MARK_SHARE)
		var spread := MARK_SPREAD if mark else 1.0
		var at := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var out := at.normalized() if at.length() > 0.01 else Vector2.UP
		var push := rng.randf_range(SIDE_SPEED.x, SIDE_SPEED.y)
		shards.append({
			"from": Vector3(center.x + at.x * half.x * spread, center.y + at.y * half.y * spread, 0.0),
			"velocity": Vector3(out.x * push, out.y * push, speed * rng.randf_range(BACK_SHARE.x, BACK_SHARE.y)),
			"size": rng.randf_range(SIZE.x, SIZE.y),
			"spin": Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)),
			"mark": mark,
		})
	return shards


## 나이 age의 자리
static func position_at(shard: Dictionary, age: float) -> Vector3:
	return shard["from"] + shard["velocity"] * age + Vector3.DOWN * FALL * age * age * 0.5


## 나이 age의 크기·밝기 배율. 1에서 시작해 LIFE에 0이 된다.
static func fade(age: float) -> float:
	return clampf(1.0 - age / LIFE, 0.0, 1.0)
