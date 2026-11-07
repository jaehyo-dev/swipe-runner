class_name Runner
extends Node3D
## 주인공 민트 젤리. 물방울 몸 + 점 눈 두 개 + 발 두 개 (팔 없음).
## 레인 이동 트윈, 이동 방향으로 기울기, 달리는 통통 눌림과 발 교대 움직임을 맡는다.

const MINT := Color("7FE0C8")
const BODY_RADIUS := 0.36
const BODY_HEIGHT := 1.0  # 구를 위로 늘인 높이 (지름보다 큼)
const FOOT_RADIUS := 0.11
const MOVE_TIME := 0.12   # 레인 이동 시간(초)
const LEAN_ANGLE := 0.35  # 이동 방향으로 기울이는 각도(라디안)
const STEP_RATE := 9.0    # 발걸음 속도 (라디안/초)

var _body: MeshInstance3D
var _feet: Array[MeshInstance3D] = []
var _phase := 0.0
var _lean := 0.0  # 트윈이 움직이는 현재 기울기
var _move_tween: Tween
var _lean_tween: Tween


func _ready() -> void:
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://shaders/jelly.gdshader")
	glow.set_shader_parameter("mint", MINT)

	var body_mesh := SphereMesh.new()
	body_mesh.radius = BODY_RADIUS
	body_mesh.height = BODY_HEIGHT
	body_mesh.radial_segments = 32
	body_mesh.rings = 16
	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	_body.material_override = glow
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
		eye.position = Vector3(side * 0.13, 0.18, -BODY_RADIUS * 0.9)
		_body.add_child(eye)

	var foot_mesh := SphereMesh.new()
	foot_mesh.radius = FOOT_RADIUS
	foot_mesh.height = FOOT_RADIUS * 1.4
	for side in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		foot.mesh = foot_mesh
		foot.material_override = glow
		foot.set_meta("side", side)
		add_child(foot)
		_feet.append(foot)
	_animate()


func _process(delta: float) -> void:
	_phase += delta * STEP_RATE
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
	var hop := absf(sin(_phase))   # 0 = 바닥에 닿음, 1 = 가장 높음
	var squash := 1.0 - hop
	var sy := 1.0 - 0.16 * squash * squash + 0.05 * hop
	var sxz := 1.0 + 0.1 * squash * squash - 0.02 * hop
	_body.scale = Vector3(sxz, sy, sxz)
	_body.position.y = FOOT_RADIUS * 0.9 + BODY_HEIGHT * 0.5 * sy * 0.92 + hop * 0.16
	_body.rotation.z = _lean
	for foot in _feet:
		var side: float = foot.get_meta("side")
		var swing := _phase + (PI if side > 0.0 else 0.0)
		foot.position = Vector3(side * 0.15, FOOT_RADIUS * 0.7 + maxf(0.0, cos(swing)) * 0.09, sin(swing) * 0.16)
