class_name Runner
extends Node3D
## 주인공: 빛나는 푸딩 슬라임. 물방울 몸 한 덩어리 + 점 눈 두 개 (발·팔 없음).
## 레인 이동 트윈, 박자에 맞춘 눌림(바닥은 땅에 붙인 채), 윗부분이 늦게 따라오는 출렁임을 맡는다. 질감은 jelly.gdshader.

const BODY_RADIUS := 0.42           # 가장 넓은 곳의 반지름 (아래쪽에서 퍼짐)
const BODY_HEIGHT := 1.0            # 아래(0)에서 위 끝까지
const WIDEST_T := 0.3086            # 가장 넓은 높이 비율 (0.5^(1/0.6) 근처)
const FOOT_RATIO := 0.8             # 땅에 닿는 바닥 반지름 / 가장 넓은 반지름 (푸딩처럼 넓고 평평한 바닥)
const SQUASH_SCALE := 0.35 # 눌림·늘어남 폭 배율 (1.0 = v0.1.5 이전의 큰 눌림)
const MOVE_TIME := 0.18   # 레인 이동 시간(초): 처음과 끝이 부드러운 푸딩 같은 이동
const STEP_RATE := 9.0    # 튀는 박자 속도 (라디안/초)
## 레인 이동 출렁임: 윗부분을 바닥 가속도에 끌려가는 저감쇠 스프링으로 본다 (바닥이 먼저 가고 위가 늦게 따라옴).
## 결과는 셰이더의 높이별 기울기(위로 갈수록 크게)로 그린다.
const WOBBLE_GAIN := 0.45    # 출렁임 세기 (조절: 더 크게 흔들림=값↑). 0.45면 정수리가 최대 약 0.15 밀림
const WOBBLE_MAX := 0.2      # 정수리가 밀리는 최대 거리 (안전 한계)
const WOBBLE_STIFF := 1000.0 # 스프링 세기: 클수록 빠르게 출렁임 (1000 ≈ 초당 5번)
const WOBBLE_DAMP := 15.0    # 감쇠: 멈춘 뒤 2~3번 출렁이고 약 0.45초 안에 멈춤
const JELLY_STIFF := 170.0 # 눌림 스프링 세기
const JELLY_DAMP := 7.0    # 눌림 감쇠: 작게 둬서 착지 뒤 길쭉↔납작이 두어 번 출렁임
const SHADOW_SIZE := 1.9  # 발밑 판 지름: 접촉 그림자 + 몸 둘레 빛 고리 (세기·크기는 shadow.gdshader)

var _body: MeshInstance3D
var _shadow: MeshInstance3D
var _phase := 0.0
var _wobble := 0.0    # 윗부분이 바닥보다 옆으로 밀린 정도 (+ = 오른쪽)
var _wobble_vel := 0.0
var _prev_vx := 0.0
var _prev_x := 0.0
var _mat: ShaderMaterial
var _squish := 0.0    # 스프링으로 따라가는 눌림 정도 (0 = 보통, 1 = 가장 납작, 음수 = 길쭉하게 튕김)
var _squish_vel := 0.0
var _move_tween: Tween
## 점프로 뜬 높이와 슬라이드로 낮아진 정도(0~1). main이 매 프레임 넣어 준다.
var lift := 0.0
var crouch := 0.0
## false면 달리기 박자가 멈춘다 (게임 오버)
var running := true


## 아래는 넓고 평평한 푸딩 바닥, 위는 둥근 돔. 바닥이 y=0이라 눌려도 땅에 붙어 있다.
## 반지름: 바닥(t=0)은 가장 넓은 폭의 FOOT_RATIO로 평평하게 닿고, 1/4 타원 모서리로 가장 넓은 곳(t≈0.31)까지 둥글게 퍼지며,
## 그 위는 v0.2.1과 같은 타원 돔으로 닫는다. 바닥면은 따로 원판으로 막는다.
static func build_body_mesh(rings: int = 32, segments: int = 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in rings:
		var t0 := float(i) / rings
		var t1 := float(i + 1) / rings
		for j in segments:
			var a0 := TAU * j / segments
			var a1 := TAU * (j + 1) / segments
			var p00 := _blob_point(t0, a0)
			var p01 := _blob_point(t0, a1)
			var p10 := _blob_point(t1, a0)
			var p11 := _blob_point(t1, a1)
			# 바깥쪽이 앞면이 되는 감기 순서
			for v in [p00, p11, p10, p00, p01, p11]:
				st.add_vertex(v)
	# 바닥 원판: 옆면과 다른 스무딩 그룹이라 법선이 아래를 향하고, 옆면 법선을 끌어내리지 않는다
	st.set_smooth_group(1)
	for j in segments:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(_blob_point(0.0, TAU * (j + 1) / segments))
		st.add_vertex(_blob_point(0.0, TAU * j / segments))
	st.generate_normals()
	return st.commit()


static func _blob_point(t: float, angle: float) -> Vector3:
	# 아래 모서리: 1/4 타원. t=0에서 바닥과 수평으로 이어지고 가장 넓은 곳에서 수직이 되어 돔과 매끈하게 붙는다
	var c := 1.0 - minf(t / WIDEST_T, 1.0)
	var r := BODY_RADIUS * (FOOT_RATIO + (1.0 - FOOT_RATIO) * sqrt(1.0 - c * c))
	if t > WIDEST_T:
		var u := (t - WIDEST_T) / (1.0 - WIDEST_T)
		r = BODY_RADIUS * sqrt(1.0 - u * u)  # 타원 돔: 맨 위가 뾰족하지 않고 둥글다
	return Vector3(cos(angle) * r, t * BODY_HEIGHT, sin(angle) * r)


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/jelly.gdshader")
	_mat.set_shader_parameter("height", BODY_HEIGHT)
	_body = MeshInstance3D.new()
	_body.mesh = build_body_mesh()
	_body.material_override = _mat
	add_child(_body)

	# 점 눈: 앞쪽(-z)에 있다. 몸이 반투명이라 눈 셰이더가 뒷모습에서는 스스로 숨는다
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.045
	eye_mesh.height = 0.09
	var eye_mat := ShaderMaterial.new()
	eye_mat.shader = preload("res://shaders/eye.gdshader")
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.13, 0.55, -0.3)
		_body.add_child(eye)

	# 발밑 빛 웅덩이 + 가운데 작은 그림자
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * SHADOW_SIZE
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = preload("res://shaders/shadow.gdshader")
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.material_override = shadow_mat
	_shadow.position.y = 0.012
	add_child(_shadow)
	_animate()


func _process(delta: float) -> void:
	if running:
		_phase += delta * STEP_RATE
	if delta > 0.0:
		step_wobble((position.x - _prev_x) / delta, delta)
	_prev_x = position.x
	_step_squish(_squish_target(), delta)
	_animate()


## 옆 속도 vx(유닛/초)를 받아 출렁임 스프링을 진행한다. 바닥 가속도의 반대쪽으로 위가 밀린다.
## 큰 delta에서도 터지지 않게 작게 쪼개 적분한다.
func step_wobble(vx: float, delta: float) -> void:
	var accel := (vx - _prev_vx) / delta
	_prev_vx = vx
	var steps := ceili(delta / 0.004)
	var h := delta / steps
	for i in steps:
		_wobble_vel += (-WOBBLE_STIFF * _wobble - WOBBLE_DAMP * _wobble_vel - accel) * h
		_wobble += _wobble_vel * h


## 셰이더에 넘기는 정수리 밀림 거리
func lean() -> float:
	return clampf(_wobble * WOBBLE_GAIN, -WOBBLE_MAX, WOBBLE_MAX)


## 걸음 위상을 직접 정한다 (테스트용).
func set_phase(phase: float) -> void:
	_phase = phase
	_squish = _squish_target()  # 스프링 없이 바로 목표 모양으로
	_squish_vel = 0.0
	_animate()


## 이 레인으로 빠르게 이동한다. 이동 중에 또 호출되면 지금 위치에서 새로 시작한다.
func move_to_lane(lane: int) -> void:
	var x := RunLogic.lane_x(lane)
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position:x", x, MOVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 박자가 정한 눌림 목표: 바닥에 닿을 때 1, 공중에서 0
func _squish_target() -> float:
	var squash := 1.0 - absf(sin(_phase))
	return squash * squash


## 눌림이 목표를 출렁이며 따라가게 한다 (착지 뒤에 몸이 말랑하게 되튐).
func _step_squish(target: float, delta: float) -> void:
	var steps := ceili(delta / 0.008)
	var h := delta / steps
	for i in steps:
		_squish_vel += (JELLY_STIFF * (target - _squish) - JELLY_DAMP * _squish_vel) * h
		_squish += _squish_vel * h


## 박자(위상)에 맞춰 눌림, 흔들림, 그림자 크기를 적용한다. 달리는 동안 몸 바닥은 항상 땅(y=0)에 붙어 있다.
func _animate() -> void:
	var hop := absf(sin(_phase))   # 0 = 가장 눌리는 박자, 1 = 가장 늘어나는 박자 (위로 뜨지는 않음)
	if lift > 0.0:
		hop = 1.0  # 점프 중에는 늘어난 모양
	# 눌리면 옆으로 퍼지고 늘어나면 가늘어진다 (부피 느낌 유지)
	var sy := 1.0 + SQUASH_SCALE * (-0.28 * _squish + 0.08 * hop)
	var sxz := (1.0 + SQUASH_SCALE * (0.22 * _squish - 0.05 * hop)) * (1.0 + 0.35 * crouch)
	# 슬라이드: 낮고 넓게 납작해진다
	_body.scale = Vector3(sxz, sy * lerpf(1.0, PlayerAction.CROUCH_SCALE, crouch), sxz)
	_body.position.y = lift  # 점프만 땅에서 뜬다
	_mat.set_shader_parameter("lean", lean())
	_mat.set_shader_parameter("beat", _phase)
	# 접촉 그림자는 바닥 폭을 따라 퍼졌다 좁아지고, 점프로 뜨면 작아진다
	_shadow.scale = Vector3.ONE * sxz * (1.0 - 0.25 * minf(lift, 1.0))
