class_name Runner
extends Node3D
## 주인공: 빛나는 푸딩 슬라임. 물방울 몸 한 덩어리 + 점 눈 두 개 (발·팔 없음).
## 레인 이동 트윈, 박자에 맞춘 눌림(바닥은 땅에 붙인 채), 윗부분이 늦게 따라오는 출렁임,
## 점프·슬라이드 액체 모션(ART_BIBLE.md 7)을 맡는다. 질감은 jelly.gdshader.

const BODY_RADIUS := 0.5            # 가장 넓은 곳의 반지름: 폭 약 1.0 (v0.2.3 찹쌀떡 크기, size_reference.png)
const BODY_HEIGHT := 0.8            # 아래(0)에서 위 끝까지
const WIDEST_T := 0.375             # 가장 넓은 높이 비율: 그 위 돔 높이(0.5)가 반지름과 같아 반구처럼 둥글다
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
const SHADOW_SIZE := 2.26 # 발밑 판 지름: 접촉 그림자 + 몸 둘레 빛 고리. 몸 폭에 비례 (v0.2.2 1.9 × 0.5/0.42, 세기는 shadow.gdshader)
## 점프 모양: 세로 늘어남(1 = 보통) 하나를 스프링으로 움직인다. 옆 폭은 1/√(세로)로 줄어 부피가 유지되는 느낌.
## 순간(뛰기·꼭대기·착지)에는 스프링 속도를 툭 쳐서(킥) 모양이 한 프레임에 튀지 않고 이어진다.
const SHAPE_STIFF := 900.0       # 모양 스프링 세기 (900 ≈ 초당 5번 출렁)
const JUMP_STRETCH_KICK := 16.0  # 뛰는 순간 세로로 늘어나는 세기 (조절: 16 ≈ 1.25배)
const JUMP_APEX_KICK := 2.0      # 꼭대기에서 동그랗게 살짝 출렁이는 세기
const JUMP_FALL_STRETCH := 0.12  # 내려올 때 세로로 늘어나는 정도 (착지 직전 약 1.1배)
const AIR_DAMP := 30.0           # 공중 감쇠: 커서 올라가며 금방 둥글게 돌아옴
const LAND_SQUASH_KICK := 16.0   # 착지 순간 납작해지는 세기 (조절: 16 ≈ 키 0.72배)
const LAND_WOBBLE_DAMP := 18.0   # 착지 출렁임 감쇠 (조절: 작을수록 더 세고 오래 출렁임, 18 ≈ 2~3번 출렁이고 0.4초에 멈춤)
## 슬라이드 모양: 앞으로 미끄러지는 액체
const SLIDE_STRETCH := 1.5       # 앞뒤로 늘어나는 배율 (조절)
const SLIDE_WIDEN := 1.12        # 옆으로 조금만 퍼짐
const SLIDE_SQUASH := 0.42       # 몸 키 배율. 표면 물결까지 더해도 판정 높이(CROUCH_SCALE 0.45배) 아래
const SLIDE_DRAG := 0.12         # 윗부분이 뒤로 끌리는 거리: 앞쪽이 낮고 길게 나간다 (셰이더 drag)
const SPREAD_DAMP := 16.0        # 앞뒤 늘어남 감쇠: 시작할 때 1.5배를 살짝 넘겨 앞으로 쭉 퍼졌다 돌아옴
const SLIDE_END_KICK := 9.0      # 슬라이드가 끝날 때 위로 쭉 올라오는 세기

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
var _stretch := 0.0   # 점프 모양 스프링: 세로 늘어남 - 1 (+ = 길쭉, - = 납작)
var _stretch_vel := 0.0
var _spread := 0.0    # 슬라이드 앞뒤 늘어남 - 1
var _spread_vel := 0.0
var _prev_lift := 0.0
var _prev_lift_vel := 0.0
var _crouch_vis := 0.0  # 화면에 보이는 슬라이드 정도: 점프로 슬라이드가 끊겨도 한 프레임에 튀지 않게 천천히 돌아온다
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
	_mat.set_shader_parameter("radius", BODY_RADIUS)
	_body = MeshInstance3D.new()
	_body.mesh = build_body_mesh()
	_body.material_override = _mat
	add_child(_body)

	# 점 눈: 앞쪽(-z)에 있다. 몸이 반투명이라 눈 셰이더가 뒷모습에서는 스스로 숨는다
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.05
	eye_mesh.height = 0.1
	var eye_mat := ShaderMaterial.new()
	eye_mat.shader = preload("res://shaders/eye.gdshader")
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.155, 0.44, -0.36)  # v0.2.2 위치를 몸 크기 비율로 옮김
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
	_step_squish(0.0 if lift > 0.0 else _squish_target(), delta)  # 공중에서는 달리기 박자 눌림 없음
	step_shape(delta)
	_animate()


## 점프·슬라이드 모양 스프링을 delta초 진행한다. lift·crouch 변화로 뛰기·꼭대기·착지·슬라이드 끝을 알아챈다.
func step_shape(delta: float) -> void:
	if delta <= 0.0:
		return
	var vy := (lift - _prev_lift) / delta
	var air := lift > 0.0
	if air and _prev_lift <= 0.0:
		_stretch_vel += JUMP_STRETCH_KICK
	elif air and _prev_lift_vel > 0.0 and vy <= 0.0:
		_stretch_vel -= JUMP_APEX_KICK
	elif not air and _prev_lift > 0.0:
		_stretch_vel -= LAND_SQUASH_KICK
	if crouch <= 0.0 and _crouch_vis > 0.0 and _crouch_vis <= delta / PlayerAction.SLIDE_FADE:
		_stretch_vel += SLIDE_END_KICK  # 슬라이드에서 돌아오는 마지막 프레임
	_crouch_vis = maxf(crouch, move_toward(_crouch_vis, 0.0, delta / PlayerAction.SLIDE_FADE))
	_prev_lift = lift
	_prev_lift_vel = vy
	var v0 := 4.0 * PlayerAction.JUMP_HEIGHT / PlayerAction.JUMP_TIME  # 뛰는 순간 속도
	var target := JUMP_FALL_STRETCH * maxf(-vy, 0.0) / v0 if air else 0.0
	var damp := AIR_DAMP if air else LAND_WOBBLE_DAMP
	var spread_target := (SLIDE_STRETCH - 1.0) * _crouch_vis
	var steps := ceili(delta / 0.004)
	var h := delta / steps
	for i in steps:
		_stretch_vel += (SHAPE_STIFF * (target - _stretch) - damp * _stretch_vel) * h
		_stretch += _stretch_vel * h
		_spread_vel += (SHAPE_STIFF * (spread_target - _spread) - SPREAD_DAMP * _spread_vel) * h
		_spread += _spread_vel * h


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
	# 점프 모양 늘어남이 곱해진다 (세로로 늘면 옆은 1/√ 만큼 좁아짐)
	var stretch := maxf(1.0 + _stretch, 0.3)
	var sy := (1.0 + SQUASH_SCALE * (-0.28 * _squish + 0.08 * hop)) * stretch
	var sxz := (1.0 + SQUASH_SCALE * (0.22 * _squish - 0.05 * hop)) / sqrt(stretch)
	# 슬라이드: 키는 판정 높이 아래로 고정, 앞뒤로 길게(스프링으로 살짝 넘쳤다 돌아옴), 옆은 조금만
	var c := _crouch_vis
	_body.scale = Vector3(lerpf(sxz, SLIDE_WIDEN, c), lerpf(sy, SLIDE_SQUASH, c), lerpf(sxz, 1.0, c) + _spread)
	_body.position.y = lift  # 점프만 땅에서 뜬다
	_mat.set_shader_parameter("lean", lean())
	_mat.set_shader_parameter("drag", SLIDE_DRAG * c)
	_mat.set_shader_parameter("beat", _phase)
	# 접촉 그림자는 바닥 모양을 따라 퍼졌다 좁아지고, 점프로 뜨면 작아진다
	_shadow.scale = Vector3(_body.scale.x, 1.0, _body.scale.z) * (1.0 - 0.25 * minf(lift, 1.0))
