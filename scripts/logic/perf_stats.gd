class_name PerfStats
extends RefCounted
## 숨은 성능 표시의 계산 (화면과 분리, 자동 테스트 대상): 최근 1초 프레임 통계, 화면 주사율 추정, 왼쪽 위 세 번 탭.

const WINDOW := 1.0         # 최근 이만큼(초)의 프레임으로 FPS·평균·최대
const TAP_GAP := 0.4        # 세 번 탭: 탭 사이가 이보다 짧아야 이어진 탭
const RATES := [30, 60, 90, 120, 144]  # 흔한 화면 주사율. 가장 가까운 값을 고른다
## 왼쪽 위 탭 자리 (720 폭 기준 UI 좌표): 일시정지·집 버튼(20~116) 오른쪽 옆. 그 버튼들과 겹치지 않는다
const TAP_ZONE := Rect2(124.0, 0.0, 150.0, 124.0)

var _frames: Array[float] = []
var _sum := 0.0
var _taps: Array[float] = []


## 프레임 시간(초)을 넣는다. 최근 WINDOW초만 남긴다
func push(frame: float) -> void:
	_frames.append(frame)
	_sum += frame
	while _frames.size() > 1 and _sum - _frames[0] >= WINDOW:
		_sum -= _frames.pop_front()


func fps() -> float:
	return _frames.size() / _sum if _sum > 0.0 else 0.0


func average() -> float:
	return _sum / _frames.size() if not _frames.is_empty() else 0.0


func worst() -> float:
	return _frames.max() if not _frames.is_empty() else 0.0


## 화면 주사율 추정: 프레임 간격의 중앙값에 가장 가까운 흔한 주사율 (밀린 프레임에 흔들리지 않게 중앙값)
func refresh_rate() -> int:
	if _frames.is_empty():
		return 0
	var sorted := _frames.duplicate()
	sorted.sort()
	var hz: float = 1.0 / sorted[sorted.size() / 2]
	var best: int = RATES[0]
	for rate: int in RATES:
		if absf(rate - hz) < absf(best - hz):
			best = rate
	return best


## 탭 자리를 눌렀다 (시각 초). 빠르게 세 번째 탭이면 true (표시를 켜거나 끈다)
func tap(now: float) -> bool:
	if not _taps.is_empty() and now - _taps[-1] > TAP_GAP:
		_taps.clear()
	_taps.append(now)
	if _taps.size() < 3:
		return false
	_taps.clear()
	return true


## 표시 글자 두 줄 (점수 숫자 위에 들어가게 짧게). render: 3D를 그리는 해상도, level: 효과 단계, setting: GRAPHICS, dpr: 기기 배율
## 프레임은 최근 1초 평균 / 최대 ms
func text(render: Vector2i, level: int, setting: String, dpr: float) -> String:
	return "FPS %.0f · %dHz · %.1f / %.1f ms\n3D %dx%d · Q%d %s · DPR %.2f" % [
		fps(), refresh_rate(), average() * 1000.0, worst() * 1000.0, render.x, render.y, level, setting.to_upper(), dpr]
