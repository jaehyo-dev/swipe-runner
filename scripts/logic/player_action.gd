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
## 공중 아래 스와이프로 땅까지 떨어지는 시간: 낮은 곳 ~ 최고 높이 (단, 원래 착지까지 남은 시간보다 길어지지 않는다)
const DROP_MIN_TIME := 0.1
const DROP_MAX_TIME := 0.15
## 점프·슬라이드 중 미리 받아 두는 입력의 유효 시간(초)
const BUFFER_TIME := 0.15

enum Buffered { NONE, JUMP, SLIDE }

var _jump_t := -1.0   # 음수 = 안 하는 중
var _slide_t := -1.0
var _slide_from_drop := false  # 떨어지다 바로 이어진 슬라이드: 시작부터 낮아져 있다
var _drop_t := -1.0   # 공중 아래 스와이프로 떨어지는 중 (이때 _jump_t는 멈춰 있고 is_jumping은 참)
var _drop_from := 0.0
var _drop_time := 0.0
var _buffer := Buffered.NONE  # 저장된 입력은 하나뿐, 새 입력이 덮어쓴다
var _buffer_age := 0.0
var _sounds: Array[StringName] = []  # 일어난 순서대로, 화면이 꺼내 재생한다


## 지난번 이후 일어난 동작의 소리("jump", "slide", "land")를 꺼낸다.
func take_sounds() -> Array[StringName]:
	var sounds := _sounds
	_sounds = []
	return sounds


func is_jumping() -> bool:
	return _jump_t >= 0.0


func is_sliding() -> bool:
	return _slide_t >= 0.0


func is_dropping() -> bool:
	return _drop_t >= 0.0


## 점프. 공중이면 착지 때 쓰도록 저장하고, 슬라이드 중이면 슬라이드를 끊고 뛴다.
func jump() -> void:
	if is_jumping():
		_store(Buffered.JUMP)
		return
	_start_jump()


## 슬라이드. 공중이면 빠르게 떨어져 닿자마자 슬라이드로 이어지고, 이미 슬라이드 중이면 끝날 때 쓰도록 저장한다.
func slide() -> void:
	if is_dropping() or is_sliding():
		_store(Buffered.SLIDE)
	elif is_jumping():
		_start_drop()
	else:
		_start_slide(false)


func step(dt: float) -> void:
	_buffer_age += dt
	if is_dropping():
		_drop_t += dt
		if _drop_t >= _drop_time:
			_drop_t = -1.0
			_jump_t = -1.0
			# 떨어지는 동안 위로 밀었으면 그 입력이 슬라이드를 덮어쓴다
			if _take_buffer() == Buffered.JUMP:
				_start_jump()
			else:
				_start_slide(true)
	elif is_jumping():
		_jump_t += dt
		if _jump_t >= JUMP_TIME:
			_jump_t = -1.0
			_sounds.append(&"land")
			_run_buffer()
	elif is_sliding():
		_slide_t += dt
		if _slide_t >= SLIDE_TIME:
			_slide_t = -1.0
			_run_buffer()


func _store(action: Buffered) -> void:
	_buffer = action
	_buffer_age = 0.0


## 저장된 입력을 꺼낸다. 유효 시간이 지났으면 없는 것으로 본다.
func _take_buffer() -> Buffered:
	var action := _buffer if _buffer_age <= BUFFER_TIME else Buffered.NONE
	_buffer = Buffered.NONE
	return action


func _run_buffer() -> void:
	match _take_buffer():
		Buffered.JUMP:
			_start_jump()
		Buffered.SLIDE:
			_start_slide(false)


func _start_jump() -> void:
	_buffer = Buffered.NONE
	_slide_t = -1.0
	_jump_t = 0.0
	_sounds.append(&"jump")


func _start_slide(from_drop: bool) -> void:
	_buffer = Buffered.NONE
	_slide_t = 0.0
	_slide_from_drop = from_drop
	_sounds.append(&"slide")


func _start_drop() -> void:
	_buffer = Buffered.NONE
	_drop_from = height()
	_drop_t = 0.0
	_drop_time = minf(lerpf(DROP_MIN_TIME, DROP_MAX_TIME, _drop_from / JUMP_HEIGHT), JUMP_TIME - _jump_t)


## 지금 땅에서 떠 있는 높이 (포물선. 떨어지는 중엔 점점 빨라짐)
func height() -> float:
	if is_dropping():
		var d := _drop_t / _drop_time
		return _drop_from * (1.0 - d * d)
	if not is_jumping():
		return 0.0
	var u := _jump_t / JUMP_TIME
	return JUMP_HEIGHT * 4.0 * u * (1.0 - u)


## 몸이 낮아진 정도 0~1 (시작·끝은 부드럽게)
func crouch() -> float:
	if not is_sliding():
		return 0.0
	var end := (SLIDE_TIME - _slide_t) / SLIDE_FADE
	return clampf(end if _slide_from_drop else minf(_slide_t / SLIDE_FADE, end), 0.0, 1.0)


## 막대 아래를 지나갈 수 있는 상태인가 (낮아지는 중이면 아직 아님).
## 공중 아래 스와이프는 입력한 순간부터 지나갈 수 있다: 슬라이드로 들어가겠다는 입력이 받아들여졌는데 떨어지는 0.15초 때문에 죽으면 억울하다
func is_ducking() -> bool:
	return is_dropping() or crouch() >= 1.0


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


## 공중 아래 스와이프 순간 이미 넘고 있던 허들인가. 이런 허들은 내려오다 닿아도 부딪힌 것으로 치지 않는다.
static func clears_on_drop(kind: ObstacleField.Kind, dx: float, dz: float, jump_height: float) -> bool:
	return kind == ObstacleField.Kind.LOW and absf(dx) <= HIT_X and absf(dz) <= HIT_Z and jump_height >= ObstacleField.LOW_TOP
