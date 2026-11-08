extends Node3D
## 게임 화면. 환경(하늘·안개·글로우), 길, 주인공, 장애물, 거리 표시를 만들고 입력을 받는다.
## 계산은 scripts/logic/ 의 클래스가 맡고, 여기서는 그 결과를 화면에 옮기기만 한다.

const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const GLASS_SHADER := preload("res://shaders/glass.gdshader")
const FONT := preload("res://assets/fonts/Poppins-ExtraLight.ttf")
## 장애물 종류별 색조 (ART_BIBLE.md 4번 표). 파랑 = 옆으로, 앰버 = 위로, 핑크 = 아래로.
## glass: 유리 면 색(연하게 보임), edge: 모서리 선 HDR 색(1을 넘어 안개 속에서도 보이고 글로우로 살짝 번짐)
## 화면은 1을 넘는 채널을 1로 자르므로, 앰버·핑크는 빨강만 1을 넘겨야 노랑·자홍으로 바뀌지 않는다.
const KIND_COLORS := {
	ObstacleField.Kind.BLOCK: {"glass": Color("9edbff"), "edge": Color(0.5, 1.5, 1.8)},
	ObstacleField.Kind.LOW: {"glass": Color("ffc38a"), "edge": Color(1.6, 0.7, 0.35)},
	ObstacleField.Kind.HIGH: {"glass": Color("ff8fc8"), "edge": Color(1.6, 0.45, 0.73)},
}

const RESTART_DELAY := 0.5
const OBSTACLE_FADE := 0.15  # 다시 시작할 때 앞 판 장애물이 작아져 사라지는 시간(초): 한 프레임에 툭 없어지지 않게
const POP_TIME := 0.25       # 다시 시작할 때 새 장애물이 바닥에서 솟아오르는 시간(초)
const PREWARM_FRAMES := 3    # 가림막 뒤에서 이만큼 연달아 빠른 프레임이 나오면 준비 끝 (셰이더는 그래픽 쪽에서 늦게 끝날 수 있다)
const PREWARM_FAST_MS := 50
const PREWARM_MAX_FRAMES := 120  # 아주 느린 기기도 언젠가는 화면을 연다
const FLASH_TIME := 0.3      # 음악 단계가 오를 때 길 선이 빛나는 시간(초)
const POP_SCALE := 1.22      # 새 기록 순간 거리 숫자가 커지는 배율 (말랑)
const POP_UP := 0.08
const POP_DOWN := 0.32
const BOOT_COLOR := Color(0.027, 0.04, 0.14)  # project.godot boot_splash/bg_color와 같은 색: 로딩에서 가림막으로 이어져 보이게

## 0이면 실행할 때마다 무작위. 테스트에서는 0이 아닌 값을 줘서 장애물 레인을 고정한다.
@export var seed_value := 0
## 최고 기록 파일. 테스트는 임시 파일을 준다.
@export var best_path := BestRecord.PATH

var lane := RunLogic.START_LANE
## 이번 판에 이동한 거리. 화면 숫자는 이 값의 정수 부분.
var travel := 0.0
## 지금 세상이 다가오는 속도
var speed := RunLogic.SPEED
var record: BestRecord
var field: ObstacleField
var runner: Runner
var player := PlayerAction.new()
var dead := false
## 첫 입력을 받았는가. 그 전에는 세상이 멈춰 있고 장애물만 미리 놓여 있다 (브라우저가 첫 입력 전엔 소리를 막으므로).
var started := false
## 셰이더 미리 준비가 끝났는가. 첫 화면은 이때 드러난다.
var prewarmed := false

var _swipe := SwipeDetector.new()
var _obstacles := {}  # id -> 장애물 노드
var _floor_material: ShaderMaterial
var _kind_meshes := {}  # Kind -> {y:float, mesh:BoxMesh, edges:ArrayMesh, glass:ShaderMaterial, edge:StandardMaterial3D}
var _dead_time := 0.0
var _restart_label: Label
var _camera: Camera3D
var _distance_label: Label
var _best_label: Label
var _pop: Tween
var _scroll := 0.0
var _music_t := 0.0  # 박자 기준 시간


## 시드를 고정했으면(주소의 ?seed, 테스트) 판마다 같은 배치, 아니면 판마다 새 배치
func _new_field() -> void:
	field = ObstacleField.new(seed_value if seed_value != 0 else randi() | 1)


func _ready() -> void:
	if seed_value == 0 and OS.has_feature("web"):
		# 화면 확인 기록(review/)을 같은 배치로 다시 찍을 수 있게 주소의 ?seed=숫자를 읽는다
		seed_value = int(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') || 0")))
	record = BestRecord.new(best_path)
	_new_field()
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
	_place_ahead(false)
	_prewarm()


func _process(delta: float) -> void:
	advance(delta, AudioManager.music_time)


## 첫 입력: 음악 0초와 함께 세상이 출발한다. 미리 놓인 장애물을 음악 시간에 맞춘다 (출력 지연만큼의 차이).
func begin() -> void:
	started = true
	AudioManager.start_music()
	_music_t = AudioManager.music_time
	_move_world()


## delta초만큼 게임을 진행한다 (테스트에서도 직접 호출). music_t: 음악 시간. 안 주면(테스트) delta만큼 흐른 것으로 친다.
## 세상은 음악 시간에서 계산한 이동 거리만큼 움직이고, 주인공 동작은 프레임 시간으로 움직인다.
func advance(delta: float, music_t := NAN) -> void:
	_music_t = _music_t + delta if is_nan(music_t) else music_t
	if dead:
		_advance_dead(delta)
		return
	player.step(delta)
	_play_action_sounds()
	runner.lift = player.height()
	runner.crouch = player.crouch()
	if not started:
		return
	_move_world()
	_distance_label.text = str(int(travel))
	if record.update(int(travel)):
		_on_new_record()
	for item in field.items:
		var dx := runner.position.x - RunLogic.lane_x(item["lane"])
		if not item.has("cleared") and PlayerAction.hits(item["kind"], dx, item["z"], player.height(), player.is_ducking()):
			_game_over(item)
			return


## 음악 시간에서 이동 거리·속도·길 선 빛남을 구해 세상에 옮긴다.
func _move_world() -> void:
	var ladder := AudioManager.ladder
	var now := ladder.distance_at(_music_t)
	_scroll += now - travel
	travel = now
	speed = ladder.speed_at(_music_t)
	_floor_material.set_shader_parameter("scroll", _scroll)
	var age := ladder.stage_up_age(_music_t)
	_floor_material.set_shader_parameter("flash", 1.0 - age / FLASH_TIME if age >= 0.0 and age < FLASH_TIME else 0.0)
	_apply_step(field.step(travel))


## field.step() 결과를 장애물 노드에 옮긴다.
func _apply_step(result: Dictionary) -> void:
	for item in result["spawned"]:
		_spawn_node(item)
	for id in result["removed"]:
		_obstacles[id].queue_free()
		_obstacles.erase(id)
	for item in field.items:
		_obstacles[item["id"]].position.z = item["z"]


## 앞으로 도착할 장애물을 이미 길 위에 놓는다. pop: 다시 시작할 때처럼 바닥에서 솟아오르게 한다.
func _place_ahead(pop: bool) -> void:
	for item in field.step(travel)["spawned"]:
		_spawn_node(item)
		if pop:
			_pop_in(_obstacles[item["id"]], _kind_meshes[item["kind"]]["y"])


## 높이 0에서 젤리처럼 '퐁': 바닥을 기준으로 늘어나 살짝 넘쳤다가 돌아온다. 판정은 field가 하므로 모양만 바뀐다.
func _pop_in(node: Node3D, y: float) -> void:
	var rise := func(s: float) -> void:
		node.scale.y = s
		node.position.y = y * s
	rise.call(0.001)
	node.create_tween().tween_method(rise, 0.001, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 부딪힌 뒤: 세상이 아주 잠깐 느려졌다 멈추고, 주인공은 충돌 모션을 이어 간다.
func _advance_dead(delta: float) -> void:
	var slow := CrashMotion.slow_delta(_dead_time, delta)
	_dead_time += delta
	_scroll += speed * slow
	_floor_material.set_shader_parameter("scroll", _scroll)
	for item in field.items:
		item["z"] += speed * slow
		_obstacles[item["id"]].position.z = item["z"]
	runner.crash_t = _dead_time
	var shake := CrashMotion.shake(_dead_time)
	_camera.h_offset = shake.x
	_camera.v_offset = shake.y
	_restart_label.visible = _dead_time >= RESTART_DELAY


## 부딪혔다: 실수로 바로 넘기지 않게 잠깐 뒤부터 다시 시작할 수 있다.
func _game_over(item: Dictionary) -> void:
	dead = true
	_dead_time = 0.0
	AudioManager.play_crash()
	_floor_material.set_shader_parameter("flash", 0.0)
	record.save()
	_best_label.visible = true
	_best_label.text = ("NEW BEST %d" if record.broken else "BEST %d") % record.best
	# 느려지는 동안 장애물이 조금 더 다가오므로 그만큼 앞으로 간 면에 붙는다
	var z: float = item["z"] + speed * CrashMotion.SLOW_SCALE * CrashMotion.SLOW_TIME
	runner.crash(CrashMotion.contact(item["kind"], RunLogic.lane_x(item["lane"]), runner.position.x, z, player.height()))


## 장면을 다시 불러오지 않고 그 자리에서 상태만 초기화한다. 레인은 그대로, 세상은 바로 움직이고 입력도 바로 받는다.
func restart() -> void:
	dead = false
	_dead_time = 0.0
	AudioManager.restart_music()
	_music_t = AudioManager.music_time
	travel = AudioManager.ladder.distance_at(_music_t)  # 출력 지연만큼 음수에서 출발: 다음 프레임에 길이 뒤로 튀지 않게
	player = PlayerAction.new()
	_swipe = SwipeDetector.new()
	var old_nodes := _obstacles.values()
	_obstacles.clear()
	_new_field()
	AudioManager.unblock()
	for node: Node3D in old_nodes:
		var fade := node.create_tween().set_parallel()
		fade.tween_property(node, "scale", Vector3.ONE * 0.01, OBSTACLE_FADE)
		fade.tween_property(node, "position:z", node.position.z + speed * OBSTACLE_FADE, OBSTACLE_FADE)
		fade.chain().tween_callback(node.queue_free)
	_place_ahead(true)
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_restart_label.visible = false
	_distance_label.text = "0"
	record.begin_run()
	_show_best()
	runner.reform(lane)


## 기록이 있으면 숫자 아래에 작게. 첫 판에는 숨긴다.
func _show_best() -> void:
	_best_label.visible = record.previous > 0
	_best_label.text = "BEST %d" % record.previous


## 예전 기록을 넘은 순간: 숫자가 한 번 말랑하게 커졌다 돌아온다. 소리는 내지 않는다.
func _on_new_record() -> void:
	_best_label.text = "NEW BEST"
	_distance_label.pivot_offset = _distance_label.size * 0.5
	_pop = create_tween()
	_pop.tween_property(_distance_label, "scale", Vector2.ONE * POP_SCALE, POP_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_distance_label, "scale", Vector2.ONE, POP_DOWN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if not started and not prewarmed:  # 가림막 뒤에서 게임이 시작되면 보이지 않는 장애물에 부딪힐 수 있다
		return
	if not started and (event is InputEventScreenTouch or event is InputEventKey) and event.pressed:
		begin()  # 이 입력도 아래에서 게임 동작으로 그대로 처리한다
	if dead:
		var pressed: bool = (event is InputEventScreenTouch or event is InputEventKey) and event.pressed
		if pressed and _dead_time >= RESTART_DELAY:
			restart()
			if event is InputEventScreenTouch:  # 다시 시작한 손가락 그대로 밀어도 스와이프가 된다
				_swipe.press(event.position, event.index)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe.press(event.position, event.index)
		else:
			_swipe.release(event.index)
	elif event is InputEventScreenDrag:
		apply_swipe(_swipe.move(event.position, event.index))
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
		SwipeDetector.Dir.UP:
			player.jump()
			_play_action_sounds()
		SwipeDetector.Dir.DOWN:
			_drop_clear_hurdles()
			player.slide()
			_play_action_sounds()


## 동작이 일어난 그 프레임에 바로 재생한다
func _play_action_sounds() -> void:
	for sound in player.take_sounds():
		AudioManager.play_action(sound)


## 공중 아래 스와이프 순간 이미 넘고 있던 허들은 내려오다 닿아도 봐준다 (넘고 있었는데 죽으면 억울하다)
func _drop_clear_hurdles() -> void:
	if not player.is_jumping() or player.is_dropping():
		return
	for item in field.items:
		var dx := runner.position.x - RunLogic.lane_x(item["lane"])
		if PlayerAction.clears_on_drop(item["kind"], dx, item["z"], player.height()):
			item["cleared"] = true


func _change_lane(direction: int) -> void:
	var next := RunLogic.move_lane(lane, direction)
	if next == lane:
		return
	lane = next
	runner.move_to_lane(lane)
	AudioManager.play_lane(direction)


func _spawn_node(item: Dictionary) -> void:
	var cube := _make_obstacle(item["kind"], item["lane"], item["z"])
	add_child(cube)
	_obstacles[item["id"]] = cube


func _make_obstacle(kind: ObstacleField.Kind, at_lane: int, z: float) -> MeshInstance3D:
	var shape: Dictionary = _kind_meshes[kind]
	var cube := MeshInstance3D.new()
	cube.mesh = shape["mesh"]
	cube.material_override = shape["glass"]
	cube.position = Vector3(RunLogic.lane_x(at_lane), shape["y"], z)
	var edges := MeshInstance3D.new()
	edges.mesh = shape["edges"]
	edges.material_override = shape["edge"]
	cube.add_child(edges)
	return cube


## 웹은 재질이 처음 그려질 때 셰이더를 만들어 그 프레임이 막힌다. 첫 화면 전에 가림막 뒤에서 모두 한 번씩 그려 둔다.
## 같은 뷰포트에서 그려야 안개·글로우까지 같은 셰이더 조합이 준비된다.
func _prewarm() -> void:
	var world := Node3D.new()
	add_child(world)
	for kind in _kind_meshes:
		world.add_child(_make_obstacle(kind, kind, -6.0))
	var drop: MeshInstance3D = runner.make_prewarm_drop()
	drop.position = Vector3(0.0, 1.0, -3.0)
	world.add_child(drop)
	var cover := CanvasLayer.new()
	cover.layer = 100
	add_child(cover)
	for pair in [["0123456789", _distance_label], [_restart_label.text, _restart_label], ["NEW BEST 0123456789", _best_label]]:  # 글자 그림도 미리 만든다
		var label := Label.new()
		label.text = pair[0]
		label.label_settings = pair[1].label_settings
		cover.add_child(label)
	var curtain := ColorRect.new()
	curtain.color = BOOT_COLOR
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(curtain)
	var fast := 0
	var last := Time.get_ticks_msec()
	for i in PREWARM_MAX_FRAMES:
		await get_tree().process_frame
		fast = fast + 1 if Time.get_ticks_msec() - last < PREWARM_FAST_MS else 0
		last = Time.get_ticks_msec()
		if fast >= PREWARM_FRAMES:
			break
	world.queue_free()
	cover.queue_free()
	prewarmed = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gameReady = performance.now()")  # 첫 화면이 드러난 시각: 프레임 측정의 시작점


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
	_restart_label.offset_top = 370.0 if size.y >= size.x else 200.0  # 웅덩이와 겹치지 않는 자리 (세로는 아래, 가로는 위)


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
	var bar := ObstacleField.BAR_WIDTH
	var d := ObstacleField.BAR_DEPTH
	var b := ObstacleField.BLOCK_SIZE
	_add_kind(ObstacleField.Kind.BLOCK, Vector3(b, b, b), 0.0)
	_add_kind(ObstacleField.Kind.LOW, Vector3(bar, ObstacleField.LOW_TOP, d), 0.0)
	_add_kind(ObstacleField.Kind.HIGH, Vector3(bar, ObstacleField.HIGH_TOP - ObstacleField.HIGH_BOTTOM, d), ObstacleField.HIGH_BOTTOM)


## 종류별 상자 메시·모서리 선 메시·색 재질 (같은 종류끼리 공유). bottom은 바닥에서 아랫면까지 높이.
func _add_kind(kind: ObstacleField.Kind, size: Vector3, bottom: float) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = GLASS_SHADER
	glass.set_shader_parameter("tint", KIND_COLORS[kind]["glass"])
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = KIND_COLORS[kind]["edge"]
	var box := BoxMesh.new()
	box.size = size
	var h := size * 0.5
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var indices := PackedInt32Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if not (i & bit):
				indices.append_array([i, i | bit])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	arrays[Mesh.ARRAY_INDEX] = indices
	var edges := ArrayMesh.new()
	edges.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_kind_meshes[kind] = {"mesh": box, "edges": edges, "y": bottom + h.y, "glass": glass, "edge": edge}


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

	# 최고 기록: 거리 숫자 아래에 작게 (Poppins에 한글이 없어 영문)
	_best_label = Label.new()
	_best_label.name = "BestLabel"
	_best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_best_label.offset_top = 290.0
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := LabelSettings.new()
	bs.font = FONT
	bs.font_size = 40
	bs.font_color = Color(1, 1, 1, 0.7)
	_best_label.label_settings = bs
	layer.add_child(_best_label)
	_show_best()

	# 게임 오버 안내 (Poppins에 한글이 없어 영문)
	_restart_label = Label.new()
	_restart_label.name = "RestartLabel"
	_restart_label.text = "TAP TO RESTART"
	_restart_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_restart_label.offset_left = -360.0
	_restart_label.offset_right = 360.0
	_restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := LabelSettings.new()
	rs.font = FONT
	rs.font_size = 48
	rs.font_color = Color(1, 1, 1, 0.85)
	_restart_label.label_settings = rs
	_restart_label.visible = false
	layer.add_child(_restart_label)

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
