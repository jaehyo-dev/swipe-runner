extends Node3D
## 게임 화면. 환경(하늘·안개·글로우), 길, 주인공, 장애물, 거리 표시를 만들고 입력을 받는다.
## 계산은 scripts/logic/ 의 클래스가 맡고, 여기서는 그 결과를 화면에 옮기기만 한다.

const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const GLASS_SHADER := preload("res://shaders/glass.gdshader")
const FONT := preload("res://assets/fonts/Poppins-ExtraLight.ttf")
const CUBE_SIZE := 1.1
# 1을 넘는 밝은 청록: 안개 속 먼 거리에서도 보이고 글로우로 살짝 번진다
const EDGE_COLOR := Color(0.5, 1.5, 1.8)

## 0이면 실행할 때마다 무작위. 테스트에서는 0이 아닌 값을 줘서 장애물 레인을 고정한다.
@export var seed_value := 0

var lane := RunLogic.START_LANE
var elapsed := 0.0
var field: ObstacleField
var runner: Runner

var _swipe := SwipeDetector.new()
var _obstacles := {}  # id -> 장애물 노드
var _floor_material: ShaderMaterial
var _glass_material: ShaderMaterial
var _edge_mesh: ArrayMesh
var _edge_material: StandardMaterial3D
var _cube_mesh: BoxMesh
var _camera: Camera3D
var _distance_label: Label
var _scroll := 0.0


func _ready() -> void:
	if seed_value == 0:
		seed_value = randi() | 1
	field = ObstacleField.new(seed_value)
	_build_environment()
	_build_camera()
	_build_floor()
	_build_obstacle_resources()
	runner = Runner.new()
	runner.position = Vector3(RunLogic.lane_x(lane), 0.0, 0.0)
	add_child(runner)
	_build_ui()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()


func _process(delta: float) -> void:
	advance(delta)


## delta초만큼 게임을 진행한다 (테스트에서도 직접 호출).
func advance(delta: float) -> void:
	elapsed += delta
	_scroll += RunLogic.SPEED * delta
	_floor_material.set_shader_parameter("scroll", _scroll)
	var result := field.step(delta)
	for item in result["spawned"]:
		_spawn_node(item)
	for id in result["removed"]:
		_obstacles[id].queue_free()
		_obstacles.erase(id)
	for item in field.items:
		_obstacles[item["id"]].position.z = item["z"]
	_distance_label.text = str(RunLogic.distance(elapsed))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe.press(event.position)
		else:
			_swipe.release()
	elif event is InputEventScreenDrag:
		apply_swipe(_swipe.move(event.position))
	elif event.is_action_pressed("ui_left"):
		apply_swipe(SwipeDetector.Dir.LEFT)
	elif event.is_action_pressed("ui_right"):
		apply_swipe(SwipeDetector.Dir.RIGHT)
	elif event.is_action_pressed("ui_up"):
		apply_swipe(SwipeDetector.Dir.UP)
	elif event.is_action_pressed("ui_down"):
		apply_swipe(SwipeDetector.Dir.DOWN)


## 스와이프(또는 방향키) 방향을 게임 동작으로 옮긴다.
func apply_swipe(dir: SwipeDetector.Dir) -> void:
	match dir:
		SwipeDetector.Dir.LEFT:
			_change_lane(-1)
		SwipeDetector.Dir.RIGHT:
			_change_lane(1)
		SwipeDetector.Dir.UP, SwipeDetector.Dir.DOWN:
			pass  # 점프·슬라이드는 v0.2.0에서 구현 (지금은 입력만 받음)


func _change_lane(direction: int) -> void:
	var next := RunLogic.move_lane(lane, direction)
	if next == lane:
		return
	lane = next
	runner.move_to_lane(lane)


func _spawn_node(item: Dictionary) -> void:
	var cube := MeshInstance3D.new()
	cube.mesh = _cube_mesh
	cube.material_override = _glass_material
	cube.position = Vector3(RunLogic.lane_x(item["lane"]), CUBE_SIZE * 0.5, item["z"])
	var edges := MeshInstance3D.new()
	edges.mesh = _edge_mesh
	edges.material_override = _edge_material
	cube.add_child(edges)
	add_child(cube)
	_obstacles[item["id"]] = cube


# ---------- 장면 만들기 ----------

func _build_environment() -> void:
	# 하늘: 위는 어두운 남색, 지평선은 보라. 안개 색을 지평선과 맞춰 먼 곳이 자연스럽게 흐려진다.
	var horizon := Color("4a2a86")
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("060a24")
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color("2a1659")
	sky_mat.sky_curve = 0.18
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = horizon
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_strength = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.position = Vector3(0.0, 3.3, 5.4)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.7, -8.0))


## 세로 화면은 가로 폭을, 가로 화면(데스크톱 테스트)은 세로 높이를 기준으로 맞춰 길이 항상 보이게 한다.
func _fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y >= size.x else Camera3D.KEEP_HEIGHT


func _build_floor() -> void:
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = FLOOR_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = plane
	floor_node.material_override = _floor_material
	floor_node.position = Vector3(0.0, 0.0, -140.0)
	add_child(floor_node)


func _build_obstacle_resources() -> void:
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE * CUBE_SIZE
	_glass_material = ShaderMaterial.new()
	_glass_material.shader = GLASS_SHADER
	# 얇은 모서리 선: 큐브 12개 모서리를 선 하나의 메시로 (모든 장애물이 공유)
	var h := CUBE_SIZE * 0.5
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(Vector3(h if i & 1 else -h, h if i & 2 else -h, h if i & 4 else -h))
	var indices := PackedInt32Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if not (i & bit):
				indices.append_array([i, i | bit])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	arrays[Mesh.ARRAY_INDEX] = indices
	_edge_mesh = ArrayMesh.new()
	_edge_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_edge_material = StandardMaterial3D.new()
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_material.albedo_color = EDGE_COLOR


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_distance_label = Label.new()
	_distance_label.name = "DistanceLabel"
	_distance_label.text = "0"
	_distance_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_distance_label.offset_top = 90.0
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = 170
	settings.font_color = Color.WHITE
	_distance_label.label_settings = settings
	layer.add_child(_distance_label)

	# 아주 흐린 버전 표시 (project.godot 버전을 읽음)
	var version := Label.new()
	version.name = "VersionLabel"
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	version.offset_top = -48.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := LabelSettings.new()
	vs.font = FONT
	vs.font_size = 22
	vs.font_color = Color(1, 1, 1, 0.4)
	version.label_settings = vs
	layer.add_child(version)
