extends Node3D
## 게임 화면. 환경(하늘·안개·글로우), 길, 주인공, 장애물, 거리 표시를 만들고 입력을 받는다.
## 계산은 scripts/logic/ 의 클래스가 맡고, 여기서는 그 결과를 화면에 옮기기만 한다.

const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const BLOCK_SHADER := preload("res://shaders/block.gdshader")
const PILLAR_SHADER := preload("res://shaders/pillar.gdshader")
const NEON_SHADER := preload("res://shaders/neon.gdshader")
const MIRROR_SHADER := preload("res://shaders/mirror.gdshader")
const DASH_SHADER := preload("res://shaders/dash.gdshader")
const STREAK_SHADER := preload("res://shaders/streak.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const FONT := preload("res://assets/fonts/Poppins-ExtraLight.ttf")
## 장애물 종류별 팔레트 이름 (색은 data/speed_palette.json). 파랑 = 옆으로, 주황 = 위로, 분홍 = 아래로.
const KINDS := {
	ObstacleField.Kind.BLOCK: "block",
	ObstacleField.Kind.LOW: "low",
	ObstacleField.Kind.HIGH: "high",
}
const MAX_PIECES := 96       # 종류마다 동시에 그릴 수 있는 장애물 수. z -85~+6에 들어오는 수보다 넉넉하다
const FOLLOW_GAP := 22.0     # 같은 레인의 앞 블록이 이만큼 안이면 연속 블록으로 본다 (2박 + 조금)
const FOLLOW_HAZE := 0.3     # 연속 블록의 뒤쪽 것이 안개 색으로 흐려지는 양
const FLOOR_HAZE_FROM := 0.4  # 바닥 안개 띠는 안개 거리의 이 비율에서 시작한다
const FOG_DENSITY := 0.025   # 안개 거리 약 30~45에서 하늘 아래 먼 세상을 덮는 값. 세상 전체의 안개. 장애물만 안개를 끄고 직접 섞는다 (block.gdshader)
const GLOW_INTENSITY := 1.3  # 얇은 관에서도 바깥으로 빛이 번지게
const GLOW_WIDE := 0.6       # 넓게 퍼지는 번짐 층
const GLOW_LOW := 0.5        # 프레임이 밀릴 때 낮춘 빛 번짐 세기

const RESTART_DELAY := 0.5
const OBSTACLE_FADE := 0.15  # 다시 시작할 때 앞 판 장애물이 작아져 사라지는 시간(초): 한 프레임에 툭 없어지지 않게
const POP_TIME := 0.25       # 다시 시작할 때 대시 격자가 '퐁' 나타나는 시간(초). 장애물은 안개에서 나온다
const PREWARM_FRAMES := 3    # 가림막 뒤에서 이만큼 연달아 빠른 프레임이 나오면 준비 끝 (셰이더는 그래픽 쪽에서 늦게 끝날 수 있다)
const PREWARM_FAST_MS := 50
const PREWARM_MAX_FRAMES := 120  # 아주 느린 기기도 언젠가는 화면을 연다
const STAGE_GLOW_TIME := 0.3  # 음악 단계가 오를 때 난간과 빛 대시가 밝아지는 시간(초)
## 무대 (ART_BIBLE.md 10). 밝기 순서: 주인공 > 장애물 기호 > 테두리·파란 기둥 > 난간 > 빛 줄기 > 바닥·하늘
const ROAD_PEAK_MAX := StageLight.ROAD_PEAK  # 평소 대시의 가장 센 채널이 이보다 밝아지지 않는다
const TINT_RESTART_TIME := 0.5  # 재시작 때 색이 돌아가는 시간(초)
const SKY_RADIUS := 1500.0
const RAIL_X := 2.38            # 난간 관 위치: 슬라이드로 퍼진 몸(1.5 + 0.775)이 닿지 않는 바깥
const RAIL_Y := 0.1
const RAIL_RADIUS := 0.1
const DASH_SIZE := Vector3(0.07, 0.02, 1.0)  # 레인 경계 빛 대시. 길이는 속도에 맞춰 셰이더가 늘린다 (dash_length)
const STREAK_MAX := 64          # 빛 줄기 풀 (data/speed_palette.json의 t = 1 값)
const STREAK_SEED := 606        # 줄기 자리를 고정하는 시드
const STREAK_X := Vector2(2.9, 8.0)  # 길 바깥 좌우 거리
const STREAK_Y := Vector2(0.4, 7.0)
const FOV_SLOW := 62.0       # 시야각: 색 진하기와 함께 속도가 오른 뒤 2마디 동안 넓어진다
const FOV_FAST := 68.0
const POP_SCALE := 1.22      # 새 기록 순간 거리 숫자가 커지는 배율 (말랑)
const POP_UP := 0.08
const POP_DOWN := 0.32
const BOOT_COLOR := Color(0.02, 0.016, 0.051)  # project.godot boot_splash/bg_color와 같은 색: 로딩에서 가림막으로 이어져 보이게

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
var _obstacles := {}  # id -> Piece
var _leaving: Array[Piece] = []  # 재시작 때 작아지며 사라지는 앞 판 장애물
var _pieces_dirty := true        # 장애물이 생기거나 없어지거나 크기가 변해 MultiMesh를 다시 써야 한다
var _animating := 0              # 크기가 변하는 중인 트윈 수
var _pieces_root: Node3D         # 장애물 MultiMesh의 부모. 세상과 함께 움직여 장애물마다 값을 바꾸지 않는다
var _floor_material: ShaderMaterial
var _rail_material: ShaderMaterial
var _dashes: MultiMeshInstance3D
var _dash_material: ShaderMaterial
var _streak_material: ShaderMaterial
var _streaks: MultiMesh
var _kind_meshes := {}  # Kind -> {body, mirror: MultiMesh, block, reflect: ShaderMaterial}, 기둥은 pillar: ShaderMaterial (반투명 몸통)
var _sky_material: ShaderMaterial
var _env: Environment
var _rail_base := 1.0    # 지금 진하기의 난간 빛 세기
var _tint := -1.0        # 지금 화면의 색 진하기
var _stage_glow := 0.0   # 지금의 단계 빛남 (1 → 0)
var _fog := Vector2(-1.0, -1.0)  # 지금 안개 (진해지기 시작하는 거리, 사라지는 거리)
var _stretch := 1.0      # 160BPM 속도보다 빠를 때 대시·빛 줄기 길이 배율
var _dash_len := 1.2     # 지금 진하기의 대시·빛 줄기 길이 (배율 전)
var _streak_len := 1.9
var _tint_from := -1.0   # 재시작 순간의 진하기. 음수면 돌아가는 중이 아니다
var _tint_clock := 0.0   # 재시작 순간의 음악 시간
var _row_beats: Array[float] = []  # 칸마다 지금 담긴 박. 바뀐 칸만 다시 쓴다
var _row_segments := 0            # 대시 줄을 쓸 때의 사다리 구간 수. 구간이 늘면 앞으로 올 줄의 자리가 바뀐다
var _row_ladder: MusicLadder
var _quality := QualityGuard.new()
var _effect_level := 0  # 지금 적용된 효과 단계
var _last_frame_usec := 0
var _dead_time := 0.0
var _restart_label: Label
var _camera: Camera3D
var _distance_label: Label
var _best_label: Label
var _pop: Tween
var _scroll := 0.0
var _music_t := 0.0  # 박자 기준 시간


## 장애물 하나의 화면 상태. 노드 대신 MultiMesh 한 칸에 옮겨 그린다.
class Piece:
	extends RefCounted
	var kind: int
	var position: Vector3
	var scale := Vector3.ONE
	var haze := 0.0
	var item: Dictionary       # 이 장애물의 판정 항목
	var wide := 0.0            # 1이면 이웃 레인까지 덮는 2칸 벽
	var hidden := false        # 2칸 벽의 짝: 판정 항목만 있고 그림은 벽 하나가 맡는다


## 시드를 고정했으면(주소의 ?seed, 테스트) 판마다 같은 배치, 아니면 판마다 새 배치
func _new_field() -> void:
	field = ObstacleField.new(seed_value if seed_value != 0 else randi() | 1, AudioManager.ladder)


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
	_apply_tint(AudioManager.ladder.tint_at(0.0))
	_apply_fog(AudioManager.ladder, 0.0)
	_place_rows()
	runner = Runner.new()
	runner.position = Vector3(RunLogic.lane_x(lane), 0.0, 0.0)
	add_child(runner)
	_build_ui()
	get_viewport().size_changed.connect(_fit_camera)
	get_viewport().size_changed.connect(_fit_render_scale)
	_fit_camera()
	_fit_render_scale()
	_prewarm()


func _process(delta: float) -> void:
	advance(delta, AudioManager.music_time)
	_sync_pieces()
	if OS.has_feature("web") and prewarmed:
		_watch_frames()


## 실제 프레임 간격을 재서 밀리면 효과를 한 단계 낮춘다 (엔진 delta는 고르게 다듬어져 밀림이 덜 보인다)
func _watch_frames() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0 and _quality.push((now - _last_frame_usec) / 1000000.0):
		apply_quality(_quality.level)
		print("QUALITY %d %.1f" % [_quality.level, now / 1000000.0])  # 측정 기록용: 언제 낮췄는지
	_last_frame_usec = now


## 효과 단계: 1 빛 줄기 줄이기, 2 반사 끄기, 3 MSAA 2x, 4 빛 번짐 낮추기. 이 단계까지 전부 적용한다.
func apply_quality(level: int) -> void:
	_effect_level = level
	var t := _tint
	_tint = -1.0
	_apply_tint(t)  # 줄기 수는 진하기 값과 함께 정해진다
	for kind in _kind_meshes:
		_kind_meshes[kind]["reflect"].set_shader_parameter("reflect_on", 0.0 if level >= 2 else 1.0)
	runner.set_reflection(level < 2)
	if level >= 3:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	if level >= 4:
		_env.glow_intensity = GLOW_LOW


## 3D만 낮은 해상도로 그리고 늘린다. 글자는 원래 해상도 그대로다.
func _fit_render_scale() -> void:
	get_viewport().scaling_3d_scale = QualityGuard.render_scale(DisplayServer.window_get_size())


## 첫 입력: 음악 0초와 함께 세상이 출발한다. 미리 놓인 장애물을 음악 시간에 맞춘다 (출력 지연만큼의 차이).
func begin() -> void:
	started = true
	_dash_material.set_shader_parameter("sparkle_on", 1.0)
	AudioManager.start_music()
	field.ladder = AudioManager.ladder  # 음악과 함께 시작한 사다리: 경계가 여기에 쌓인다
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
		if not item.has("cleared") and PlayerAction.hits(item["kind"], dx, PlayerAction.swept_dz(item), player.height(), player.is_ducking()):
			_game_over(item)
			return


## 음악 시간에서 이동 거리·속도·대시 박자·단계 빛남을 구해 세상에 옮긴다.
func _move_world() -> void:
	var ladder := AudioManager.ladder
	var now := ladder.distance_at(_music_t)
	_scroll += now - travel
	travel = now
	speed = ladder.speed_at(_music_t)
	_streak_material.set_shader_parameter("scroll", _scroll)
	_place_rows()
	_apply_tint(_tint_now())
	_apply_fog(ladder, _music_t)
	_apply_stretch(maxf(speed / MusicLadder.STEPS[MusicLadder.TOP]["speed"], 1.0))
	var beat := ladder.beat_at(_music_t)
	var beat_time := MusicLadder.beat_time(ladder.segment_at(_music_t)["step"])
	_dash_material.set_shader_parameter("pulse", BeatRows.pulse(fposmod(beat, 1.0) * beat_time))
	var age := ladder.stage_up_age(_music_t)
	_set_stage_glow(1.0 - age / STAGE_GLOW_TIME if age >= 0.0 and age < STAGE_GLOW_TIME else 0.0)
	_apply_step(field.step(travel, ladder.spawn_distance_at(_music_t)))


## 대시 줄을 지금 박 자리에 놓는다. 음악 시간에서 바로 계산하므로 템포가 바뀌어도 박 줄은 박에 주인공 옆에 닿는다.
## 줄은 이동 거리 좌표로 고정해 두고 부모만 움직인다. 값을 쓰는 칸은 새로 들어온 박과, 구간이 늘어 자리가 바뀐 줄뿐이다.
func _place_rows() -> void:
	var ladder := AudioManager.ladder
	_dashes.position.z = ladder.distance_at(_music_t)
	var now_beat := ladder.beat_at(_music_t)
	var rewrite := ladder != _row_ladder or ladder.segments.size() != _row_segments
	_row_ladder = ladder
	_row_segments = ladder.segments.size()
	for i in BeatRows.COUNT:
		var beat := BeatRows.beat_of(i, now_beat)
		var slot := BeatRows.slot_of(beat)
		if not rewrite and _row_beats[slot] == beat:
			continue
		_row_beats[slot] = beat
		for side in 2:
			var origin := Vector3((side - 0.5) * RunLogic.LANE_WIDTH, DASH_SIZE.y * 0.5, -ladder.distance_of_beat(beat))
			_dashes.multimesh.set_instance_transform(slot * 2 + side, Transform3D(Basis.IDENTITY, origin))


## 지금의 색 진하기: 사다리 값. 재시작 뒤 0.5초는 그 순간의 진하기에서 부드럽게 돌아간다.
func _tint_now() -> float:
	var target := AudioManager.ladder.tint_at(_music_t)
	if _tint_from < 0.0:
		return target
	var back := (_music_t - _tint_clock) / TINT_RESTART_TIME
	if back >= 1.0:
		_tint_from = -1.0
		return target
	return lerpf(_tint_from, target, smoothstep(0.0, 1.0, maxf(back, 0.0)))


## 안개 거리(속도 × 보이는 시간)를 장애물·대시·난간·바닥에 똑같이 넣는다. 값이 그대로면 아무것도 하지 않는다.
func _apply_fog(ladder: MusicLadder, t: float) -> void:
	var fog := Vector2(ladder.fog_clear_at(t), ladder.fog_at(t))
	if fog == _fog:
		return
	_fog = fog
	var materials: Array[ShaderMaterial] = [_dash_material, _rail_material]
	for shape: Dictionary in _kind_meshes.values():
		materials.append(shape["block"])
		materials.append(shape["reflect"])
		if shape.has("pillar"):
			materials.append(shape["pillar"])
	for material in materials:
		material.set_shader_parameter("fog_near", fog.x)
		material.set_shader_parameter("fog_far", fog.y)
	_floor_material.set_shader_parameter("haze_near", fog.y * FLOOR_HAZE_FROM)
	_floor_material.set_shader_parameter("haze_far", fog.y)


## 160BPM 뒤 속도가 계속 오르면 대시와 빛 줄기도 그만큼 길어진다 (시야각은 68°에서 멈춘다)
func _apply_stretch(stretch: float) -> void:
	if stretch == _stretch:
		return
	_stretch = stretch
	_streak_material.set_shader_parameter("streak_length", _streak_len * stretch)
	_dash_material.set_shader_parameter("dash_length", _dash_len * stretch)


## 진하기 t의 색을 재질 값으로만 옮긴다. 새 재질을 만들지 않아 셰이더를 다시 준비할 일이 없고, 값이 그대로면 아무것도 하지 않는다.
func _apply_tint(t: float) -> void:
	if t == _tint:
		return
	_tint = t
	var c := SpeedPalette.at(t)
	_sky_material.set_shader_parameter("top", c["sky_top"])
	_sky_material.set_shader_parameter("horizon", c["horizon"])
	_sky_material.set_shader_parameter("curve", c["sky_band"])
	_env.fog_light_color = c["horizon"]
	_floor_material.set_shader_parameter("road_color", c["floor"])
	_floor_material.set_shader_parameter("rail_color", c["rail"])
	_floor_material.set_shader_parameter("haze_color", c["horizon"])
	_rail_material.set_shader_parameter("color", c["rail"])
	_rail_base = c["rail_energy"]
	var rail: Color = c["rail"]
	_dash_material.set_shader_parameter("color", rail)
	_dash_material.set_shader_parameter("max_energy", ROAD_PEAK_MAX / maxf(rail.r, maxf(rail.g, rail.b)))
	_set_stage_glow(_stage_glow)
	_streaks.visible_instance_count = QualityGuard.streaks(c["streak_count"], _effect_level)
	_streak_len = c["streak_length"]
	_dash_len = c["dash_length"]
	_streak_material.set_shader_parameter("streak_length", _streak_len * _stretch)
	_streak_material.set_shader_parameter("level", c["streak_alpha"])
	_dash_material.set_shader_parameter("dash_length", _dash_len * _stretch)
	_rail_material.set_shader_parameter("fog_color", c["horizon"])
	_camera.fov = lerpf(FOV_SLOW, FOV_FAST, t)
	for kind: ObstacleField.Kind in KINDS:
		var name_: String = KINDS[kind]
		var shape: Dictionary = _kind_meshes[kind]
		var edge: Color = c[name_ + "_edge"]
		var body: Color = c.get(name_ + "_body", c["body"])  # 옆 장애물만 자기 몸통 색(파랑)이 있다
		shape["block"].set_shader_parameter("body_color", body)
		shape["block"].set_shader_parameter("tint", c[name_])
		shape["block"].set_shader_parameter("edge_color", edge)
		if c.has(name_ + "_mark"):  # 기둥에는 기호가 없다
			shape["block"].set_shader_parameter("mark_color", c[name_ + "_mark"])
		shape["block"].set_shader_parameter("fog_color", c["horizon"])
		if shape.has("pillar"):
			shape["pillar"].set_shader_parameter("body_color", body)
			shape["pillar"].set_shader_parameter("fog_color", c["horizon"])
		shape["reflect"].set_shader_parameter("body_color", body)
		shape["reflect"].set_shader_parameter("edge_color", Color(minf(edge.r, 1.0), minf(edge.g, 1.0), minf(edge.b, 1.0)))  # 화면 범위로 줄인 빛 색


## 단계가 오를 때의 빛남 (1 → 0)을 난간과 대시에 준다.
func _set_stage_glow(amount: float) -> void:
	_stage_glow = amount
	_rail_material.set_shader_parameter("energy", StageLight.energy(_rail_base, amount))
	_dash_material.set_shader_parameter("stage_add", amount * (StageLight.PEAK_MAX - StageLight.ROAD_PEAK))


## field.step() 결과를 장애물 노드에 옮긴다.
func _apply_step(result: Dictionary) -> void:
	for item in result["spawned"]:
		_spawn_node(item)
	for id in result["removed"]:
		_obstacles.erase(id)
		_pieces_dirty = true
	for item in field.items:
		_obstacles[item["id"]].position.z = item["z"]


func _animation_done() -> void:
	_animating -= 1
	_pieces_dirty = true  # 마지막 크기까지 옮긴다


## 바뀐 프레임에만 MultiMesh 값을 쓴다. 보통 프레임은 부모 위치만 움직인다.
func _sync_pieces() -> void:
	_pieces_root.position.z = _scroll
	if not _pieces_dirty and _animating == 0:
		return
	_pieces_dirty = false
	var used := {}
	for kind in _kind_meshes:
		used[kind] = 0
	for piece: Piece in _pieces_far_first():
		if piece.hidden:
			continue
		var slot: int = used[piece.kind]
		if slot >= MAX_PIECES:
			continue
		used[piece.kind] = slot + 1
		var at := Transform3D(Basis.from_scale(piece.scale), Vector3(piece.position.x, piece.position.y, piece.position.z - _scroll))
		var shape: Dictionary = _kind_meshes[piece.kind]
		shape["body"].set_instance_transform(slot, at)
		var custom := Color(piece.haze, piece.wide, 0.0, 0.0)
		shape["body"].set_instance_custom_data(slot, custom)
		shape["mirror"].set_instance_transform(slot, at)
		shape["mirror"].set_instance_custom_data(slot, custom)
	for kind in _kind_meshes:
		_kind_meshes[kind]["body"].visible_instance_count = used[kind]
		_kind_meshes[kind]["mirror"].visible_instance_count = used[kind]


## 반투명 기둥은 MultiMesh 안의 순서대로 쌓이므로 먼 것부터 쓴다
func _pieces_far_first() -> Array:
	var pieces: Array = _obstacles.values() + _leaving
	pieces.sort_custom(func(a: Piece, b: Piece) -> bool: return a.position.z < b.position.z)
	return pieces


## 부딪힌 뒤: 세상이 아주 잠깐 느려졌다 멈추고, 주인공은 충돌 모션을 이어 간다.
func _advance_dead(delta: float) -> void:
	var slow := CrashMotion.slow_delta(_dead_time, delta)
	_dead_time += delta
	_scroll += speed * slow
	_streak_material.set_shader_parameter("scroll", _scroll)
	_dashes.position.z += speed * slow
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
	_set_stage_glow(0.0)
	_dash_material.set_shader_parameter("pulse", 0.0)
	_dash_material.set_shader_parameter("sparkle_on", 0.0)
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
	_tint_from = _tint  # 부딪힌 순간의 색에서 돌아간다
	AudioManager.restart_music()
	_music_t = AudioManager.music_time
	_tint_clock = _music_t
	travel = AudioManager.ladder.distance_at(_music_t)  # 출력 지연만큼 음수에서 출발: 다음 프레임에 길이 뒤로 튀지 않게
	player = PlayerAction.new()
	_swipe = SwipeDetector.new()
	var old_pieces := _obstacles.values()
	_obstacles.clear()
	_new_field()
	AudioManager.unblock()
	_apply_fog(AudioManager.ladder, _music_t)
	for piece: Piece in old_pieces:
		_leaving.append(piece)
		_animating += 1
		var fade := create_tween().set_parallel()
		fade.tween_property(piece, "scale", Vector3.ONE * 0.01, OBSTACLE_FADE)
		fade.tween_property(piece, "position:z", piece.position.z + speed * OBSTACLE_FADE, OBSTACLE_FADE)
		fade.chain().tween_callback(func() -> void:
			_leaving.erase(piece)
			_animation_done())
	_dashes.position.z = 0.0  # 부딪힌 뒤 밀려 간 만큼 되돌린다
	_place_rows()
	_dash_material.set_shader_parameter("sparkle_on", 1.0)
	# 박자가 0박으로 돌아가며 대시 격자가 옮겨 가는 순간을 장애물과 같은 '퐁'으로 가린다
	var appear := func(a: float) -> void: _dash_material.set_shader_parameter("appear", a)
	appear.call(0.0)
	create_tween().tween_method(appear, 0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	var piece := Piece.new()
	piece.kind = item["kind"]
	piece.position = Vector3(RunLogic.lane_x(item["lane"]), 0.0, item["z"])
	piece.item = item
	var twin := _wall_twin(item)
	if twin:
		piece.hidden = true
		twin.wide = 1.0
		twin.position.x = (twin.position.x + piece.position.x) * 0.5
		twin.haze = _haze_of(twin)
	else:
		piece.haze = _haze_of(piece)
	_obstacles[item["id"]] = piece
	_pieces_dirty = true


## 같은 줄 이웃 레인에 이미 놓인 기둥. 같은 줄은 같은 프레임에 차례로 생기므로 앞서 놓인 것을 넓힌다.
func _wall_twin(item: Dictionary) -> Piece:
	for other: Piece in _obstacles.values():
		if not other.hidden and ObstacleField.forms_wall(other.item, item):
			return other
	return null


## 같은 레인에 바로 앞서 오는 옆 블록이 있으면 뒤쪽 것을 조금 흐리게 한다: 연속 블록이 한 덩어리로 보이지 않게 하는 깊이 단서
func _haze_of(piece: Piece) -> float:
	if piece.kind != ObstacleField.Kind.BLOCK:
		return 0.0
	for other: Piece in _obstacles.values():
		var gap := other.position.z - piece.position.z
		var overlap := absf(other.position.x - piece.position.x) < RunLogic.LANE_WIDTH * 0.5 * (other.wide + piece.wide) + 0.1  # 벽과 기둥이 겹치는 레인도 연속으로 본다
		if other.kind == piece.kind and overlap and gap > 0.0 and gap < FOLLOW_GAP:
			return FOLLOW_HAZE
	return 0.0


## 장애물을 모두 지운다 (화면 확인 도구, 테스트)
func clear_pieces() -> void:
	_obstacles.clear()
	_pieces_dirty = true


## 웹은 재질이 처음 그려질 때 셰이더를 만들어 그 프레임이 막힌다. 첫 화면 전에 가림막 뒤에서 모두 한 번씩 그려 둔다.
## 같은 뷰포트에서 그려야 안개·글로우까지 같은 셰이더 조합이 준비된다.
func _prewarm() -> void:
	var world := Node3D.new()
	add_child(world)
	var samples: Array[Piece] = []
	for kind in _kind_meshes:  # 모든 종류의 재질을 한 번씩 그린다
		var sample := Piece.new()
		sample.kind = kind
		sample.position = Vector3(RunLogic.lane_x(kind), 0.0, -6.0)
		samples.append(sample)
		_leaving.append(sample)
	_pieces_dirty = true
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
	for sample in samples:
		_leaving.erase(sample)
	_pieces_dirty = true
	prewarmed = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gameReady = performance.now()")  # 첫 화면이 드러난 시각: 프레임 측정의 시작점


# ---------- 장면 만들기 ----------

func _build_environment() -> void:
	# 안개 색을 지평선과 맞춰 먼 곳이 자연스럽게 흐려진다. 색은 _apply_tint가 정한다.
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.fog_enabled = true
	_env.fog_density = FOG_DENSITY
	_env.fog_sky_affect = 0.0
	_env.glow_enabled = true
	_env.glow_intensity = GLOW_INTENSITY
	_env.glow_strength = 1.1
	_env.set_glow_level(3, GLOW_WIDE)
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.9
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var dome := SphereMesh.new()
	dome.radius = SKY_RADIUS
	dome.height = SKY_RADIUS * 2.0
	dome.radial_segments = 16
	dome.rings = 8
	var sky := MeshInstance3D.new()
	sky.name = "Sky"
	sky.mesh = dome
	sky.material_override = _sky_material
	sky.position = Vector3(0.0, 3.3, 5.4)  # 카메라 자리
	add_child(sky)


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
	_build_rails()
	_build_dashes()
	_build_streaks()


func _build_rails() -> void:
	_rail_material = ShaderMaterial.new()
	_rail_material.shader = NEON_SHADER
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = ArtMeshes.rails(RAIL_X, RAIL_Y, RAIL_RADIUS, 8.0, -128.0, 8.0)
	rails.material_override = _rail_material
	add_child(rails)


## 레인 경계 2줄의 대시. MultiMesh 하나에 담고 새 박의 줄만 값을 쓴다 (_place_rows).
func _build_dashes() -> void:
	_dash_material = ShaderMaterial.new()
	_dash_material.shader = DASH_SHADER
	var dash := BoxMesh.new()
	dash.size = DASH_SIZE
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = dash
	many.instance_count = BeatRows.COUNT * 2
	_row_beats.resize(BeatRows.COUNT)
	_dashes = MultiMeshInstance3D.new()
	_dashes.name = "Dashes"
	_dashes.multimesh = many
	_dashes.material_override = _dash_material
	add_child(_dashes)


## 카메라 옆 빛 줄기. 자리는 고정이고 움직임은 셰이더가 이동 거리로 계산한다. 앞쪽 칸부터 보이므로 어떤 개수에서도 고르게 흩어져 있다.
func _build_streaks() -> void:
	_streak_material = ShaderMaterial.new()
	_streak_material.shader = STREAK_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = STREAK_SEED
	_streaks = MultiMesh.new()
	_streaks.transform_format = MultiMesh.TRANSFORM_3D
	_streaks.mesh = BoxMesh.new()
	_streaks.instance_count = STREAK_MAX
	for i in STREAK_MAX:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(STREAK_X.x, STREAK_X.y), rng.randf_range(STREAK_Y.x, STREAK_Y.y), rng.randf_range(0.0, 60.0))
		_streaks.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
	var node := MultiMeshInstance3D.new()
	node.name = "Streaks"
	node.multimesh = _streaks
	node.material_override = _streak_material
	node.extra_cull_margin = 16384.0
	add_child(node)


## 종류마다 MultiMesh: 몸통과 반사 두 번만 그린다. 장애물이 늘어도 그리는 횟수는 같다.
func _build_obstacle_resources() -> void:
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)
	for kind: ObstacleField.Kind in KINDS:
		var meshes := ArtMeshes.obstacle(kind)
		var body := _new_pieces_mesh(meshes["body"])
		var mirror := _new_pieces_mesh(meshes["mirror"])
		var block := ShaderMaterial.new()
		block.shader = BLOCK_SHADER
		var reflect := ShaderMaterial.new()
		reflect.shader = MIRROR_SHADER
		reflect.render_priority = -1  # 젤리 발밑 그림자보다 먼저 그린다
		block.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
		reflect.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
		reflect.set_shader_parameter("wall_shadow", RunLogic.LANE_WIDTH * 0.5 / ArtMeshes.SHADOW_HALF.x)
		var body_override: Material = block
		_kind_meshes[kind] = {"body": body, "mirror": mirror, "block": block, "reflect": reflect}
		if kind == ObstacleField.Kind.BLOCK:  # 표면마다 재질이 달라 덮어쓰기 재질을 쓰지 않는다
			var pillar := ShaderMaterial.new()
			pillar.shader = PILLAR_SHADER
			pillar.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
			pillar.render_priority = 1  # 젤리보다 뒤에: 젤리 뒤의 기둥은 깊이에 막히고, 젤리 앞의 기둥은 그 위에 비친다
			meshes["body"].surface_set_material(0, pillar)
			meshes["body"].surface_set_material(1, block)
			body_override = null
			_kind_meshes[kind]["pillar"] = pillar
		for pair: Array in [[body, body_override], [mirror, reflect]]:
			var node := MultiMeshInstance3D.new()
			node.multimesh = pair[0]
			node.material_override = pair[1]
			node.extra_cull_margin = 16384.0  # 반사는 셰이더가 옮겨 그리고, 영역 계산보다 몇 번 더 그리는 편이 싸다
			_pieces_root.add_child(node)


func _new_pieces_mesh(mesh: Mesh) -> MultiMesh:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.use_colors = true  # 끄면 꼭짓점 색(COLOR)의 RGB가 0으로 읽혀 반사가 검게 나온다
	many.mesh = mesh
	many.instance_count = MAX_PIECES
	for i in MAX_PIECES:
		many.set_instance_color(i, Color.WHITE)
	many.visible_instance_count = 0
	return many


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
