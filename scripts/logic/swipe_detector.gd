class_name SwipeDetector
extends RefCounted
## 스와이프 판정. 손가락을 떼기 전에, 임계 거리를 넘는 순간 바로 방향을 돌려준다.
## 화면 좌표(720x1280 기준 픽셀)로 계산하며, Godot 입력과 분리되어 있어 자동 테스트가 가능하다.

enum Dir { NONE, LEFT, RIGHT, UP, DOWN }

## 이 거리(픽셀)보다 많이 움직여야 스와이프로 본다
const MIN_DISTANCE := 48.0
## 주된 축 이동이 다른 축 이동의 이 배수 이상이어야 한다 (대각선은 무시)
const DOMINANCE := 1.5

var _active := false
var _origin := Vector2.ZERO


## 이동량(delta)이 스와이프인지, 어느 방향인지 판정한다.
static func classify(delta: Vector2, min_distance: float = MIN_DISTANCE, dominance: float = DOMINANCE) -> Dir:
	var ax := absf(delta.x)
	var ay := absf(delta.y)
	if maxf(ax, ay) < min_distance:
		return Dir.NONE
	if ax >= ay * dominance:
		return Dir.RIGHT if delta.x > 0.0 else Dir.LEFT
	if ay >= ax * dominance:
		return Dir.DOWN if delta.y > 0.0 else Dir.UP
	return Dir.NONE


## 손가락을 댔다
func press(pos: Vector2) -> void:
	_active = true
	_origin = pos


## 손가락이 움직였다. 스와이프가 완성되면 방향을 돌려주고 기준점을 현재 위치로 옮겨,
## 손가락을 떼지 않고도 이어서 다시 스와이프할 수 있게 한다.
func move(pos: Vector2) -> Dir:
	if not _active:
		return Dir.NONE
	var dir := classify(pos - _origin)
	if dir != Dir.NONE:
		_origin = pos
	return dir


## 손가락을 뗐다
func release() -> void:
	_active = false
