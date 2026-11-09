class_name CrashMotion
extends RefCounted
## 충돌 모션의 시간표와 붙을 자리 계산 (ART_BIBLE.md 2-5 원칙 7). 화면과 분리되어 있어 자동 테스트 대상.
## 느려짐 → 장애물 면에 찰싹 붙음 → 잠깐 붙어 있음 → 흘러내려 웅덩이 → 멈춤

const SLOW_TIME := 0.12    # 세상이 아주 느려지는 시간(초)
const SLOW_SCALE := 0.1    # 느려지는 동안 세상 속도 배율
const SLOW_STICK := 0.35   # 느려지는 동안 찌그러지는 정도 (나머지는 끝나는 순간 한 번에 찰싹)
const SNAP_TIME := 0.06    # 찰싹 붙는 시간(초)
const FLOW_START := 0.3    # 흘러내리기 시작
const FLOW_END := 0.85     # 웅덩이가 되어 멈춤
const SHAKE_TIME := 0.18   # 화면 흔들림 시간(초): 찰싹 붙는 순간 시작
const SHAKE_SIZE := 0.05   # 화면 흔들림 크기(m)
const BODY_REACH := 0.5    # 주인공 반폭: 어느 면에 붙을지 정할 때 쓴다
const BODY_MIDDLE := 0.4   # 주인공 몸 가운데 높이 (키 0.8의 절반)
const TALL := {ObstacleField.Kind.BLOCK: 1.3, ObstacleField.Kind.LOW: 0.85, ObstacleField.Kind.HIGH: 1.1}  # 붙었을 때 키 배율 (허들은 낮아서 작게)


## 몸이 붙을 자리. ox·rx = 장애물·주인공 x, z = 장애물 z (주인공은 z=0 근처), lift = 뜬 높이.
## 앞·뒤·옆면 중 가장 조금 움직여 닿는 면에 붙는다 (앞으로 달리다 = 앞면, 레인 이동 중 = 옆면, 넘어가다 뒷부분에 걸림 = 뒷면).
## 돌려주는 값 normal: 면 바깥쪽, face: 면의 좌표, along: 면을 따라가는 좌표, y: 붙는 높이(몸 가운데), tall: 키 배율
static func contact(kind: ObstacleField.Kind, ox: float, rx: float, z: float, lift: float) -> Dictionary:
	var half_x: float = ObstacleField.BLOCK_SIZE * 0.5 if kind == ObstacleField.Kind.BLOCK else ObstacleField.BAR_WIDTH * 0.5
	var half_z: float = ObstacleField.BLOCK_SIZE * 0.5 if kind == ObstacleField.Kind.BLOCK else ObstacleField.BAR_DEPTH * 0.5
	var bottom := 0.0
	var top := ObstacleField.BLOCK_HEIGHT
	if kind == ObstacleField.Kind.LOW:
		top = ObstacleField.LOW_TOP
	elif kind == ObstacleField.Kind.HIGH:
		bottom = ObstacleField.HIGH_BOTTOM
		top = ObstacleField.HIGH_TOP
	var dx := rx - ox
	var front := z + half_z + BODY_REACH
	var back := BODY_REACH - (z - half_z)
	var side := BODY_REACH + half_x - absf(dx)
	var result := {"y": clampf(lift + BODY_MIDDLE, bottom, top), "tall": TALL[kind]}
	if side < minf(front, back):
		result["normal"] = Vector3(signf(dx), 0.0, 0.0)
		result["face"] = ox + signf(dx) * half_x
		result["along"] = clampf(0.0, z - half_z, z + half_z)
	else:
		result["normal"] = Vector3(0.0, 0.0, 1.0 if front <= back else -1.0)
		result["face"] = z + half_z if front <= back else z - half_z
		result["along"] = ox + clampf(dx, -half_x, half_x)
	return result


## 면에 붙은 정도 0~1 (찰싹 붙을 때 살짝 넘친다)
static func stick(t: float) -> float:
	if t < SLOW_TIME:
		return SLOW_STICK * t / SLOW_TIME
	var u := minf((t - SLOW_TIME) / SNAP_TIME, 1.0) - 1.0
	return lerpf(SLOW_STICK, 1.0, 1.0 + 2.2 * u * u * u + 1.2 * u * u)


## 흘러내려 웅덩이가 된 정도 0~1
static func flow(t: float) -> float:
	return smoothstep(FLOW_START, FLOW_END, t)


## 지금 프레임(t부터 delta초)에서 세상이 움직일 시간 (느려지는 구간만, 그 뒤엔 0)
static func slow_delta(t: float, delta: float) -> float:
	return clampf(SLOW_TIME - t, 0.0, delta) * SLOW_SCALE


## 화면 흔들림 (찰싹 붙는 순간 짧고 작게 1회, 점점 잦아듦)
static func shake(t: float) -> Vector2:
	var u := (t - SLOW_TIME) / SHAKE_TIME
	if u < 0.0 or u >= 1.0:
		return Vector2.ZERO
	return Vector2(sin(TAU * u * 2.0), 0.6 * sin(TAU * u * 3.0)) * SHAKE_SIZE * (1.0 - u)
