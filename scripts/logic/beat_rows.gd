class_name BeatRows
extends RefCounted
## 레인 경계 물방울 줄의 자리와 부풂 (자동 테스트 대상). 장애물과 같은 "이동 거리"를 쓰므로 템포가 바뀌어도 줄은 박에 주인공 옆에 닿는다.
## 줄 z = 이동 거리 - 박 × 한 박 거리. 격자가 반복되므로 노드 하나를 offset()만큼만 옮기면 모든 줄이 맞는다.

## 반 박 간격. 짝수 번째 줄이 박 줄, 홀수 번째 줄이 반 박 줄 (작은 물방울)
const GAP := MusicLadder.BEAT_DISTANCE * 0.5
const FIRST := -1   # 카메라 아래까지 덮는 첫 줄 번호
const LAST := 22    # 안개 속 마지막 줄 번호: 이보다 먼 줄은 어차피 보이지 않는다 (droplet.gdshader의 사라지는 거리)
const SMALL_SCALE := 0.6  # 반 박 물방울 크기 배율
const PULSE_SIZE := 0.15  # 박마다 부푸는 양
const PULSE_TIME := 0.15  # 부풀었다 돌아오는 시간(초)


## 물방울 노드의 z. 이동 거리에 따라 0 이상 한 박 거리 미만에서 되풀이한다.
static func offset(travel: float) -> float:
	return fposmod(travel, MusicLadder.BEAT_DISTANCE)


## 노드 안에서 줄의 z (offset이 0일 때의 자리)
static func row_z(row: int) -> float:
	return -GAP * row


static func is_beat_row(row: int) -> bool:
	return posmod(row, 2) == 0


## 지난 박에서 age초 지났을 때의 크기 배율. 박 직후 빠르게 부풀고 천천히 돌아온다.
static func pulse(age: float) -> float:
	if age < 0.0 or age >= PULSE_TIME:
		return 1.0
	return 1.0 + PULSE_SIZE * sin(PI * sqrt(age / PULSE_TIME))
