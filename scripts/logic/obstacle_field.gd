class_name ObstacleField
extends RefCounted
## 장애물의 생성·이동·제거 규칙. 노드는 만들지 않고 목록만 관리한다 (자동 테스트 대상).
## 화면(main.gd)은 step()이 돌려준 spawned/removed를 보고 노드를 만들고 지운다.

## 종류: BLOCK(레인을 바꿔 피함), LOW(낮은 허들: 점프), HIGH(공중에 뜬 막대: 슬라이드)
enum Kind { BLOCK, LOW, HIGH }

## 모양(월드 단위). 충돌 판정과 화면이 같은 값을 쓴다.
const BLOCK_SIZE := 1.1
const BAR_WIDTH := 1.3
const BAR_DEPTH := 0.5
const LOW_TOP := 0.45        # 허들 윗면 높이: 점프로 이보다 높이 떠야 넘는다
const HIGH_BOTTOM := 0.62    # 막대 아랫면 높이: 슬라이드로 이보다 낮아져야 지나간다
const HIGH_TOP := 1.32

## 생성 위치 (z는 음수 = 앞쪽 멀리, 안개 속)
const SPAWN_Z := -60.0
## 이 z를 넘으면 지나간 것으로 보고 제거 (카메라 뒤)
const REMOVE_Z := 6.0
## 생성 지점에서 주인공(z=0)까지 걸리는 시간. 도착 박에서 이만큼 거꾸로 계산해 생성한다.
const TRAVEL := -SPAWN_Z / RunLogic.SPEED
## 시작·재시작 뒤 첫 장애물까지 최소 1마디 (다음 마디 첫 박이므로 2.4~4.8초 안에 도착)
const START_LEAD := BeatClock.BAR

var speed := RunLogic.SPEED
## 현재 살아 있는 장애물: {id:int, lane:int, z:float, kind:Kind, beat:int}
var items: Array[Dictionary] = []
## 음악 시간. 패턴의 박은 이 시간 기준으로 도착한다.
var time := 0.0

var _pattern: BeatPattern
var _coming: Dictionary  # 아직 생성하지 않은 다음 장애물
var _next_id := 0


## 시드를 주면 순서가 고정된다. start_time: 음악 시간. 패턴은 이 시각 뒤 마디 첫 박부터 시작한다.
func _init(seed_value: int = 0, start_time: float = 0.0) -> void:
	time = start_time
	_pattern = BeatPattern.new(seed_value, BeatPattern.first_beat(start_time, START_LEAD))
	_coming = _pattern.next()


## dt초 진행한다. 이번에 생긴 것과 지워진 것의 id를 돌려준다.
## step(0)은 앞으로 도착할 장애물 중 z -60보다 가까운 것을 지금 시각에 맞는 자리에 미리 놓는다 (시작·재시작).
func step(dt: float) -> Dictionary:
	var spawned: Array[Dictionary] = []
	var removed: Array[int] = []
	time += dt
	for item in items:
		item["z"] += speed * dt
	var kept: Array[Dictionary] = []
	for item in items:
		if item["z"] > REMOVE_Z:
			removed.append(item["id"])
		else:
			kept.append(item)
	items = kept
	while _coming["beat"] * BeatClock.BEAT - time <= TRAVEL:
		var z: float = speed * (time - _coming["beat"] * BeatClock.BEAT)
		if z <= REMOVE_Z:  # 시간이 크게 건너뛰면(탭 전환 등) 이미 지나간 것은 만들지 않는다
			var item := {"id": _next_id, "lane": _coming["lane"], "z": z, "kind": _coming["kind"], "beat": _coming["beat"]}
			_next_id += 1
			items.append(item)
			spawned.append(item)
		_coming = _pattern.next()
	return {"spawned": spawned, "removed": removed}
