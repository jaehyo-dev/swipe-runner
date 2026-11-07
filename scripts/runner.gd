class_name Runner
extends Node3D
## 주인공 민트 젤리. 물방울 몸 + 점 눈 두 개 + 발 두 개 (팔 없음).
## 레인 이동 트윈, 이동 방향으로 기울기, 달리는 통통 눌림과 발 교대 움직임을 맡는다.

const MINT := Color("7FE0C8")
const FOOT_MINT := Color("5CC4AC")  # 발: 몸보다 한 톤 진한 민트
const BODY_RADIUS := 0.42           # 가장 넓은 곳의 반지름 (아래쪽에서 퍼짐)
const BODY_HEIGHT := 1.0            # 아래(0)에서 위 끝까지
const BODY_LIFT := 0.1              # 몸 바닥이 땅에서 뜬 높이 (발이 이만큼 받침)
const FOOT_SIZE := Vector3(0.2, 0.16, 0.26)
const MOVE_TIME := 0.12   # 레인 이동 시간(초)
const LEAN_ANGLE := 0.35  # 이동 방향으로 기울이는 각도(라디안)
const STEP_RATE := 9.0    # 발걸음 속도 (라디안/초)
const SHADOW_SIZE := 1.35

var _body: MeshInstance3D
var _feet: Array[MeshInstance3D] = []
var _shadow: MeshInstance3D
var _phase := 0.0
var _lean := 0.0  # 트윈이 움직이는 현재 기울기
var _move_tween: Tween
var _lean_tween: Tween


## 위가 살짝 뾰족한 물방울 + 아래는 납작하게 퍼진 바닥. 바닥이 y=0이라 눌려도 땅에 붙어 있다.
## 반지름 곡선 r(t)=R·sin(π·t^0.6): t^0.6=0.5(t≈0.31)에서 가장 넓고 위로 갈수록 뾰족해진다.
static func build_body_mesh(rings: int = 24, segments: int = 32) -> ArrayMesh:
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
	return Vector3(cos(angle) * r, t * BODY_HEIGHT, sin(angle) * r)


func _ready() -> void:
	var body_mat := _jelly_material(MINT, 1.0)
	_body = MeshInstance3D.new()
	_body.mesh = build_body_mesh()
	_body.material_override = body_mat
	add_child(_body)

	# 머리 위 작은 물방울 꼭지: 뒷모습에서도 알아보는 포인트
	var nub_mesh := SphereMesh.new()
	nub_mesh.radius = 0.07
	nub_mesh.height = 0.2
	var nub := MeshInstance3D.new()
	nub.mesh = nub_mesh
	nub.material_override = body_mat
	nub.position = Vector3(0.0, BODY_HEIGHT - 0.03, 0.0)
	nub.rotation.z = -0.35
	_body.add_child(nub)

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

	# 발: 몸에 붙은 짧고 통통한 반구형 덩어리, 한 톤 진한 민트
	var foot_mesh := SphereMesh.new()
	foot_mesh.radius = 0.5
	foot_mesh.height = 1.0
	var foot_mat := _jelly_material(FOOT_MINT, 0.0)
	foot_mat.set_shader_parameter("height", 1.0)
	for side in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		foot.mesh = foot_mesh
		foot.scale = FOOT_SIZE
		foot.material_override = foot_mat
		foot.set_meta("side", side)
		add_child(foot)
		_feet.append(foot)

	# 발밑 그림자
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
	_animate()


## 걸음 위상을 직접 정한다 (테스트용).
func set_phase(phase: float) -> void:
	_phase = phase
	_animate()


## 이 레인으로 빠르게 이동한다. 이동 중에 또 호출되면 지금 위치에서 새로 시작한다.
func move_to_lane(lane: int) -> void:
	var x := RunLogic.lane_x(lane)
	var dir := signf(x - position.x)
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position:x", x, MOVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 이동 방향 쪽으로 기울었다가 원래대로 (오른쪽으로 갈 때 z축 회전은 음수)
	if _lean_tween:
		_lean_tween.kill()
	_lean_tween = create_tween()
	_lean_tween.tween_property(self, "_lean", -dir * LEAN_ANGLE, MOVE_TIME * 0.4).set_ease(Tween.EASE_OUT)
	_lean_tween.tween_property(self, "_lean", 0.0, MOVE_TIME * 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 통통 눌림과 발 교대 움직임을 현재 위상에 맞춰 적용한다.
func _animate() -> void:
	var hop := absf(sin(_phase))   # 0 = 바닥에 닿음(가장 납작), 1 = 가장 높음(가장 길쭉)
	var squash := 1.0 - hop
	var sy := 1.0 - 0.26 * squash * squash + 0.08 * hop
	var sxz := 1.0 + 0.2 * squash * squash - 0.05 * hop
	_body.scale = Vector3(sxz, sy, sxz)
	_body.position.y = BODY_LIFT + hop * 0.14
	_body.rotation.z = _lean
	for foot in _feet:
		var side: float = foot.get_meta("side")
		var swing := _phase + (PI if side > 0.0 else 0.0)
		# 앞으로 내딛는 발(cos>0)은 들리고 크게 앞뒤로 움직인다. 몸이 뜨면 발도 따라 올라 몸에서 떨어지지 않는다
		foot.position = Vector3(side * 0.2, FOOT_SIZE.y * 0.5 + maxf(0.0, cos(swing)) * 0.14 + hop * 0.1, 0.04 + sin(swing) * 0.2)
	# 높이 뛸수록 그림자가 작고 옅어진다
	_shadow.scale = Vector3.ONE * (1.0 - 0.18 * hop)
