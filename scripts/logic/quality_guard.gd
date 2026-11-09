class_name QualityGuard
extends RefCounted
## 렉 줄이기 계산 (자동 테스트 대상). 3D를 그리는 해상도 상한과, 프레임이 밀릴 때 효과를 한 단계씩 낮추는 판단을 맡는다.
## 낮춘 단계는 다시 올리지 않는다: 오르내리면 화면이 깜빡인다.

const MAX_HEIGHT := 1920.0    # 세로 1280 × 기기 화소 1.5배
const MAX_PIXELS := 2880.0 * 1620.0  # 맥북 전체 화면처럼 가로로 넓은 창은 세로 상한만으로 부족하다 (review/v0.5.1/perf_mac.md)
const WINDOW := 2.0           # 이만큼의 프레임을 모아 판단한다(초)
const LIMIT := 0.020          # 이 구간의 99% 프레임이 이보다 길면 한 단계 낮춘다(초)
const IGNORE_OVER := 0.25     # 탭 전환 같은 긴 멈춤은 렉이 아니다
const LEVELS := 4             # 1 빛 줄기 줄이기, 2 반사 끄기, 3 MSAA 2x, 4 빛 번짐 낮추기
const STREAK_LOW := 0.35      # 1단계부터 빛 줄기를 이 비율로

var level := 0

var _frames: Array[float] = []
var _sum := 0.0


## 창 크기(실제 화소)에서 3D를 그릴 배율. 글자는 이 배율과 상관없이 원래 해상도로 그려진다.
static func render_scale(size: Vector2i) -> float:
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return minf(minf(1.0, MAX_HEIGHT / size.y), sqrt(MAX_PIXELS / (size.x * size.y)))


## 품질 단계 level에서 그릴 빛 줄기 수
static func streaks(count: float, at_level: int) -> int:
	return int(count * (STREAK_LOW if at_level >= 1 else 1.0))


## 프레임 시간(초)을 넣는다. 이번에 단계를 낮췄으면 true
func push(frame: float) -> bool:
	if level >= LEVELS:
		return false
	if frame > IGNORE_OVER:
		_frames.clear()
		_sum = 0.0
		return false
	_frames.append(frame)
	_sum += frame
	if _sum < WINDOW:
		return false
	_frames.sort()
	var slow: bool = _frames[int((_frames.size() - 1) * 0.99)] > LIMIT
	_frames.clear()
	_sum = 0.0
	if slow:
		level += 1
	return slow
