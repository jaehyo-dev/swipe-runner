class_name ObstacleField
extends RefCounted
## 장애물의 생성·이동·제거 규칙. 노드는 만들지 않고 목록만 관리한다 (자동 테스트 대상).
## 화면(main.gd)은 step()이 돌려준 spawned/removed를 보고 노드를 만들고 지운다.

## 종류: BLOCK(얼음 기둥: 레인을 바꿔 피함), LOW(낮은 턱: 점프), HIGH(공중에 뜬 막대: 슬라이드)
enum Kind { BLOCK, LOW, HIGH }

## 모양(월드 단위). 충돌 판정과 화면이 같은 값을 쓴다.
const BLOCK_SIZE := 1.1      # 얼음 기둥 폭·깊이
const BLOCK_HEIGHT := 2.1    # 얼음 기둥 키: 점프 최고점(1.6)보다 확실히 높아 넘을 수 없다 (판정에 높이는 없다)
const BAR_WIDTH := 1.3
const BAR_DEPTH := 0.5
const LOW_TOP := 0.45        # 허들 윗면 높이: 점프로 이보다 높이 떠야 넘는다
const HIGH_BOTTOM := 0.62    # 막대 아랫면 높이: 슬라이드로 이보다 낮아져야 지나간다
const HIGH_TOP := 1.32

## 생성 위치 (z는 음수 = 앞쪽 멀리, 안개 속)
const SPAWN_Z := -60.0
## 이 z를 넘으면 지나간 것으로 보고 제거 (카메라 뒤)
const REMOVE_Z := 6.0
## 시작·재시작 뒤 첫 장애물은 1마디 뒤 첫 박에 도착한다
const FIRST_BEAT := BeatClock.BEATS_PER_BAR

## 현재 살아 있는 장애물: {id:int, lane:int, z:float, kind:Kind, beat:float, arrive:float}. arrive: 주인공(z=0)에 닿을 때의 이동 거리
var items: Array[Dictionary] = []
## 지금까지 이동한 거리
var travel := 0.0

## 박을 이동 거리로 바꾸는 이번 판의 사다리. 첫 입력에 음악이 시작하며 새 사다리로 바뀐다 (main.begin)
var ladder: MusicLadder
var _pattern: BeatPattern
var _coming: Dictionary  # 아직 생성하지 않은 다음 장애물
var _next_id := 0


## 시드를 주면 순서가 고정된다.
func _init(seed_value: int = 0, run_ladder := MusicLadder.new()) -> void:
	ladder = run_ladder
	_pattern = BeatPattern.new(seed_value, FIRST_BEAT, ladder.segments[0]["step"])
	_coming = _pattern.next()


## 이동 거리를 now로 옮긴다. 이번에 생긴 것과 지워진 것의 id를 돌려준다.
## step(travel)은 앞으로 도착할 장애물 중 z -60보다 가까운 것을 지금 거리에 맞는 자리에 미리 놓는다 (시작·재시작).
func step(now: float) -> Dictionary:
	var spawned: Array[Dictionary] = []
	var removed: Array[int] = []
	travel = now
	var kept: Array[Dictionary] = []
	for item in items:
		item["z"] = now - item["arrive"]
		if item["z"] > REMOVE_Z:
			removed.append(item["id"])
		else:
			kept.append(item)
	items = kept
	while ladder.distance_of_beat(_coming["beat"]) - now <= -SPAWN_Z:
		var arrive := ladder.distance_of_beat(_coming["beat"])
		var z := now - arrive
		if z <= REMOVE_Z:  # 시간이 크게 건너뛰면(탭 전환 등) 이미 지나간 것은 만들지 않는다
			var item := {"id": _next_id, "lane": _coming["lane"], "z": z, "kind": _coming["kind"], "beat": _coming["beat"], "arrive": arrive}
			_next_id += 1
			items.append(item)
			spawned.append(item)
		_coming = _pattern.next()
	return {"spawned": spawned, "removed": removed}
