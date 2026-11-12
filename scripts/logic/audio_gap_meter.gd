class_name AudioGapMeter
extends RefCounted
## 오디오 끊김 추정 (화면과 분리, 자동 테스트 대상, v0.11.2).
## 소리가 제때 만들어지지 못하면(버퍼 부족) 오디오 시계가 그만큼 서고 실제 시계만 흐른다.
## 그래서 (오디오 출력 시각 − 실제 시각)이 한 묶음(약 0.5초)의 최댓값 기준으로 DROP_MS 넘게 줄면 끊김 한 번으로 센다.
## 최댓값을 쓰는 까닭: WebKit은 오디오 시각이 10~40ms 계단으로 움직여 프레임마다 보면 흔들린다. 묶음 안 최댓값은 흔들리지 않는다.

const DROP_MS := 15.0   # 이보다 크게 밀리면 끊김
const SPAN := 10.0      # 최근 이만큼(초)의 끊김 수를 보인다

var _base := NAN
var _times: Array[float] = []


## peak: 지난 묶음의 (오디오 출력 시각 − 실제 시각) 최댓값(ms). null이면 그 사이 멈춤·일시정지가 있었다 → 기준을 새로 잡는다
func push(peak: Variant, now: float) -> void:
	if peak == null:
		_base = NAN
		return
	if not is_nan(_base) and _base - float(peak) > DROP_MS:
		_times.append(now)
	_base = float(peak)


## 최근 SPAN초 끊김 수
func count(now: float) -> int:
	while not _times.is_empty() and now - _times[0] > SPAN:
		_times.pop_front()
	return _times.size()


## 성능 표시 오디오 두 줄. rate: 출력 표본율(Hz), latency: 출력 지연(초), gaps: 끊김 수(-1이면 잴 수 없음)
static func text(rate: float, latency: float, gaps: int) -> String:
	return "AUDIO %.1fkHz\n%.0f ms · GAP %s/10s" % [rate / 1000.0, latency * 1000.0, str(gaps) if gaps >= 0 else "-"]
