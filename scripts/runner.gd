class_name Runner
extends Node3D
## 주인공 민트 젤리. 물방울 몸 한 덩어리 + 점 눈 두 개 (발·팔 없음).
## 레인 이동 트윈, 박자에 맞춘 튀기·착지 눌림, 이동 반대쪽으로 늦게 따라오는 말랑한 흔들림을 맡는다.

const MINT := Color("7FE0C8")
const BODY_RADIUS := 0.42           # 가장 넓은 곳의 반지름 (아래쪽에서 퍼짐)
const BODY_HEIGHT := 1.0            # 아래(0)에서 위 끝까지
const WIDEST_T := 0.3086            # 가장 넓은 높이 비율 (0.5^(1/0.6) 근처)
const HOP_HEIGHT := 0.2   # 튀어 오르는 높이
const MOVE_TIME := 0.12   # 레인 이동 시간(초)
const STEP_RATE := 9.0    # 튀는 박자 속도 (라디안/초)
const SWAY_GAIN := 0.03   # 옆 속도(유닛/초) 1당 흔들림 목표 각도(라디안)
const SWAY_MAX := 0.5     # 흔들림 최대 각도
const SWAY_STIFF := 150.0 # 스프링 세기 (클수록 빨리 따라옴)
const SWAY_DAMP := 14.0   # 감쇠: 거의 임계 감쇠라 덜컹거리지 않고 한 번 부드럽게 되돌아옴
const SWAY_SMOOTH := 14.0 # 옆 속도를 거르는 속도 (클수록 즉각 반응, 작을수록 완만)
const JELLY_STIFF := 170.0 # 눌림 스프링 세기
const JELLY_DAMP := 7.0    # 눌림 감쇠: 작게 둬서 착지 뒤 길쭉↔납작이 두어 번 출렁임
const SHADOW_SIZE := 1.35

var _body: MeshInstance3D
var _shadow: MeshInstance3D
var _phase := 0.0
var _sway := 0.0      # 몸의 현재 흔들림 각도 (z축 회전)
var _sway_vel := 0.0
var _vx_smooth := 0.0 # 거른 옆 속도: 이동 시작의 급격한 속도 점프가 몸을 덜컹이게 하지 않게 함
var _prev_x := 0.0
var _squish := 0.0    # 스프링으로 따라가는 눌림 정도 (0 = 보통, 1 = 가장 납작, 음수 = 길쭉하게 튕김)
var _squish_vel := 0.0
var _move_tween: Tween


## 아래는 납작하게 퍼지고 위는 둥근 돔인 물방울. 바닥이 y=0이라 눌려도 땅에 붙어 있다.
## 반지름: t<TOP_START는 sin(π·t^0.6)로 가장 넓은 곳(t≈0.31)까지 퍼지고, 그 위는 타원 돔으로 둥글게 닫는다.
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
	st.generate_normals()
	return st.commit()


static func _blob_point(t: float, angle: float) -> Vector3:
	var r := BODY_RADIUS * sin(PI * pow(t, 0.6))
	if t > WIDEST_T:
		var u := (t - WIDEST_T) / (1.0 - WIDEST_T)
		r = BODY_RADIUS * sqrt(1.0 - u * u)  # 타원 돔: 맨 위가 뾰족하지 않고 둥글다
	return Vector3(cos(angle) * r, t * BODY_HEIGHT, sin(angle) * r)


func _ready() -> void:
	var body_mat := _jelly_material(MINT, 1.0)
	_body = MeshInstance3D.new()
	_body.mesh = build_body_mesh()
	_body.material_override = body_mat
	add_child(_body)

	# 점 눈: 앞쪽(-z)에 있어서 뒤에서 보면 거의 안 보인다
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.045
	eye_mesh.height = 0.09
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color("12332e")
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.13, 0.55, -0.3)
		_body.add_child(eye)

	# 바닥 그림자
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


func _jelly_material(color: Color, highlight: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/jelly.gdshader")
	mat.set_shader_parameter("mint", color)
	mat.set_shader_parameter("highlight", highlight)
	mat.set_shader_parameter("height", BODY_HEIGHT)
	return mat


func _process(delta: float) -> void:
	_phase += delta * STEP_RATE
	if delta > 0.0:
		step_sway((position.x - _prev_x) / delta, delta)
	_prev_x = position.x
	_step_squish(_squish_target(), delta)
	_animate()


## 옆 속도 vx에 반대쪽으로 몸 윗부분이 늦게 따라오는 스프링 (오른쪽으로 가면 위가 왼쪽에 처짐).
## 큰 delta에서도 터지지 않게 작게 쪼개 적분한다.
func step_sway(vx: float, delta: float) -> void:
	var steps := ceili(delta / 0.008)
	var h := delta / steps
	for i in steps:
		_vx_smooth += (vx - _vx_smooth) * minf(1.0, SWAY_SMOOTH * h)
		var target := clampf(_vx_smooth * SWAY_GAIN, -SWAY_MAX, SWAY_MAX)
		_sway_vel += (SWAY_STIFF * (target - _sway) - SWAY_DAMP * _sway_vel) * h
		_sway += _sway_vel * h


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
	_move_tween.tween_property(self, "position:x", x, MOVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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


## 박자(위상)에 맞춰 튀기, 눌림, 흔들림, 그림자 크기를 적용한다.
func _animate() -> void:
	var hop := absf(sin(_phase))   # 0 = 바닥에 닿음, 1 = 가장 높음
	# 눌리면 옆으로 퍼지고 늘어나면 가늘어진다 (부피 느낌 유지)
	var sy := 1.0 - 0.28 * _squish + 0.08 * hop
	var sxz := 1.0 + 0.22 * _squish - 0.05 * hop
	_body.scale = Vector3(sxz, sy, sxz)
	_body.position.y = hop * HOP_HEIGHT
	_body.rotation.z = _sway
	# 높이 뛸수록 작아지고, 착지 순간(눌림↑)에 살짝 커졌다 줄어든다
	_shadow.scale = Vector3.ONE * (1.0 - 0.18 * hop + 0.14 * clampf(_squish, 0.0, 1.0))
