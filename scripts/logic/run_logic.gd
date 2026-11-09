class_name RunLogic
extends RefCounted
## 화면과 분리된 달리기 계산 (레인 이동, 레인 좌표, 거리). 자동 테스트 대상.

const LANE_COUNT := 3
const LANE_WIDTH := 1.5
const START_LANE := 1
## 시작(100BPM) 때 세상이 다가오는 속도 (월드 단위/초). 단계별 속도는 MusicLadder.STEPS
const SPEED := 15.0


## 레인 번호를 방향(-1 왼쪽, +1 오른쪽)만큼 옮긴다. 0~2 밖으로는 나가지 않는다.
static func move_lane(lane: int, direction: int) -> int:
	return clampi(lane + signi(direction), 0, LANE_COUNT - 1)


## 레인 번호의 가로 좌표 (가운데 레인이 0)
static func lane_x(lane: int) -> float:
	return (lane - (LANE_COUNT - 1) / 2.0) * LANE_WIDTH
