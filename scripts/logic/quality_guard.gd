class_name QualityGuard
extends RefCounted
## 렉 줄이기 계산 (자동 테스트 대상). 3D를 그리는 해상도 상한과, 프레임이 밀릴 때 효과를 한 단계씩 낮추는 판단을 맡는다.
## 낮춘 단계는 다시 올리지 않는다: 오르내리면 화면이 깜빡인다.

const MAX_HEIGHT := 1920.0    # 세로 1280 × 기기 화소 1.5배
const MAX_PIXELS := 2880.0 * 1620.0  # 맥북 전체 화면처럼 가로로 넓은 창은 세로 상한만으로 부족하다 (review/v0.5.1/perf_mac.md)
const WINDOW := 1.0           # 이만큼(초)의 프레임을 모아 한 번 판단한다
const LIMIT := 0.020          # 한 구간의 99% 프레임이 이보다 길면 느린 구간
const SLOW_WINDOWS := 3       # 느린 구간이 이만큼 연속(3초)일 때만 한 단계 낮춘다
const GRACE := 5.0            # 페이지를 연 뒤, 탭이 가려졌다 돌아온 뒤, 화면 전환·단계를 낮춘 뒤 이 시간(초)은 판단하지 않는다
const IGNORE_OVER := 0.25     # 이보다 긴 멈춤은 탭 전환 같은 것이라 렉이 아니다 (돌아온 뒤 GRACE만큼 쉰다)
const LEVELS := 4             # 1 빛 줄기 줄이기, 2 반사 끄기, 3 MSAA 2x, 4 빛 번짐 낮추기
const STREAK_LOW := 0.35      # 1단계부터 빛 줄기를 이 비율로

var level := 0
## 마지막으로 낮춘 이유 (콘솔 기록용): 연속 구간들의 99% 프레임
var reason := ""

var _frames: Array[float] = []
var _sum := 0.0
var _grace := GRACE
var _slow: Array[float] = []  # 연속된 느린 구간의 99% 프레임(초)


## 창 크기(실제 화소)에서 3D를 그릴 배율. 글자는 이 배율과 상관없이 원래 해상도로 그려진다.
static func render_scale(size: Vector2i) -> float:
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return minf(minf(1.0, MAX_HEIGHT / size.y), sqrt(MAX_PIXELS / (size.x * size.y)))


## 품질 단계 level에서 그릴 빛 줄기 수
static func streaks(count: float, at_level: int) -> int:
	return int(count * (STREAK_LOW if at_level >= 1 else 1.0))


## seconds초 동안 판단하지 않는다. 모으던 구간과 연속 기록도 버린다
func hold(seconds := GRACE) -> void:
	_grace = maxf(_grace, seconds)
	_frames.clear()
	_sum = 0.0
	_slow.clear()


## 프레임 시간(초)을 넣는다. 이번에 단계를 낮췄으면 true (이유는 reason)
func push(frame: float) -> bool:
	if level >= LEVELS:
		return false
	if frame > IGNORE_OVER:
		hold()
		return false
	if _grace > 0.0:
		_grace -= frame
		return false
	_frames.append(frame)
	_sum += frame
	if _sum < WINDOW:
		return false
	_frames.sort()
	var p99 := _frames[int((_frames.size() - 1) * 0.99)]
	_frames.clear()
	_sum = 0.0
	if p99 <= LIMIT:
		_slow.clear()
		return false
	_slow.append(p99)
	if _slow.size() < SLOW_WINDOWS:
		return false
	level += 1
	reason = "99%% 프레임 %s ms가 %d초 연속 %.0fms 초과" % [", ".join(_slow.map(func(x: float) -> String: return "%.1f" % (x * 1000.0))), SLOW_WINDOWS, LIMIT * 1000.0]
	hold()  # 낮춘 직후의 셰이더 준비 끊김으로 연달아 낮추지 않게
	return true
