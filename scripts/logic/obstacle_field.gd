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

## 생성 위치는 음악 시간마다 달라진다: 안개 거리보다 조금 먼 곳 (MusicLadder.spawn_distance_at, z는 음수 = 앞쪽 멀리)
## 이 z를 넘으면 지나간 것으로 보고 제거 (카메라 뒤)
const REMOVE_Z := 6.0
## 시작·재시작 뒤 첫 장애물은 1마디 뒤 첫 박에 도착한다
const FIRST_BEAT := BeatClock.BEATS_PER_BAR
## 이만큼 방울이 계획돼 있으면 계획을 쉰다 (줄 두 개쯤: 160BPM에서도 3초 넘게 남는다)
const ORB_AHEAD := 16

## 현재 살아 있는 장애물: {id:int, lane:int, z:float, kind:Kind, beat:float, arrive:float}. arrive: 주인공(z=0)에 닿을 때의 이동 거리
var items: Array[Dictionary] = []
## 지금까지 이동한 거리
var travel := 0.0

## 박을 이동 거리로 바꾸는 이번 판의 사다리. 첫 입력에 음악이 시작하며 새 사다리로 바뀐다 (main.begin)
var ladder: MusicLadder
## 살아 있는 빛 방울: {id, beat, x, y, lane, trail, index, z, arrive}. 먹거나 놓친 것은 화면이 표시한다 (taken, missed)
var orbs: Array[Dictionary] = []
## true면 만든 방울 줄을 모두 남긴다 (공정성 테스트)
var keep_trails := false
## 먹거나 놓쳤다는 처리 없이 지워진 방울 수 (시간이 크게 건너뛴 프레임). ScoreBoard.watch가 놓침으로 센다
var skipped_orbs := 0
var trails: Array[Dictionary] = []
var _pattern: BeatPattern
var _orb_trail: OrbTrail
var _known: Array[Dictionary] = []  # 패턴에서 꺼낸 장애물: 아직 생성 안 된 것 + 방울 줄 계획에 필요한 최근 것
var _next_spawn := 0               # _known에서 다음에 생성할 번호
var _orb_queue: Array[Dictionary] = []  # 계획했지만 아직 생성 안 된 방울
var _next_id := 0


## 시드를 주면 순서가 고정된다.
func _init(seed_value: int = 0, run_ladder := MusicLadder.new()) -> void:
	ladder = run_ladder
	_pattern = BeatPattern.new(seed_value, FIRST_BEAT, ladder.segments[0]["step"])
	_orb_trail = OrbTrail.new(seed_value, ladder.segments[0]["step"])


## 패턴을 beat까지 꺼내 둔다
func _pull_until(beat: float) -> void:
	while _known.is_empty() or _known[-1]["beat"] < beat:
		_known.append(_pattern.next())


## 방울 줄 계획을 한 걸음 진행한다 (계획된 방울이 ORB_AHEAD개보다 적을 때만, 한 프레임에 후보 하나).
## 큐가 비었으면(시작·재시작) 줄 하나가 정해질 때까지 이어서 한다. 다 쓴 옛 장애물은 버린다.
func _plan_orbs() -> void:
	while _orb_queue.size() < ORB_AHEAD:
		_pull_until(_orb_trail.horizon())
		var trail := _orb_trail.work(_known)
		if not trail.is_empty():
			_orb_queue.append_array(trail["orbs"])
			if keep_trails:
				trails.append(trail)
		if not _orb_queue.is_empty():
			break
	var keep_from := _orb_trail.next_beat - OrbTrail.LEAD - 2.0
	var drop := 0
	while drop < _next_spawn and _known[drop]["beat"] < keep_from:
		drop += 1
	if drop > 0:
		_known = _known.slice(drop)
		_next_spawn -= drop


## 같은 줄에서 이웃한 두 레인의 기둥이면 그림은 넓은 벽 하나다. 판정은 레인마다 그대로 따로다.
static func forms_wall(a: Dictionary, b: Dictionary) -> bool:
	return a["kind"] == Kind.BLOCK and b["kind"] == Kind.BLOCK and absi(a["lane"] - b["lane"]) == 1 and a["beat"] == b["beat"]


## 이동 거리를 now로 옮기고 spawn(생성 거리)보다 가까워진 장애물을 만든다. 이번에 생긴 것과 지워진 것의 id를 돌려준다.
## 시작·재시작 때는 앞으로 도착할 장애물 중 생성 거리 안의 것을 지금 거리에 맞는 자리에 미리 놓는다.
func step(now: float, spawn: float) -> Dictionary:
	var spawned: Array[Dictionary] = []
	var removed: Array[int] = []
	travel = now
	var kept: Array[Dictionary] = []
	for item in items:
		item["prev_z"] = item["z"]  # 프레임 사이 구간 판정용 (PlayerAction.swept_dz)
		item["z"] = now - item["arrive"]
		if item["z"] > REMOVE_Z:
			removed.append(item["id"])
		else:
			kept.append(item)
	items = kept
	while true:
		if _next_spawn >= _known.size():
			_known.append(_pattern.next())
		var coming := _known[_next_spawn]
		var arrive := ladder.distance_of_beat(coming["beat"])
		if arrive - now > spawn:
			break
		_next_spawn += 1
		var z := now - arrive
		if z <= REMOVE_Z:  # 시간이 크게 건너뛰면(탭 전환 등) 이미 지나간 것은 만들지 않는다
			var item := {"id": _next_id, "lane": coming["lane"], "z": z, "kind": coming["kind"], "beat": coming["beat"], "arrive": arrive, "shape": coming["shape"]}
			_next_id += 1
			items.append(item)
			spawned.append(item)
	_step_orbs(now, spawn)
	return {"spawned": spawned, "removed": removed}


## 방울도 장애물과 같은 규칙으로 다가오고 생기고 지워진다
func _step_orbs(now: float, spawn: float) -> void:
	var kept: Array[Dictionary] = []
	for orb in orbs:
		orb["prev_z"] = orb["z"]
		orb["z"] = now - orb["arrive"]
		if orb["z"] <= REMOVE_Z:
			kept.append(orb)
		elif not orb.has("taken") and not orb.has("missed"):
			skipped_orbs += 1
	orbs = kept
	_plan_orbs()
	while true:
		var orb: Dictionary = _orb_queue[0]
		var arrive := ladder.distance_of_beat(orb["beat"])
		if arrive - now > spawn:
			return
		_orb_queue.pop_front()
		if _orb_queue.is_empty():
			_plan_orbs()
		orb["arrive"] = arrive
		orb["z"] = now - arrive
		orb["id"] = _next_id
		_next_id += 1
		if orb["z"] <= REMOVE_Z:
			orbs.append(orb)
