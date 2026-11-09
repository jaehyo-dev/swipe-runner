class_name BeatRows
extends RefCounted
## 레인 경계 물방울 줄의 자리와 부풂 (자동 테스트 대상). 장애물과 같은 "이동 거리"를 쓰므로 템포가 바뀌어도 줄은 박에 주인공 옆에 닿는다.
## 줄 z = 이동 거리 - 그 박의 이동 거리. 템포가 오르면 줄 간격이 달라지므로 간격을 고정하지 않고 매 프레임 계산한다.

const COUNT := 24   # 반 박 간격 줄 수: 첫 줄은 카메라 뒤, 끝 줄은 안개 속 (droplet.gdshader의 사라지는 거리)
const BEHIND := 1   # 지금 박보다 이만큼 앞선 박부터 놓는다
const SMALL_SCALE := 0.6  # 반 박 물방울 크기 배율
const PULSE_SIZE := 0.15  # 박마다 부푸는 양
const PULSE_TIME := 0.15  # 부풀었다 돌아오는 시간(초)


## 자리 index(0~COUNT-1)의 박. 짝수 자리가 항상 박 줄, 홀수 자리가 반 박 줄이다.
static func beat_of(index: int, now_beat: float) -> float:
	return floorf(now_beat) - BEHIND + index * 0.5


## 박 beat(반 박 포함)의 줄을 담는 칸. 줄은 고리처럼 돌려 쓰므로 박이 지나도 앞으로 올 줄의 값은 그대로다.
static func slot_of(beat: float) -> int:
	return posmod(roundi(beat * 2.0), COUNT)


static func is_beat_row(index: int) -> bool:
	return posmod(index, 2) == 0


## 음악 시간 t에 박 beat 줄의 z
static func row_z(ladder: MusicLadder, t: float, beat: float) -> float:
	return ladder.distance_at(t) - ladder.distance_of_beat(beat)


## 지난 박에서 age초 지났을 때의 크기 배율. 박 직후 빠르게 부풀고 천천히 돌아온다.
static func pulse(age: float) -> float:
	if age < 0.0 or age >= PULSE_TIME:
		return 1.0
	return 1.0 + PULSE_SIZE * sin(PI * sqrt(age / PULSE_TIME))
