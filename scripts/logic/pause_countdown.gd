class_name PauseCountdown
extends RefCounted
## 일시정지에서 이어 하기: 3 → 2 → 1을 한 박 간격으로 보이고 음악을 멈췄던 자리에서 다시 튼다 (자동 테스트 대상).
## 멈춘 자리가 박 사이(phase)여도 숫자의 박과 음악의 박이 이어지게, 음악은 "1" 뒤 (phase × 박)에 다시 튼다:
## 그러면 다음 음악 박이 "1"에서 정확히 한 박 뒤에 온다 (숫자 3·2·1 → 음악 박이 같은 간격으로 이어짐).

const COUNT := 3

var beat := 0.6     # 한 박(초)
var phase := 0.0    # 멈춘 자리가 지난 박에서 얼마나 지났나 (0~1 박)


func _init(beat_time: float, beat_phase: float) -> void:
	beat = beat_time
	phase = fposmod(beat_phase, 1.0)


## 음악을 다시 트는 시각 (이어 하기를 누른 뒤 초)
func resume_at() -> float:
	return (COUNT - 1 + phase) * beat


## 이어 하기를 누른 뒤 elapsed초에 보일 숫자. 3, 2, 1, 음악을 다시 틀었으면 0
func digit(elapsed: float) -> int:
	if elapsed >= resume_at():
		return 0
	return COUNT - mini(floori(elapsed / beat), COUNT - 1)


func done(elapsed: float) -> bool:
	return elapsed >= resume_at()
