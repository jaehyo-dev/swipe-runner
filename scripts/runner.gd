class_name Runner
extends Node3D
## 주인공: 빛나는 푸딩 슬라임. 물방울 몸 한 덩어리 + 점 눈 두 개 (발·팔 없음).
## 레인 이동 트윈, 박자에 맞춘 눌림(바닥은 땅에 붙인 채), 윗부분이 늦게 따라오는 출렁임,
## 점프·슬라이드 액체 모션(ART_BIBLE.md 7)을 맡는다. 질감은 jelly.gdshader.

const BODY_RADIUS := 0.5            # 가장 넓은 곳의 반지름: 폭 약 1.0 (v0.2.3 찹쌀떡 크기, size_reference.png)
const BODY_HEIGHT := 0.8            # 아래(0)에서 위 끝까지
const WIDEST_T := 0.375             # 가장 넓은 높이 비율: 그 위 돔 높이(0.5)가 반지름과 같아 반구처럼 둥글다
const FOOT_RATIO := 0.8             # 땅에 닿는 바닥 반지름 / 가장 넓은 반지름 (푸딩처럼 넓고 평평한 바닥)
## 공중 계란형 (ART_BIBLE.md 2-4): 가장 넓은 높이 비율 (조절: 0.45~0.5). 바닥이 y=0에 있어 아래 깊이/위 돔은 이 값으로 정해진다
const AIR_WIDEST_T := 0.49
const AIR_LOWER_DEPTH := AIR_WIDEST_T / (1.0 - AIR_WIDEST_T)  # 아래 둥근 깊이 / 위 돔 높이 = 0.96 (시차가 가장 클 때도 0.9 이상)
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
## 점프·착지 모양: 세로 늘어남(1 = 보통) 하나를 스프링으로 움직인다 (ART_BIBLE.md 2-5).
## 늘어나면 옆 폭은 1/√(세로)로 줄고, 눌리면 옆으로 퍼진다(LAND_SPREAD까지). 순간(뛰기·착지)에는 스프링 속도를 쳐서(킥) 값이 끊기지 않는다.
const SHAPE_STIFF := 900.0       # 공중 모양 스프링 세기
## 공중(원칙 1): 목표 늘어남 = 꼭대기 값 + 위아래 속도에 비례한 값. 화면 키/폭은 뛰는 순간·떨어질 때 약 1.4, 꼭대기 약 1.0 (screen_aspect)
const AIR_ROUND := 0.1           # 꼭대기(위아래 속도 0)의 늘어남: 동그란 물방울, 화면 키/폭 1.0 이상(2-4)
const AIR_SPEED_STRETCH := 0.37  # 가장 빠를 때 더해지는 늘어남 (조절: 최대 늘어남, 0.37 ≈ 게임 화면 키/폭 1.4)
const JUMP_STRETCH_KICK := 14.0  # 뛰는 순간 스프링 속도 킥: 입력한 첫 프레임부터 늘어난다
const AIR_DAMP := 40.0           # 공중 감쇠: 속도를 거의 바로 따라간다 (꼭대기에서 출렁여 납작해지지 않게)
## 공중 아래 스와이프: 떨어지는 속도가 점프 최고 속도보다 빠르므로 늘어남 상한을 더 준다 (보통 점프는 속도가 1배를 넘지 않아 값이 그대로)
const AIR_DROP_SPEED_MAX := 2.0
const DROP_MELT_TIME := 0.05     # 닿은 뒤 슬라이드 모양으로 녹는 시간(초): 한 프레임에 툭 바뀌지 않게
## 착지(원칙 2): 닿는 순간 아래로 킥 → LAND_SQUASH_TIME 동안 팬케이크로 눌림 → 튕김 스프링으로 종 모양 반구 → 1~2번 출렁 → 원래 모양
const LAND_PANCAKE := 0.25       # 팬케이크 키 배율 (조절: 팬케이크 깊이, 작을수록 납작)
const LAND_SQUASH_TIME := 0.12   # 닿고 나서 팬케이크까지 눌리는 시간(초): 무게가 내려앉는 구간
const LAND_SQUASH_STIFF := 2500.0  # 눌리는 스프링 세기 (임계 감쇠라 팬케이크 아래로 넘치지 않음)
const LAND_SQUASH_KICK := 16.0   # 닿는 순간 아래로 치는 세기: 다음 프레임에 바로 동그라미
const LAND_BOUNCE_STIFF := 1000.0  # 튕김 스프링 세기 (조절: 출렁임 빠르기)
const LAND_BOUNCE_DAMP := 30.0   # 튕김 감쇠 (조절: 출렁임 세기·시간, 작을수록 세고 오래)
const LAND_SPREAD := 1.5         # 팬케이크일 때 옆 폭 배율
const LAND_RIM_WAVE := 0.05      # 팬케이크 테두리 물결 세기 (셰이더 rim_wave, 폭의 5%)
## 보이는 몸 폭 상한(m): 옆 레인 허들·막대 안쪽 끝(레인 중심에서 0.85)과 겹쳐 보이지 않게. 반폭 0.775 + 물결 5% ≈ 0.82
const BODY_WIDTH_LIMIT := 1.55
## 착지 물방울(원칙 3): 같은 젤리 재질의 작은 구가 튀었다가 몸으로 떨어지며 작아져 합쳐진다
const DROPLET_COUNT := 3         # 물방울 개수 (조절: 2~4)
const DROPLET_RADIUS := 0.07     # 물방울 반지름(m) (조절)
const DROPLET_TIME := 0.34       # 튀었다 합쳐지기까지 시간(초)
const DROPLET_HEIGHT := 0.45     # 튀어 오르는 높이(m)
const DROPLET_OUT := 0.3         # 바깥으로 나가는 거리(m)
## 위아래 시차(원칙 5): 윗부분이 몸 위아래 가속도에 끌려 늦게 따라오는 스프링(레인 이동 출렁임과 같은 세기·감쇠). 셰이더 sag
const SAG_GAIN := 0.3            # 시차 세기
const SAG_MAX := 0.05            # 정수리가 위아래로 밀리는 최대 거리(몸 좌표, 키 배율이 곱해짐)
## 슬라이드(원칙 4): 녹아서 낮고 넓게 흐른다. 앞(-z)은 바로 나가고 뒤는 스프링으로 늦게 따라온다
const SLIDE_STRETCH := 1.5       # 앞뒤 길이 배율 (앞·뒤가 반씩)
const SLIDE_WIDEN := 1.5         # 옆 폭 배율 (조절: 슬라이드 퍼짐 폭, BODY_WIDTH_LIMIT까지)
const SLIDE_SQUASH := 0.4        # 몸 키 배율 0.32m. 표면 물결까지 더해도 판정 높이(0.45 x 0.8 = 0.36) 아래
const SLIDE_DRAG := 0.12         # 윗부분이 뒤로 끌리는 거리: 앞쪽이 낮고 길게 나간다 (셰이더 drag)
const SLIDE_FRONT_RISE := 0.6    # 끝날 때 뒤가 덜 모인 만큼 윗부분이 앞으로 기울어 앞부터 솟는다
const SPREAD_DAMP := 16.0        # 뒤 따라오기 감쇠: 시작할 때 살짝 넘쳤다 돌아옴
const SLIDE_END_KICK := 9.0      # 슬라이드가 끝날 때 위로 쭉 올라오는 세기
## 충돌 (2-5 원칙 7): 장애물 면에 붙은 납작한 모양과 바닥 웅덩이 모양 (시간표는 CrashMotion)
const CRASH_THIN := 0.3          # 붙었을 때 면과 수직인 두께 배율
const CRASH_WIDE := 1.55         # 붙었을 때 옆 폭 배율 (옆 레인 장애물과 겹치지 않는 상한)
const PUDDLE_DEEP := 1.5         # 웅덩이 앞뒤 길이 배율
const PUDDLE_FLAT := 0.15        # 웅덩이 키 배율
const REFORM_TIME := 0.3         # 다시 시작: 웅덩이가 모여 젤리가 되는 시간(초)
const CRASH_DROP_TIME := 0.4     # 충돌 물방울이 튀었다 사라지는 시간(초)
const CRASH_DROP_HEIGHT := 0.7   # 충돌 물방울이 튀는 높이(m)
## 공중 모양 (ART_BIBLE.md 2-4): 바닥 평평함(1 = 땅의 평평한 바닥, 0 = 둥근 물방울 바닥)을 시간에 걸쳐 바꿔 툭 튀지 않게 한다
const FLAT_CURL_TIME := 0.1      # 뜬 뒤 바닥이 둥글게 말려 올라가는 시간(초) (조절: 작을수록 빨리 둥글어짐)
const FLAT_SPREAD_TIME := 0.05   # 착지 순간 바닥이 다시 평평하게 퍼지는 시간(초)
## 점프 그림자: 최고 높이(JUMP_HEIGHT)에서의 값. 그 사이는 높이에 비례해 줄어든다
const SHADOW_AIR_OPACITY := 0.3  # 최고 높이 진하기 (땅 1)
const SHADOW_AIR_SIZE := 0.6     # 최고 높이 크기 (땅 1)
const MIRROR_ALPHA := 0.25       # 유리 바닥 반사 불투명도 (바닥에 닿은 곳, ART_BIBLE.md 10)

var _body: MeshInstance3D
var _mirror: MeshInstance3D      # 바닥에 비친 몸. 같은 메시 + 같은 셰이더 값이라 모양이 변하는 대로 따라간다
var _mirror_mat: ShaderMaterial
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
var _spread := 0.0    # 슬라이드 뒤쪽 늘어남 (앞쪽은 _crouch_vis로 바로 정해진다)
var _spread_vel := 0.0
var _land_t := -1.0   # 착지 뒤 지난 시간 (음수 = 착지 중 아님)
var _drop_t := -1.0   # 물방울이 튄 뒤 지난 시간 (음수 = 없음)
var _drops: Array[MeshInstance3D] = []
var _sag := 0.0       # 위아래 시차 스프링 (- = 윗부분이 아래로 처짐)
var _sag_vel := 0.0
var _prev_lift := 0.0
var _prev_lift_vel := 0.0
var _crouch_vis := 0.0  # 화면에 보이는 슬라이드 정도: 점프로 슬라이드가 끊겨도 한 프레임에 튀지 않게 천천히 돌아온다
var _flat := 1.0        # 바닥 평평함 (1 = 땅, 0 = 공중의 둥근 바닥)
var _shadow_mat: ShaderMaterial
## 점프로 뜬 높이와 슬라이드로 낮아진 정도(0~1). main이 매 프레임 넣어 준다.
var lift := 0.0
var crouch := 0.0
## false면 달리기 박자가 멈춘다 (게임 오버)
var running := true
## 부딪힌 뒤 지난 시간. main이 매 프레임 넣어 준다 (음수 = 충돌 중 아님)
var crash_t := -1.0
var _crash := {}  # CrashMotion.contact 결과
var _crash_from_scale := Vector3.ONE  # 부딪힌 순간 모양 (점프·슬라이드 중이었어도 거기서 이어진다)
var _crash_from_y := 0.0
var _crash_from_pos := Vector3.ZERO
var _crash_from_flat := 1.0
var _reform_t := -1.0  # 다시 모인 뒤 지난 시간 (음수 = 모이는 중 아님)
var _reform_from_scale := Vector3.ONE
var _reform_from_y := 0.0
var _reform_from_z := 0.0
var _reform_from_wave := 0.0


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
	var r := BODY_RADIUS * _profile(t, 1.0)
	return Vector3(cos(angle) * r, t * BODY_HEIGHT, sin(angle) * r)


## 높이 비율 t의 반지름 / 가장 넓은 반지름. flat = 1이면 땅 위 찹쌀떡, 0이면 공중 계란형. jelly.gdshader profile과 같은 식
static func _profile(t: float, flat: float) -> float:
	var w := lerpf(AIR_WIDEST_T, WIDEST_T, flat)
	if t < w:
		var c := 1.0 - t / w
		var k := FOOT_RATIO * flat
		return k + (1.0 - k) * sqrt(1.0 - c * c)
	var u := (t - w) / (1.0 - w)
	return sqrt(maxf(1.0 - u * u, 0.0))  # 타원 돔: 맨 위가 뾰족하지 않고 둥글다


## 화면에서 보이는 몸의 키/폭: 몸 표면 점(셰이더의 둥근 바닥까지 반영)을 카메라로 투영한 테두리 상자 비율.
## 표면 물결·출렁임 기울기는 작아서 뺀다. 테스트와 화면 확인 기록(review/)에서 쓴다.
func screen_aspect(cam: Camera3D) -> float:
	var flat := smoothstep(0.0, 1.0, _flat)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in 33:
		var t := i / 32.0
		var r := BODY_RADIUS * _profile(t, flat)
		var y := t * BODY_HEIGHT + sag() * t * t  # 셰이더와 같은 위아래 시차
		for j in 32:
			var a := TAU * j / 32
			var q := cam.unproject_position(_body.global_transform * Vector3(cos(a) * r, y, sin(a) * r))
			lo = lo.min(q)
			hi = hi.max(q)
	return (hi.y - lo.y) / (hi.x - lo.x)


## 지금 몸 모양 측정 (시차 포함, 몸 좌표): x = 가장 넓은 높이 / 몸 높이, y = 아래 둥근 깊이 / 위 돔 높이. 테스트와 review/ 기록에서 쓴다.
func body_shape() -> Vector2:
	var w := lerpf(AIR_WIDEST_T, WIDEST_T, smoothstep(0.0, 1.0, _flat))
	var top := BODY_HEIGHT + sag()
	var wide_y := w * BODY_HEIGHT + sag() * w * w
	return Vector2(wide_y / top, wide_y / (top - wide_y))


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/jelly.gdshader")
	_mat.set_shader_parameter("height", BODY_HEIGHT)
	_mat.set_shader_parameter("radius", BODY_RADIUS)
	_mat.set_shader_parameter("foot_ratio", FOOT_RATIO)
	_mat.set_shader_parameter("widest_t", WIDEST_T)
	_mat.set_shader_parameter("air_widest_t", AIR_WIDEST_T)
	_body = MeshInstance3D.new()
	_body.mesh = build_body_mesh()
	_body.material_override = _mat
	add_child(_body)

	_mirror_mat = _mat.duplicate()
	_mirror_mat.set_shader_parameter("mirror_alpha", MIRROR_ALPHA)
	_mirror_mat.render_priority = -1  # 발밑 그림자보다 먼저 그린다
	_mirror = MeshInstance3D.new()
	_mirror.mesh = _body.mesh
	_mirror.material_override = _mirror_mat
	add_child(_mirror)

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
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = preload("res://shaders/shadow.gdshader")
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.material_override = _shadow_mat
	_shadow.position.y = 0.012
	add_child(_shadow)

	# 착지 물방울: 같은 젤리 셰이더. 구 메시라 바닥 둥글기(widest_t 음수로 끔)·심지·기포·바닥 진함은 끈다
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = DROPLET_RADIUS
	drop_mesh.height = DROPLET_RADIUS * 2.0
	drop_mesh.radial_segments = 12
	drop_mesh.rings = 6
	var drop_mat := ShaderMaterial.new()
	drop_mat.shader = _mat.shader
	var drop_params := {"height": DROPLET_RADIUS * 2.0, "radius": DROPLET_RADIUS, "widest_t": -1.0, "core_strength": 0.0,
			"bubble_strength": 0.0, "ground_dark": 0.0, "ripple": 0.0}
	for key in drop_params:
		drop_mat.set_shader_parameter(key, drop_params[key])
	for i in DROPLET_COUNT:
		var d := MeshInstance3D.new()
		d.mesh = drop_mesh
		d.material_override = drop_mat
		d.visible = false
		_drops.append(d)
		add_child(d)
	_animate()


## 셰이더 미리 준비용 물방울 하나 (같은 메시·재질, 보이는 상태)
func make_prewarm_drop() -> MeshInstance3D:
	var drop: MeshInstance3D = _drops[0].duplicate()
	drop.visible = true
	return drop


func _process(delta: float) -> void:
	if crash_t >= 0.0:  # 충돌 모션은 crash_t만으로 정해진다. 스프링은 쉰다
		_animate()
		return
	if _reform_t >= 0.0:
		_reform_t += delta
		if _reform_t >= REFORM_TIME:
			_reform_t = -1.0
			position.z = 0.0
			_stretch_vel += SLIDE_END_KICK  # 다 모이면 한 번 출렁인다
	if running:
		_phase += delta * STEP_RATE
	if delta > 0.0:
		step_wobble((position.x - _prev_x) / delta, delta)
	_prev_x = position.x
	_step_squish(0.0 if lift > 0.0 else _squish_target(), delta)  # 공중에서는 달리기 박자 눌림 없음
	step_shape(delta)
	_animate()


## 점프·착지·슬라이드 모양 스프링을 delta초 진행한다. lift·crouch 변화로 뛰기·착지·슬라이드 끝을 알아챈다.
func step_shape(delta: float) -> void:
	if delta <= 0.0:
		return
	var vy := (lift - _prev_lift) / delta
	var accel_y := (vy - _prev_lift_vel) / delta
	var air := lift > 0.0
	if air and _prev_lift <= 0.0:
		_land_t = -1.0
		# 팬케이크에서 뛰면 아래로 가던 속도를 버리고, 눌려 있던 만큼 세게 솟는다 (예비 동작 느낌). 이미 솟는 중이면 그 속도와 킥 중 큰 쪽
		_stretch_vel = maxf(_stretch_vel, JUMP_STRETCH_KICK * (1.0 - minf(_stretch, 0.0)))
	elif not air and _prev_lift > 0.0:
		_drop_t = 0.0
		if crouch <= 0.0:  # 공중 아래 스와이프로 슬라이드에 바로 이어지면 팬케이크는 건너뛴다
			_land_t = 0.0
			_stretch_vel -= LAND_SQUASH_KICK
	if crouch <= 0.0 and _crouch_vis > 0.0 and _crouch_vis <= delta / PlayerAction.SLIDE_FADE:
		_stretch_vel += SLIDE_END_KICK  # 슬라이드에서 돌아오는 마지막 프레임
	_crouch_vis = maxf(minf(crouch, _crouch_vis + delta / DROP_MELT_TIME), move_toward(_crouch_vis, 0.0, delta / PlayerAction.SLIDE_FADE))
	_flat = move_toward(_flat, 0.0 if air else 1.0, delta / (FLAT_CURL_TIME if air else FLAT_SPREAD_TIME))
	_prev_lift = lift
	_prev_lift_vel = vy
	var target := 0.0
	var stiff := LAND_BOUNCE_STIFF  # 땅에서는 튕김 스프링 (착지 뒤·슬라이드 끝 출렁임)
	var damp := LAND_BOUNCE_DAMP
	if air:
		var v0 := 4.0 * PlayerAction.JUMP_HEIGHT / PlayerAction.JUMP_TIME  # 뛰는 순간(가장 빠른) 속도
		target = AIR_ROUND + AIR_SPEED_STRETCH * minf(absf(vy) / v0, AIR_DROP_SPEED_MAX)
		stiff = SHAPE_STIFF
		damp = AIR_DAMP
	elif _land_t >= 0.0 and _land_t < LAND_SQUASH_TIME:
		target = LAND_PANCAKE - 1.0
		stiff = LAND_SQUASH_STIFF
		damp = 2.0 * sqrt(LAND_SQUASH_STIFF)
	if _land_t >= 0.0:
		_land_t += delta
	if _drop_t >= 0.0:
		_drop_t += delta
		if _drop_t >= DROPLET_TIME:
			_drop_t = -1.0
	var spread_target := (SLIDE_STRETCH - 1.0) * 0.5 * _crouch_vis
	var steps := ceili(delta / 0.004)
	var h := delta / steps
	for i in steps:
		_stretch_vel += (stiff * (target - _stretch) - damp * _stretch_vel) * h
		_stretch += _stretch_vel * h
		_spread_vel += (SHAPE_STIFF * (spread_target - _spread) - SPREAD_DAMP * _spread_vel) * h
		_spread += _spread_vel * h
		_sag_vel += (-WOBBLE_STIFF * _sag - WOBBLE_DAMP * _sag_vel - accel_y) * h  # 레인 출렁임과 같은 스프링
		_sag += _sag_vel * h


## 셰이더에 넘기는 정수리 위아래 밀림 (슬라이드 중에는 판정 높이를 넘지 않게 끈다)
func sag() -> float:
	return clampf(_sag * SAG_GAIN, -SAG_MAX, SAG_MAX) * (1.0 - _crouch_vis)


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


## 부딪혔다. 지금 모양에서 시작해 장애물 면에 붙고 흘러내린다 (이후 main이 crash_t를 넣어 준다).
func crash(contact: Dictionary) -> void:
	if _move_tween:
		_move_tween.kill()
	running = false
	crash_t = 0.0
	_crash = contact
	_crash_from_scale = _body.scale
	_crash_from_y = _body.position.y
	_crash_from_pos = position
	_crash_from_flat = _flat
	_drop_t = -1.0
	_reform_t = -1.0


## 다시 시작: 지금 모양(웅덩이 또는 흘러내리는 중)에서 REFORM_TIME 동안 달리는 모양으로 모인다.
func reform(lane: int) -> void:
	_reform_from_scale = _body.scale
	_reform_from_y = _body.position.y
	_reform_from_z = position.z
	_reform_from_wave = _mat.get_shader_parameter("rim_wave")  # 모양과 함께 지금 값에서 이어 간다 (바닥 평평함 _flat도 그대로 두면 step_shape가 이어 줌)
	_reform_t = 0.0
	crash_t = -1.0
	running = true
	lift = 0.0
	crouch = 0.0
	# 스프링을 쉬게 둬서 앞 판의 움직임이 이어지지 않게 한다
	_squish = 0.0
	_squish_vel = 0.0
	_wobble = 0.0
	_wobble_vel = 0.0
	_stretch = 0.0
	_stretch_vel = 0.0
	_spread = 0.0
	_spread_vel = 0.0
	_sag = 0.0
	_sag_vel = 0.0
	_land_t = -1.0
	_drop_t = -1.0
	_crouch_vis = 0.0
	_prev_lift = 0.0
	_prev_lift_vel = 0.0
	_prev_vx = 0.0
	_prev_x = position.x
	move_to_lane(lane)


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
	# 점프 모양 늘어남이 곱해진다: 세로로 늘면 옆은 1/√ 만큼 좁아지고, 팬케이크로 눌리면 LAND_SPREAD까지만 퍼진다
	var stretch := maxf(1.0 + _stretch, 0.15)
	var widen := 1.0 / sqrt(stretch) if stretch >= 1.0 \
		else minf(1.0 + (LAND_SPREAD - 1.0) * (1.0 - stretch) / (1.0 - LAND_PANCAKE), LAND_SPREAD)
	var sy := (1.0 + SQUASH_SCALE * (-0.28 * _squish + 0.08 * hop)) * stretch
	var sxz := (1.0 + SQUASH_SCALE * (0.22 * _squish - 0.05 * hop)) * widen
	# 슬라이드: 키는 판정 높이 아래로 고정, 옆으로 넓게 녹아 퍼짐, 앞은 바로 나가고 뒤(_spread)가 따라옴
	var c := _crouch_vis
	var front := (SLIDE_STRETCH - 1.0) * 0.5 * c
	_body.scale = Vector3(minf(lerpf(sxz, SLIDE_WIDEN, c), BODY_WIDTH_LIMIT), lerpf(sy, SLIDE_SQUASH, c), lerpf(sxz, 1.0, c) + front + _spread)
	_body.position = Vector3(0.0, lift, (_spread - front) * BODY_RADIUS)  # 점프만 땅에서 뜬다. 슬라이드 앞(-z) 끝은 바로 나감
	_set_shape("lean", lean())
	_set_shape("sag", sag())
	# 끝날 때 앞이 먼저 모이고 뒤가 덜 모인 만큼 윗부분이 앞으로 기울어 앞부터 솟는다
	_set_shape("drag", SLIDE_DRAG * c - SLIDE_FRONT_RISE * maxf(_spread - front, 0.0))
	_set_shape("rim_wave", LAND_RIM_WAVE * clampf(-_stretch / (1.0 - LAND_PANCAKE), 0.0, 1.0))
	if crash_t >= 0.0:
		_apply_crash()
	elif _reform_t >= 0.0:
		var u := smoothstep(0.0, 1.0, _reform_t / REFORM_TIME)
		_body.scale = _reform_from_scale.lerp(_body.scale, u)
		_body.position.y = lerpf(_reform_from_y, _body.position.y, u)
		position.z = lerpf(_reform_from_z, 0.0, u)
		_set_shape("rim_wave", _reform_from_wave * (1.0 - u))
	_animate_drops()
	_mirror.scale = _body.scale * Vector3(1.0, -1.0, 1.0)
	_mirror.position = _body.position * Vector3(1.0, -1.0, 1.0)
	_mat.set_shader_parameter("beat", _phase)
	_set_shape("flat_bottom", smoothstep(0.0, 1.0, _flat))  # 처음과 끝이 부드럽게
	# 접촉 그림자는 바닥 모양을 따라 퍼졌다 좁아지고, 점프로 뜨면 작고 옅고 부드러워진다.
	# 높이의 제곱근을 써서 조금만 떠도 빨리 옅어진다 (낮게 뜬 몸 아래 진한 원이 까만 구멍처럼 남지 않게)
	var h := sqrt(clampf(_body.position.y / PlayerAction.JUMP_HEIGHT, 0.0, 1.0))
	_shadow.scale = Vector3(_body.scale.x, 1.0, _body.scale.z) * lerpf(1.0, SHADOW_AIR_SIZE, h)
	_shadow_mat.set_shader_parameter("opacity", lerpf(1.0, SHADOW_AIR_OPACITY, h))
	_shadow_mat.set_shader_parameter("soft", h)


## 몸 모양을 바꾸는 셰이더 값은 반사에도 똑같이 넣는다.
func _set_shape(param: StringName, value: float) -> void:
	_mat.set_shader_parameter(param, value)
	_mirror_mat.set_shader_parameter(param, value)


## 충돌 모양을 몸과 주인공 위치에 적용한다.
## 몸의 면 쪽 끝이 늘 장애물 면에 닿도록 주인공 위치를 두께에 맞춰 옮긴다.
func _apply_crash() -> void:
	var stick := CrashMotion.stick(crash_t)
	var reach := minf(stick, 1.0)  # 튕겨 넘치는 값은 모양에만 쓰고 위치는 넘치지 않게 한다
	var flow := CrashMotion.flow(crash_t)
	var n: Vector3 = _crash["normal"]
	var on_x := absf(n.x) > 0.5  # 옆면에 붙었으면 두께가 x, 폭이 z
	var from_thin := _crash_from_scale.x if on_x else _crash_from_scale.z
	var from_wide := _crash_from_scale.z if on_x else _crash_from_scale.x
	var thin := lerpf(lerpf(from_thin, CRASH_THIN, stick), PUDDLE_DEEP, flow)
	var wide := lerpf(lerpf(from_wide, CRASH_WIDE, stick), BODY_WIDTH_LIMIT, flow)
	var tall := lerpf(lerpf(_crash_from_scale.y, _crash["tall"], stick), PUDDLE_FLAT, flow)
	var bottom := maxf(float(_crash["y"]) - float(_crash["tall"]) * BODY_HEIGHT * 0.5, 0.0)
	_body.scale = Vector3(thin, tall, wide) if on_x else Vector3(wide, tall, thin)
	_body.position = Vector3(0.0, lerpf(lerpf(_crash_from_y, bottom, reach), 0.0, flow), 0.0)
	var edge: float = float(_crash["face"]) + (n.x + n.z) * BODY_RADIUS * thin
	var along: float = _crash["along"]
	position.x = lerpf(_crash_from_pos.x, edge if on_x else along, reach)
	position.z = lerpf(_crash_from_pos.z, along if on_x else edge, reach)
	_set_shape("lean", 0.0)
	_set_shape("sag", 0.0)
	_set_shape("drag", 0.0)
	_set_shape("rim_wave", LAND_RIM_WAVE * 0.4 * flow)  # 웅덩이는 넓어서 작게 줘야 테두리가 각지지 않는다
	# 붙은 동안엔 뒤 카메라에 면에 눌린 둥근 원판으로 보이게 바닥을 둥글게, 웅덩이가 되며 다시 평평하게
	_flat = lerpf(lerpf(_crash_from_flat, 0.0, reach), 1.0, flow)


## 충돌 물방울: 붙는 순간 면에서 바깥(면의 수직 방향)·양옆으로 튀어 떨어지며 작아진다. 몸과 합쳐지지 않고 사라진다.
func _animate_crash_drops() -> void:
	var u := (crash_t - CrashMotion.SLOW_TIME) / CRASH_DROP_TIME
	var n: Vector3 = _crash["normal"]
	var side := n.cross(Vector3.UP)
	for i in _drops.size():
		var d := _drops[i]
		d.visible = u >= 0.0 and u < 1.0
		if not d.visible:
			continue
		var fan := i - (_drops.size() - 1) * 0.5  # 왼쪽·가운데·오른쪽
		var up := CRASH_DROP_HEIGHT * (1.0 - 0.3 * (i % 2)) * sin(PI * minf(u * 1.3, 1.0))
		d.position = (n * 0.4 + side * fan * 1.2) * u + Vector3.UP * (_body.position.y + 0.3 * (1.0 - u) + up)
		d.scale = Vector3.ONE * (1.0 - smoothstep(0.6, 1.0, u)) * 1.6


## 착지 물방울: 팬케이크 테두리에서 나와 바깥·위로 튀었다가 몸 가운데 위로 떨어지며 작아져 합쳐진다.
## 무작위 없이 개수로 방향을 나눠(옆·앞으로 퍼지게) 항상 같은 모양이다.
func _animate_drops() -> void:
	if crash_t >= 0.0:
		_animate_crash_drops()
		return
	for i in _drops.size():
		var d := _drops[i]
		d.visible = _drop_t >= 0.0
		if not d.visible:
			continue
		var u := _drop_t / DROPLET_TIME
		var a := PI + PI * i / maxf(_drops.size() - 1, 1.0)  # 왼쪽부터 앞(-z)을 지나 오른쪽까지: 뒤 카메라에서 몸에 가리지 않게
		var r := lerpf(0.6, 0.15, u) + DROPLET_OUT * sin(PI * u)
		var up := DROPLET_HEIGHT * (1.0 - 0.2 * (i % 2)) * sin(PI * u)  # 높이를 조금씩 달리해 비대칭
		d.position = Vector3(cos(a) * r, lerpf(0.06, 0.25, u) + up, sin(a) * r)
		d.scale = Vector3.ONE * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.65, 1.0, u))
