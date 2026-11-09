class_name StageLight
extends RefCounted
## 레이저 번쩍임 계산 (자동 테스트 대상, ART_BIBLE.md 10장). 박마다 살짝, 마디 첫 박에 크게, 음악 단계가 오를 때 전체가 번쩍인다.

const BEAT_BOOST := 0.35   # 박마다 더하는 비율
const BAR_BOOST := 1.0     # 마디 첫 박에 더하는 비율
const STAGE_BOOST := 1.6   # 음악 단계가 오를 때 더하는 비율
const FLASH_DECAY := 0.18  # 박의 번쩍임이 사라지는 시간(초)
const PEAK_MAX := 1.0      # 밝기 순서: 어떤 번쩍임에도 레이저의 가장 센 채널이 1을 넘지 않아 색이 희게 날아가지 않는다 (장애물 테두리 1.7 아래)


## 박 번호 beat(소수)에서 번쩍임 비율. 음악 시작 전(음수)에는 없다.
static func beat_flash(beat: float, beat_time: float) -> float:
	if beat < 0.0:
		return 0.0
	var age := fposmod(beat, 1.0) * beat_time
	var boost := BAR_BOOST if posmod(int(beat), BeatClock.BEATS_PER_BAR) == 0 else BEAT_BOOST
	return boost * maxf(1.0 - age / FLASH_DECAY, 0.0)


## 지금의 레이저 빛 세기. base: 진하기의 빛 세기, flash: 박 번쩍임, stage: 단계 빛남(1 → 0), color_peak: 레이저 색의 가장 센 채널
static func energy(base: float, flash: float, stage: float, color_peak: float) -> float:
	return minf(base * (1.0 + flash + STAGE_BOOST * stage), PEAK_MAX / color_peak)
