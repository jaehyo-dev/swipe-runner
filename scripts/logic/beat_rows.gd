class_name BeatRows
extends RefCounted
## 레인 경계 빛 대시 줄의 자리와 박 밝기 (자동 테스트 대상). 장애물과 같은 "이동 거리"를 쓰므로 템포가 바뀌어도 줄은 박에 주인공 옆에 닿는다.
## 줄 z = 이동 거리 - 그 박의 이동 거리. 템포가 오르면 줄 간격이 달라지므로 간격을 고정하지 않고 매 프레임 계산한다.

const COUNT := 12   # 박 거리마다 한 줄: 첫 줄은 카메라 뒤, 끝 줄은 안개 속 (dash.gdshader의 사라지는 거리)
const BEHIND := 1   # 지금 박보다 이만큼 앞선 박부터 놓는다
const PULSE_TIME := 0.15  # 박에 밝아졌다 돌아오는 시간(초)


## 자리 index(0~COUNT-1)의 박
static func beat_of(index: int, now_beat: float) -> float:
	return floorf(now_beat) - BEHIND + index


## 박 beat의 줄을 담는 칸. 줄은 고리처럼 돌려 쓰므로 박이 지나도 앞으로 올 줄의 값은 그대로다.
static func slot_of(beat: float) -> int:
	return posmod(roundi(beat), COUNT)


## 음악 시간 t에 박 beat 줄의 z
static func row_z(ladder: MusicLadder, t: float, beat: float) -> float:
	return ladder.distance_at(t) - ladder.distance_of_beat(beat)


## 지난 박에서 age초 지났을 때의 밝기(0~1). 박 직후 바로 밝고 천천히 돌아온다.
static func pulse(age: float) -> float:
	if age < 0.0 or age >= PULSE_TIME:
		return 0.0
	return sin(PI * sqrt(age / PULSE_TIME))
