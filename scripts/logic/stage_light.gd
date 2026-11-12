class_name StageLight
extends RefCounted
## 음악 단계가 오를 때 난간과 빛 대시가 밝아지는 계산 (자동 테스트 대상, ART_BIBLE.md 10장).

const ROAD_PEAK := 1.0    # 평소 대시의 가장 센 채널 상한
const PEAK_MAX := 1.6     # 밝기 순서: 단계 빛남이 가장 셀 때도 장애물 테두리(1.7 이상) 아래
const STAGE_BOOST := 0.6  # 단계 빛남이 평소 빛 세기에 더하는 비율


## 지금의 난간 빛 세기. base: 진하기의 빛 세기, stage: 단계 빛남(1 → 0)
static func energy(base: float, stage: float) -> float:
	return minf(base * (1.0 + STAGE_BOOST * stage), PEAK_MAX)


const WALL_HOLD := 0.15   # 고비 신호: 이만큼 가장 밝게 있다가
const WALL_FADE := 0.25   # 이만큼 동안 꺼진다 (모두 0.4초)


## 고비(v0.10.1) 신호의 빛남(1 → 0). age: 고비에 들어선 뒤 흐른 시간, 음수면 아직
static func wall_flash(age: float) -> float:
	if age < 0.0 or age >= WALL_HOLD + WALL_FADE:
		return 0.0
	return 1.0 if age < WALL_HOLD else 1.0 - (age - WALL_HOLD) / WALL_FADE
