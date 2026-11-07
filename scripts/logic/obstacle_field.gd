class_name ObstacleField
extends RefCounted
## 장애물의 생성·이동·제거 규칙. 노드는 만들지 않고 목록만 관리한다 (자동 테스트 대상).
## 화면(main.gd)은 step()이 돌려준 spawned/removed를 보고 노드를 만들고 지운다.

## 생성 위치 (z는 음수 = 앞쪽 멀리, 안개 속)
const SPAWN_Z := -60.0
## 이 z를 넘으면 지나간 것으로 보고 제거 (카메라 뒤)
const REMOVE_Z := 6.0
## 생성 간격(초)
const SPAWN_INTERVAL := 1.0

var speed := RunLogic.SPEED
## 현재 살아 있는 장애물: {id:int, lane:int, z:float}
var items: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _timer := 0.0


## 시드를 주면 레인 순서가 고정된다.
func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_timer = SPAWN_INTERVAL  # 시작하자마자 첫 장애물이 나오게


## dt초 진행한다. 이번에 생긴 것과 지워진 것의 id를 돌려준다.
func step(dt: float) -> Dictionary:
	var spawned: Array[Dictionary] = []
	var removed: Array[int] = []
	for item in items:
		item["z"] += speed * dt
	var kept: Array[Dictionary] = []
	for item in items:
		if item["z"] > REMOVE_Z:
			removed.append(item["id"])
		else:
			kept.append(item)
	items = kept
	_timer += dt
	while _timer >= SPAWN_INTERVAL:
		_timer -= SPAWN_INTERVAL
		var item := {"id": _next_id, "lane": _rng.randi_range(0, RunLogic.LANE_COUNT - 1), "z": SPAWN_Z}
		_next_id += 1
		items.append(item)
		spawned.append(item)
	return {"spawned": spawned, "removed": removed}
