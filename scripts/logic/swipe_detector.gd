class_name SwipeDetector
extends RefCounted
## 스와이프 판정. 손가락을 떼기 전에, 임계 거리를 넘는 순간 바로 방향을 돌려준다.
## 스와이프 한 번 = 한 동작: 손가락을 대고 뗄 때까지 첫 판정 한 번만 돌려주고 이후 움직임은 무시한다.
## 손가락(터치 번호)마다 따로 판정하므로, 다른 손가락이 새로 스와이프하면 그것도 한 동작으로 인정한다.
## 화면 좌표(720x1280 기준 픽셀)로 계산하며, Godot 입력과 분리되어 있어 자동 테스트가 가능하다.

enum Dir { NONE, LEFT, RIGHT, UP, DOWN }

## 이 거리(픽셀)보다 많이 움직여야 스와이프로 본다
const MIN_DISTANCE := 48.0
## 주된 축 이동이 다른 축 이동의 이 배수 이상이어야 한다 (대각선은 무시)
const DOMINANCE := 1.5

var _origins := {}  # 터치 번호 -> 누른 위치. 이미 판정을 돌려준 손가락은 지운다(뗄 때까지 무시)


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
func press(pos: Vector2, index: int = 0) -> void:
	_origins[index] = pos


## 손가락이 움직였다. 스와이프가 완성되면 방향을 한 번만 돌려주고, 그 손가락은 뗄 때까지 무시한다.
func move(pos: Vector2, index: int = 0) -> Dir:
	if not _origins.has(index):
		return Dir.NONE
	var dir := classify(pos - _origins[index])
	if dir != Dir.NONE:
		_origins.erase(index)
	return dir


## 손가락을 뗐다
func release(index: int = 0) -> void:
	_origins.erase(index)
