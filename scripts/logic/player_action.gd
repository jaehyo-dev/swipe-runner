class_name PlayerAction
extends RefCounted
## 주인공의 점프·슬라이드 상태와 충돌 판정. 화면과 분리되어 있어 자동 테스트 대상.

const JUMP_TIME := 0.6
const JUMP_HEIGHT := 1.6
const SLIDE_TIME := 0.65
const SLIDE_FADE := 0.08   # 슬라이드 시작·끝에서 몸이 낮아지고 돌아오는 시간
## 슬라이드 중 몸 높이 배율 (1.0 * 0.45 = 0.45 < HIGH_BOTTOM)
const CROUCH_SCALE := 0.45
## 충돌 범위: 장애물 반폭 + 주인공 반폭 정도로, 조금 너그럽게 잡았다
const HIT_X := 0.7
const HIT_Z := 0.7

var _jump_t := -1.0   # 음수 = 안 하는 중
var _slide_t := -1.0


func is_jumping() -> bool:
	return _jump_t >= 0.0


func is_sliding() -> bool:
	return _slide_t >= 0.0


## 점프. 이미 점프 중이면 무시, 슬라이드 중이면 슬라이드를 끊고 뛴다.
func jump() -> void:
	if is_jumping():
		return
	_slide_t = -1.0
	_jump_t = 0.0


## 슬라이드. 점프 중이거나 이미 슬라이드 중이면 무시.
func slide() -> void:
	if is_jumping() or is_sliding():
		return
	_slide_t = 0.0


func step(dt: float) -> void:
	if is_jumping():
		_jump_t += dt
		if _jump_t >= JUMP_TIME:
			_jump_t = -1.0
	if is_sliding():
		_slide_t += dt
		if _slide_t >= SLIDE_TIME:
			_slide_t = -1.0


## 지금 땅에서 떠 있는 높이 (포물선)
func height() -> float:
	if not is_jumping():
		return 0.0
	var u := _jump_t / JUMP_TIME
	return JUMP_HEIGHT * 4.0 * u * (1.0 - u)


## 몸이 낮아진 정도 0~1 (시작·끝은 부드럽게)
func crouch() -> float:
	if not is_sliding():
		return 0.0
	return clampf(minf(_slide_t, SLIDE_TIME - _slide_t) / SLIDE_FADE, 0.0, 1.0)


## 낮아진 몸이 장애물 아래를 지나갈 수 있는 상태인가 (낮아지는 중이면 아직 아님)
func is_ducking() -> bool:
	return crouch() >= 1.0


## 장애물이 주인공과 부딪히는가. dx, dz는 둘 사이의 가로·앞뒤 거리.
static func hits(kind: ObstacleField.Kind, dx: float, dz: float, jump_height: float, ducking: bool) -> bool:
	if absf(dx) > HIT_X or absf(dz) > HIT_Z:
		return false
	match kind:
		ObstacleField.Kind.LOW:
			return jump_height < ObstacleField.LOW_TOP
		ObstacleField.Kind.HIGH:
			return not ducking
		_:
			return true
