extends TestCase
## 무대·장애물 아트의 규칙: 보이는 모양 = 판정 범위, 판정 값 그대로, 대시 줄은 박에 닿음, 반사는 몸을 따라감, 지나간 장애물은 그대로 사라짐.
## 충돌 소리·음악을 실제로 켜서 AudioManager 상태가 남는다. test_audio보다 뒤에 돌도록 파일 이름을 test_track_로 시작한다.

const K := ObstacleField.Kind
const STEP := 1.0 / 60.0
const TEST_BEST := "user://test_best_art.txt"


func _make_main(seed_value := 1234) -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = seed_value
	DirAccess.remove_absolute(TEST_BEST)
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	main.started = true
	return main


func _meshes(kind: K) -> Dictionary:
	return ArtMeshes.obstacle(kind)


## 몸통 메시에서 부위(ArtMeshes.Part) 꼭짓점의 영역. 관은 둥근 끝까지 포함한다
func _box(kind: K, part: int) -> AABB:
	var mesh: ArrayMesh = _meshes(kind)["body"]
	var box := AABB()
	var first := true
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			if int(arrays[Mesh.ARRAY_TEX_UV][i].y) != part:
				continue
			var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box


## 값이 달라지면 게임이 달라지므로 일부러 숫자를 그대로 적어 둔다
func test_판정_값은_그대로() -> void:
	assert_eq(PlayerAction.HIT_X, 0.7)
	assert_eq(PlayerAction.HIT_Z, 0.7)
	assert_eq(ObstacleField.BLOCK_SIZE, 1.1)
	assert_eq(ObstacleField.BAR_WIDTH, 1.3)
	assert_eq(ObstacleField.BAR_DEPTH, 0.5)
	assert_eq(ObstacleField.LOW_TOP, 0.45)
	assert_eq(ObstacleField.HIGH_BOTTOM, 0.62)
	assert_eq(ObstacleField.HIGH_TOP, 1.32)
	assert_eq(PlayerAction.JUMP_HEIGHT, 1.6)
	assert_eq(PlayerAction.JUMP_TIME, 0.6)
	assert_eq(PlayerAction.SLIDE_TIME, 0.65)
	assert_eq(PlayerAction.CROUCH_SCALE, 0.45)
	assert_eq(RunLogic.LANE_WIDTH, 1.5)
	# 판정 함수의 표: 종류, dx, dz, 높이, 슬라이드 → 결과
	for row: Array in [
		[K.BLOCK, 0.0, 0.0, 0.0, false, true],
		[K.BLOCK, 0.0, 0.0, 1.6, false, true],  # 기둥은 넘을 수 없다
		[K.BLOCK, 0.71, 0.0, 0.0, false, false],
		[K.BLOCK, 0.0, 0.71, 0.0, false, false],
		[K.LOW, 0.0, 0.0, 0.44, false, true],
		[K.LOW, 0.0, 0.0, 0.45, false, false],
		[K.HIGH, 0.0, 0.0, 0.0, false, true],
		[K.HIGH, 0.0, 0.0, 0.0, true, false],
	]:
		assert_eq(PlayerAction.hits(row[0], row[1], row[2], row[3], row[4]), row[5], str(row))


func test_보이는_면이_판정_크기에_정확히_맞음() -> void:
	var cases := {
		K.BLOCK: [Vector3(1.1, 2.1, 1.1), 0.0],
		K.LOW: [Vector3(1.3, 0.45, 0.5), 0.0],
		K.HIGH: [Vector3(1.3, 0.7, 0.5), 0.62],
	}
	for kind in cases:
		var box: AABB = _box(kind, ArtMeshes.Part.BODY)
		assert_true(box.size.is_equal_approx(cases[kind][0]), "크기 %s: %s" % [kind, box.size])
		assert_true(is_equal_approx(box.position.y, cases[kind][1]), "아랫면 %s: %f" % [kind, box.position.y])
		assert_true(absf(box.position.x + box.size.x * 0.5) < 0.001 and absf(box.position.z + box.size.z * 0.5) < 0.001, "레인 가운데 %s" % kind)


func test_옆_블록은_점프보다_확실히_높음() -> void:
	assert_true(ObstacleField.BLOCK_HEIGHT - PlayerAction.JUMP_HEIGHT >= 0.4)


func test_슬라이드_블록에는_받침이_없고_아래_빛_웅덩이는_블록보다_좁고_가장자리가_사라짐() -> void:
	var half := RunLogic.LANE_WIDTH * 0.5
	var meshes := _meshes(K.HIGH)
	var lines: AABB = _box(K.HIGH, ArtMeshes.Part.EDGE)
	assert_true(lines.position.y >= ObstacleField.HIGH_BOTTOM - 0.1, "선이 블록 아래로 내려가지 않음 %f" % lines.position.y)
	assert_true(lines.position.x > -half, "선")
	var center := 0.0
	var arrays: Array = meshes["mirror"].surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		if p.y != 0.0:
			continue
		var c: Color = arrays[Mesh.ARRAY_COLOR][i]
		center = maxf(center, c.a)
		assert_eq(c.b, 1.0, "멀어도 그리는 바닥 흔적")
		assert_true(absf(p.x) < ObstacleField.BAR_WIDTH * 0.5, "막대 폭보다 좁음 %f" % p.x)
		var r := Vector2(p.x / ArtMeshes.POOL_HALF.x, p.z / ArtMeshes.POOL_HALF.y).length()
		assert_true(r <= 1.001, "타원 안")
		if r > 0.999:
			assert_eq(c.a, 0.0, "가장자리 0%%")
	assert_true(center > 0.2 and center <= 0.35, "가운데 %f" % center)


## 기호 하나가 면의 65~75% (둥근 끝까지 포함한 폭과 높이), 앞면에 있고 면 안에 든다. 선은 화면에서 2픽셀 이상 (v0.9.0: 멀리서 ^가 뭉개짐)
func test_기호는_앞면의_70퍼센트이고_화면에서_2픽셀_이상() -> void:
	var shader: Shader = load("res://shaders/block.gdshader")
	var radius := RegEx.create_from_string("mark_min_pixels = ([0-9.]+)").search(shader.code).get_string(1).to_float()  # 헤드리스는 셰이더 기본값을 읽지 못해 코드에서 읽는다
	assert_true(radius * 2.0 >= 2.0, "선 굵기(반지름 × 2) 2픽셀 이상: %f" % radius)
	for kind: K in [K.LOW, K.HIGH]:
		var face: AABB = _box(kind, ArtMeshes.Part.BODY)
		var mark: AABB = _box(kind, ArtMeshes.Part.MARK)
		for axis in 2:
			var share: float = mark.size[axis] / face.size[axis]
			assert_true(share >= 0.65 and share <= 0.75, "종류 %d 축 %d: %f" % [kind, axis, share])
		assert_true(absf(mark.get_center().y - face.get_center().y) < 0.001, "종류 %d: 가운데" % kind)
		assert_true(mark.end.z > face.end.z, "종류 %d: 앞면에서 솟음" % kind)
		assert_true(mark.position.z > 0.0, "종류 %d: 앞면에만" % kind)


## 기둥은 기호 없이 키 큰 실루엣으로 읽힌다. 모양과 판정은 v0.6.0과 같다
func test_기둥에는_기호가_없고_크기는_판정_그대로() -> void:
	var mesh: ArrayMesh = _meshes(K.BLOCK)["body"]
	assert_eq(mesh.get_surface_count(), 2, "몸통과 테두리가 따로")
	for uv: Vector2 in mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
		assert_eq(int(uv.y), ArtMeshes.Part.BODY, "표면 0은 몸통만")
	for uv: Vector2 in mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV]:
		assert_eq(int(uv.y), ArtMeshes.Part.EDGE, "표면 1은 테두리만, 기호 없음")
	var body := _box(K.BLOCK, ArtMeshes.Part.BODY)
	assert_true(is_equal_approx(body.size.x, ObstacleField.BLOCK_SIZE), "폭")
	assert_true(is_equal_approx(body.size.y, ObstacleField.BLOCK_HEIGHT), "키")
	assert_eq(ObstacleField.BLOCK_HEIGHT, 2.1, "높이 그대로")


## 뒤집힌 ^는 슬라이드 기호 v로 읽힌다
func test_반사에는_기호가_없음() -> void:
	for kind: K in [K.LOW, K.HIGH]:
		var mark := _box(kind, ArtMeshes.Part.MARK)
		assert_true(mark.size.x > 0.0, "몸통에는 기호가 있음")
		var arrays: Array = _meshes(kind)["mirror"].surface_get_arrays(0)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			if arrays[Mesh.ARRAY_COLOR][i].r > 0.5 and arrays[Mesh.ARRAY_COLOR][i].b < 0.5:
				assert_true(absf(p.x) > mark.end.x or absf(p.y + mark.get_center().y) > mark.size.y * 0.5, "종류 %d: 기호 자리에 빛 없음 %s" % [kind, p])


## 불투명 재질은 뒷면을 잘라 낸다. 감기 방향이 뒤집히면 몸통이 투명해 보이고 기호가 사라진다 (v0.6.0에서 실제로 겪음)
func test_몸통과_관은_바깥이_앞면() -> void:
	for kind: K in [K.BLOCK, K.LOW, K.HIGH]:
		var mesh: ArrayMesh = _meshes(kind)["body"]
		var wrong := 0
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(0, v.size(), 3):
				var cross := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
				if cross.length() > 0.000001 and cross.dot(n[i] + n[i + 1] + n[i + 2]) > 0.0:  # Godot는 시계 방향이 앞면
					wrong += 1
		assert_eq(wrong, 0, "종류 %d: 뒤집힌 삼각형" % kind)


func test_몸통은_불투명이고_안개를_직접_섞음() -> void:
	var code: String = load("res://shaders/block.gdshader").code
	assert_false(code.contains("ALPHA"), "불투명")
	assert_true(code.contains("fog_disabled"))
	assert_false(ResourceLoader.exists("res://shaders/glass.gdshader"), "유리 재질 제거")


## 기둥 몸통만 반투명이다. 점프·슬라이드 블록과 기둥 테두리는 불투명으로 남아 또렷하다
func test_기둥_몸통만_반투명이고_깊이를_기록하지_않음() -> void:
	var code: String = load("res://shaders/pillar.gdshader").code
	assert_true(code.contains("depth_draw_never"), "뒤 장애물을 가리지 않음")
	assert_true(code.contains("ALPHA"))
	var main := _make_main()
	await wait_frames()
	var pillar: ShaderMaterial = main._kind_meshes[K.BLOCK]["pillar"]
	var alpha := RegEx.create_from_string("body_alpha = ([0-9.]+)").search(code).get_string(1).to_float()
	assert_true(alpha >= 0.5 and alpha <= 0.55, "불투명도 %f" % alpha)
	assert_true(pillar.render_priority > 0, "젤리보다 뒤에 그려 앞뒤가 맞음")
	var mesh: ArrayMesh = main._kind_meshes[K.BLOCK]["body"].mesh
	assert_eq(mesh.surface_get_material(0), pillar)
	assert_eq(mesh.surface_get_material(1), main._kind_meshes[K.BLOCK]["block"], "테두리는 불투명 재질")
	for kind: K in [K.LOW, K.HIGH]:
		assert_false(main._kind_meshes[kind].has("pillar"), "종류 %d은 그대로" % kind)
		assert_eq(main._kind_meshes[kind]["body"].mesh.get_surface_count(), 1)
	main._apply_tint(1.0)
	assert_true(pillar.get_shader_parameter("body_color").is_equal_approx(Color("1268b8")), "진하기를 따라감")
	main.queue_free()


## 기둥 접지 그림자는 멀어도, 반사를 꺼도 남는다 (COLOR.b). 연속 기둥 사이 바닥에서 서 있는 자리를 말해 준다
func test_기둥에만_접지_그림자() -> void:
	for kind: K in [K.BLOCK, K.LOW, K.HIGH]:
		var colors: PackedColorArray = _meshes(kind)["mirror"].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var found := 0.0
		for c: Color in colors:
			if c.g > 0.5 and c.b > 0.5:
				found = maxf(found, c.a)
		assert_true(is_equal_approx(found, ArtMeshes.SHADOW_ALPHA if kind == K.BLOCK else 0.0), "종류 %d: %f" % [kind, found])


## 반투명은 먼 것부터 그려야 겹칠 때 맞다. MultiMesh 안의 순서가 곧 그리는 순서다
func test_기둥은_먼_것부터_그림() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.warmed:
		await wait_frames()
	main.clear_pieces()
	for z in [-10.0, -30.0, -20.0, -40.0]:  # 일부러 뒤섞어 넣는다
		main._spawn_node({"id": 8200 + int(-z), "lane": 1, "beat": z, "z": z, "kind": K.BLOCK})
	var zs: Array = main._pieces_far_first().map(func(p) -> float: return p.position.z)
	assert_eq(zs, [-40.0, -30.0, -20.0, -10.0])
	main.queue_free()


func test_연속_블록의_뒤쪽만_흐림() -> void:
	var main := _make_main()
	await wait_frames()
	main.clear_pieces()
	main._spawn_node({"id": 8001, "lane": 0, "beat": 1.0, "z": -10.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8002, "lane": 0, "beat": 2.0, "z": -18.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8003, "lane": 2, "beat": 2.0, "z": -18.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8004, "lane": 0, "beat": 3.0, "z": -26.0, "kind": K.LOW})
	assert_eq(main._obstacles[8001].haze, 0.0, "앞 기둥")
	assert_true(main._obstacles[8002].haze > 0.0, "같은 레인 뒤 기둥")
	assert_eq(main._obstacles[8003].haze, 0.0, "다른 레인")
	assert_eq(main._obstacles[8004].haze, 0.0, "기둥이 아님")
	main.queue_free()


## 장애물이 늘어도 그리는 횟수가 늘지 않고, 보통 프레임에는 값을 쓰지 않는다
func test_장애물은_종류별_MultiMesh_하나이고_바뀔_때만_다시_씀() -> void:
	var main := _make_main()
	await wait_frames()
	while not main.warmed:  # 미리 준비용 장애물이 사라질 때까지
		await wait_frames()
	main.clear_pieces()
	for i in 5:
		main._spawn_node({"id": 8100 + i, "lane": i % 3, "beat": float(i), "z": -10.0 - i * 5.0, "kind": K.BLOCK})
	main._sync_pieces()
	assert_eq(main._kind_meshes[K.BLOCK]["body"].visible_instance_count, 5)
	assert_eq(main._kind_meshes[K.BLOCK]["mirror"].visible_instance_count, 5)
	assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 0)
	assert_eq(main._pieces_root.get_child_count(), 2 * main.KINDS.size(), "종류마다 몸통·반사")
	assert_false(main._pieces_dirty, "다 썼음")
	main._scroll += 3.0
	main._sync_pieces()
	assert_eq(main._pieces_root.position.z, main._scroll, "세상이 움직이면 부모만 움직임")
	assert_false(main._pieces_dirty)
	main.queue_free()


func test_대시는_새로_들어온_줄만_다시_씀() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var ladder: MusicLadder = AudioManager.ladder
	main.advance(0.0, ladder.time_of_beat(4.1))
	var before: Array[float] = main._row_beats.duplicate()
	main.advance(0.0, ladder.time_of_beat(4.2))
	assert_eq(main._row_beats, before, "같은 박 안에서는 값이 그대로")
	main.advance(0.0, ladder.time_of_beat(5.1))
	var changed := 0
	for i in BeatRows.COUNT:
		changed += 1 if main._row_beats[i] != before[i] else 0
	assert_eq(changed, 2, "한 박에 두 칸")
	main.queue_free()


func test_프레임이_밀리면_줄기_반사_MSAA_빛_번짐_순서로_낮춤() -> void:
	var main := _make_main()
	await wait_frames()
	var msaa: int = get_viewport().msaa_3d
	var glow: float = main._env.glow_intensity
	main._tint = -1.0
	main._apply_tint(1.0)
	var streaks: int = main._streaks.visible_instance_count
	assert_eq(streaks, 64, "t=1 빛 줄기")
	main.apply_quality(1)
	assert_true(main._streaks.visible_instance_count < streaks, "1단계 줄기")
	assert_true(main.runner._mirror.visible, "반사는 그대로")
	main.apply_quality(2)
	assert_eq(main._kind_meshes[K.BLOCK]["reflect"].get_shader_parameter("reflect_on"), 0.0, "2단계 반사 끔")
	assert_false(main.runner._mirror.visible, "주인공 반사도")
	assert_eq(get_viewport().msaa_3d, msaa, "MSAA는 그대로")
	main.apply_quality(3)
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_2X, "3단계 MSAA 2x")
	assert_eq(main._env.glow_intensity, glow, "빛 번짐은 그대로")
	main.apply_quality(4)
	assert_true(main._env.glow_intensity < glow, "4단계 빛 번짐 낮춤")
	get_viewport().msaa_3d = msaa
	main.queue_free()


func test_반사는_바닥_아래이고_몸통과_빛의_불투명도가_정해진_값() -> void:
	for kind in [K.BLOCK, K.LOW, K.HIGH]:
		var arrays: Array = _meshes(kind)["mirror"].surface_get_arrays(0)
		var alphas := {}
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var a: float = arrays[Mesh.ARRAY_COLOR][i].a
			if a > 0.0 and arrays[Mesh.ARRAY_VERTEX][i].y < 0.0:
				alphas[snappedf(a, 0.01)] = true
		assert_eq(alphas.size(), 2, str(alphas))
		assert_true(alphas.has(snappedf(ArtMeshes.MIRROR_BODY_ALPHA, 0.01)) and alphas.has(snappedf(ArtMeshes.MIRROR_EDGE_ALPHA, 0.01)), str(alphas))


func test_세_종류의_실루엣_높이가_다름() -> void:
	var pillar: AABB = _box(K.BLOCK, ArtMeshes.Part.BODY)
	var low: AABB = _box(K.LOW, ArtMeshes.Part.BODY)
	var high: AABB = _box(K.HIGH, ArtMeshes.Part.BODY)
	assert_true(pillar.end.y > high.end.y + 0.5, "옆 블록이 가장 키가 큼")
	assert_true(low.end.y < high.position.y, "낮은 블록 윗면이 떠 있는 블록 아랫면보다 아래: 아래가 비어 보임")


func test_대시_줄은_템포가_바뀌어도_박에_주인공_자리에_닿음() -> void:
	var ladder := MusicLadder.new(0)
	ladder.add_segment(19.2, 32, 1)
	ladder.add_segment(37.49, 64, 6)
	for beat in [0, 1, 31, 32, 33, 63, 64, 65, 500]:
		var t := ladder.time_of_beat(beat)
		assert_true(absf(BeatRows.row_z(ladder, t, beat)) < 0.000001, "박 %d" % beat)


func test_줄은_반_박_거리마다_하나이고_주인공_앞뒤를_덮으며_간격이_구간_속도를_따름() -> void:
	assert_eq(BeatRows.beat_of(0, 10.3), 9.0)
	assert_eq(BeatRows.beat_of(1, 10.3), 9.5)
	assert_eq(BeatRows.beat_of(4, 10.9), 11.5)
	for step in MusicLadder.STEPS.size():
		var ladder := MusicLadder.new(step)
		var t := 3.0
		var now := ladder.beat_at(t)
		assert_true(BeatRows.row_z(ladder, t, BeatRows.beat_of(0, now)) > 0.0, "주인공 뒤")
		assert_true(BeatRows.row_z(ladder, t, BeatRows.beat_of(BeatRows.COUNT - 1, now)) < -ladder.fog_at(t), "장애물이 사라지는 안개 너머까지")
		var gap := BeatRows.row_z(ladder, t, 5.0) - BeatRows.row_z(ladder, t, 6.0)
		assert_true(is_equal_approx(gap, MusicLadder.beat_distance(step)), "한 박 거리 %f" % gap)


func test_실제_줄_노드가_박에_주인공_자리에_닿음() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var ladder: MusicLadder = AudioManager.ladder
	for beat in [4.0, 7.0, 12.0]:
		main._music_t = ladder.time_of_beat(beat)  # 큰 시간 건너뛰기로 장애물에 부딪히지 않게 줄만 옮긴다
		main._place_rows()
		# 헤드리스 렌더러는 MultiMesh 값을 돌려주지 않으므로 칸에 담긴 박과 부모 위치로 확인한다. 실제 값은 tools/playthrough.gd가 웹에서 잰다
		assert_eq(main._row_beats[BeatRows.slot_of(beat)], beat, "그 박이 들어 있는 칸")
		assert_true(absf(main._dashes.position.z - ladder.distance_of_beat(beat)) < 0.0001, "부모가 그 박의 이동 거리에 있어 z = 0")
	main.queue_free()


func test_박에_바로_밝아지고_0_15초에_돌아옴() -> void:
	assert_eq(BeatRows.pulse(0.0), 0.0)
	assert_eq(BeatRows.pulse(BeatRows.PULSE_TIME), 0.0)
	assert_eq(BeatRows.pulse(0.3), 0.0)
	var peak := 0.0
	for i in 150:
		peak = maxf(peak, BeatRows.pulse(i * 0.001))
	assert_true(absf(peak - 1.0) < 0.001, "최대 %f" % peak)


func test_대시는_박에_밝아지고_멈추면_꺼짐() -> void:
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	main.advance(1.8 + 0.03)  # 3박(1.8초) 0.03초 뒤
	var mat: ShaderMaterial = main._dash_material
	assert_true(mat.get_shader_parameter("pulse") > 0.5, "박 직후 밝음")
	main.advance(0.2)
	assert_eq(mat.get_shader_parameter("pulse"), 0.0, "0.15초 뒤 돌아옴")
	var item := {"id": 7000, "lane": main.lane, "z": 0.0, "kind": K.BLOCK, "beat": 0, "arrive": main.travel}
	main.field.items.append(item)
	main._spawn_node(item)
	main.advance(STEP)
	assert_true(main.dead, "부딪힘")
	assert_eq(mat.get_shader_parameter("pulse"), 0.0)
	assert_eq(mat.get_shader_parameter("sparkle_on"), 0.0, "멈춘 줄이 계속 빛나지 않음")
	var z: float = main._dashes.position.z
	main.advance(STEP)
	assert_true(main._dashes.position.z > z, "느려지는 동안 장애물과 같이 다가옴")
	main.restart()
	assert_eq(main._dashes.position.z, 0.0, "밀린 만큼 되돌림")
	assert_eq(mat.get_shader_parameter("appear"), 0.0, "재시작 때 '퐁'으로 다시 나타남")
	assert_eq(mat.get_shader_parameter("sparkle_on"), 1.0)
	main.queue_free()


func test_대기_화면에서는_줄이_반짝이지_않고_출발하면_반짝임() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	var on: Variant = main._dash_material.get_shader_parameter("sparkle_on")
	assert_true(on == null or on == 0.0, "대기 중 꺼짐")
	main.begin()
	assert_eq(main._dash_material.get_shader_parameter("sparkle_on"), 1.0)
	main.queue_free()


func test_주인공_반사는_모양이_변하는_대로_따라감() -> void:
	var runner := Runner.new()
	add_child(runner)
	await wait_frames()
	var check := func(label: String) -> void:
		assert_eq(runner._mirror.scale, runner._body.scale * Vector3(1, -1, 1), label + " 크기")
		assert_eq(runner._mirror.position, runner._body.position * Vector3(1, -1, 1), label + " 위치")
		for param in ["lean", "sag", "drag", "rim_wave", "flat_bottom"]:
			assert_eq(runner._mirror_mat.get_shader_parameter(param), runner._mat.get_shader_parameter(param), "%s %s" % [label, param])
	assert_eq(runner._mirror.mesh, runner._body.mesh, "같은 메시")
	assert_eq(runner._mirror_mat.get_shader_parameter("mirror_alpha"), Runner.MIRROR_ALPHA)
	assert_true(Runner.MIRROR_ALPHA >= 0.15 and Runner.MIRROR_ALPHA <= 0.25)
	runner.lift = 1.0
	for i in 6:
		runner.step_shape(STEP)
		runner._process(STEP)
	check.call("점프")
	runner.lift = 0.0
	runner.crouch = 1.0
	for i in 6:
		runner.step_shape(STEP)
		runner._process(STEP)
	check.call("슬라이드")
	runner.queue_free()


func test_재시작_뒤_새_모양도_바닥에서_솟음() -> void:
	var main := _make_main()
	await wait_frames()
	main.advance(1.0)
	main.dead = true
	main.restart()
	for item in main.field.items:
		var node = main._obstacles[item["id"]]
		assert_true(node.scale.y < 0.01, "높이 0에서 시작")
		assert_eq(node.position.y, 0.0, "원점이 바닥")
	main.queue_free()


func test_자동_플레이어_시드_5개_3분_충돌_없음_사다리를_끝까지_오름() -> void:
	for seed_value in [11, 143, 2024, 7777, 90001]:
		var ladder := MusicLadder.new(0)
		AudioManager.ladder = ladder
		var main := _make_main(seed_value)
		await wait_frames()
		var t := 0.0
		var last_input := -INF
		while t < 180.0 and not main.dead:
			t += STEP
			ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
			main.advance(STEP, t)
			if main.runner._move_tween and main.runner._move_tween.is_valid():
				main.runner._move_tween.custom_step(STEP)
			var dir := AutoPlayer.decide(RunSim.visible_items(main.field.items, ladder, t), main.lane, main.player, main.speed, t - last_input)
			if dir != SwipeDetector.Dir.NONE:
				main.apply_swipe(dir)
				last_input = t
		assert_false(main.dead, "시드 %d: %.1f초에 충돌" % [seed_value, t])
		assert_true(ladder.segments.size() > MusicLadder.STEPS.size(), "시드 %d: 160을 넘어 오름" % seed_value)
		main.queue_free()
		await wait_frames()
	AudioManager.ladder = MusicLadder.new(0)


## 첫 입력의 음악 시작이 사다리를 새로 만든다. 장애물 목록이 옛 사다리를 보면 경계 뒤 장애물의 도착 거리가 어긋난다.
func test_첫_입력_뒤_장애물은_음악의_사다리로_경계를_넘어_박에_도착() -> void:
	AudioManager.music.stop()
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = 1234
	main.best_path = TEST_BEST
	add_child(main)
	main.set_process(false)
	main.begin()
	assert_eq(main.field.ladder, AudioManager.ladder, "같은 사다리")
	var ladder: MusicLadder = AudioManager.ladder
	var edge := MusicLadder.span_time(0)
	ladder.plan(edge - 6.5, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
	main.field.step(ladder.distance_at(edge - 1.0), ladder.spawn_distance_at(edge - 1.0))
	var crossing: Array = main.field.items.filter(func(item): return item["beat"] > 16.0)
	assert_true(crossing.size() > 0, "경계를 넘는 장애물이 있음")
	for item: Dictionary in crossing:
		assert_true(absf(item["arrive"] - ladder.distance_of_beat(item["beat"])) < 0.000001, "새 속도로 계산한 도착 거리")
		assert_true(item["arrive"] > 16 * 7.2 + (item["beat"] - 16.0) * 7.2, "경계 뒤 한 박은 7.2보다 멂")
	AudioManager.music.stop()
	main.queue_free()


## --- v0.5.0 색 진하기 ---
func _sky_top(main: Node3D) -> Color:
	return main._sky_material.get_shader_parameter("top")


func test_색은_속도를_따라_진해지고_재질을_새로_만들지_않음() -> void:
	var ladder := MusicLadder.new(0)
	AudioManager.ladder = ladder
	var main := _make_main()
	await wait_frames()
	main.field.items.clear()
	var block: ShaderMaterial = main._kind_meshes[K.BLOCK]["block"]
	main.advance(0.0, 1.0)
	assert_eq(main._tint, 0.0)
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")), "t=0 하늘")
	assert_true(block.get_shader_parameter("tint").is_equal_approx(Color("2fb8ff")))
	assert_true(main._env.fog_light_color.is_equal_approx(Color("241650")), "안개 = 지평선")
	assert_eq(_sky_band(main), 0.07, "t=0 안개 띠")
	ladder.add_segment(9.6, 16, 12)
	main.advance(0.0, 9.6 + 60.0 / 160.0 * 4.0)  # 2마디의 절반
	assert_true(absf(main._tint - 0.5) < 0.001, "절반 %f" % main._tint)
	main._music_t = 30.0  # 큰 시간 건너뛰기로 장애물에 부딪히지 않게 색만 계산한다
	main._apply_tint(main._tint_now())
	assert_eq(main._tint, 1.0)
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")), "t=1 하늘")
	assert_true(main._env.fog_light_color.is_equal_approx(Color("3d1880")), "t=1 안개 짙게")
	assert_true(block.get_shader_parameter("tint").is_equal_approx(Color("0faeff")))
	assert_eq(main._kind_meshes[K.BLOCK]["block"], block, "같은 재질")
	assert_eq(_sky_band(main), 0.13, "t=1 안개 띠 넓게")
	assert_true(block.get_shader_parameter("body_color").is_equal_approx(Color("1268b8")), "t=1 기둥 몸통")
	assert_eq(main._streaks.visible_instance_count, 64, "t=1 빛 줄기")
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


func _sky_band(main: Node3D) -> float:
	return main._sky_material.get_shader_parameter("curve")


func test_단계_빛남에도_난간과_대시는_상한을_넘지_않고_끝나면_평소로() -> void:
	var main := _make_main()
	await wait_frames()
	for t in [0.0, 0.5, 1.0]:
		main._tint = -1.0
		main._apply_tint(t)
		main._set_stage_glow(1.0)
		assert_true(main._rail_material.get_shader_parameter("energy") <= StageLight.PEAK_MAX + 0.001, "난간 t=%f" % t)
		var rail: Color = main._rail_material.get_shader_parameter("color")
		var dash_peak: float = maxf(rail.r, maxf(rail.g, rail.b)) * (main._dash_material.get_shader_parameter("max_energy") + main._dash_material.get_shader_parameter("stage_add"))
		assert_true(dash_peak <= StageLight.PEAK_MAX + 0.001, "대시 t=%f" % t)
		main._set_stage_glow(0.0)
		assert_true(is_equal_approx(main._rail_material.get_shader_parameter("energy"), SpeedPalette.at(t)["rail_energy"]), "평소 빛 세기")
		assert_eq(main._dash_material.get_shader_parameter("stage_add"), 0.0, "대시 평소")
	main.queue_free()


func test_재시작하면_색이_0_5초_동안_돌아감() -> void:
	var ladder := MusicLadder.new(12)
	AudioManager.ladder = ladder
	AudioManager.start_step = 12
	var main := _make_main()
	await wait_frames()
	main.advance(0.0, 1.0)
	assert_eq(main._tint, 1.0)
	AudioManager.start_step = 0
	main.dead = true
	main.restart()
	assert_eq(AudioManager.ladder.segments[0]["step"], 0, "100BPM으로")
	var from: float = main._tint
	assert_eq(from, 1.0, "재시작 순간 끊기지 않음")
	var clock: float = main._tint_clock
	var at := func(t: float) -> float:
		main.advance(0.0, clock + t)
		return main._tint
	var mid: float = at.call(0.25)
	assert_true(absf(mid - 0.5) < 0.001, "0.25초 %f" % mid)
	assert_eq(at.call(0.5), 0.0, "0.5초에 t=0")
	assert_eq(main.speed, 15.0, "속도 15")
	assert_true(_sky_top(main).is_equal_approx(Color("05040d")))
	AudioManager.ladder = MusicLadder.new(0)
	main.queue_free()


## 옆 레인에 곧 주인공 위치를 지날 장애물을 놓는다
func _passing(main: Node3D, id: int, kind: K, lane: int, ahead := 0.01) -> Dictionary:
	var item := {"id": id, "lane": lane, "z": -ahead, "kind": kind, "beat": 0, "arrive": main.travel + ahead}
	main.field.items.append(item)
	main._spawn_node(item)
	return item


func test_지나간_장애물은_그대로_뒤로_지나가_z6에서_사라짐() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.warmed:
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var item := _passing(main, 7100, K.LOW, 2)
	while item["z"] <= ObstacleField.REMOVE_Z:
		main.advance(STEP)
		main._sync_pieces()
		if item["z"] <= ObstacleField.REMOVE_Z:
			assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 1, "z %f에서 그대로 보임" % item["z"])
	assert_false(main._obstacles.has(7100), "z +6을 넘으면 사라짐")
	assert_eq(main._kind_meshes[K.LOW]["body"].visible_instance_count, 0, "그리지 않음")
	assert_false(main.dead, "옆 레인이라 부딪히지 않음")
	main.queue_free()


## 판정은 z 0.7까지 그대로다: 지나친 직후 그 범위로 파고들면 원래대로 부딪히고 장애물은 계속 보인다
func test_z0을_지난_직후_판정_범위에서_부딪힘() -> void:
	AudioManager.unblock()
	var main := _make_main()
	while not main.warmed:
		await wait_frames()
	main.field.items.clear()
	main.clear_pieces()
	var side: int = (main.lane + 1) % 3
	var item := _passing(main, 7400, K.BLOCK, side)
	main.advance(STEP)
	assert_false(main.dead, "옆 레인")
	assert_true(item["z"] >= 0.0 and item["z"] < PlayerAction.HIT_Z)
	main.runner.position.x = RunLogic.lane_x(side)
	main.advance(STEP)
	assert_true(main.dead, "v0.6.0과 같이 부딪힘")
	main._sync_pieces()
	assert_eq(main._kind_meshes[K.BLOCK]["body"].visible_instance_count, 1, "장애물이 보임")
	main.queue_free()


## 게임 코드·데이터에 레이저, 부서짐, 칭 소리의 흔적이 남아 있지 않다 (후보 소리는 review/에만 있고 review/는 .gdignore로 빌드에서 빠진다)
func test_레이저_부서짐_칭_소리가_남아_있지_않음() -> void:
	var words := ["laser", "레이저", "shatter", "shard", "부서", "조각", "번쩍", "\"칭"]
	var files: Array[String] = ["res://project.godot", "res://export_presets.cfg"]
	for dir in ["res://scripts", "res://shaders", "res://data", "res://scenes"]:
		_collect(dir, files)
	assert_true(files.size() > 20, "파일을 찾음 %d" % files.size())
	for path in files:
		var text := FileAccess.get_file_as_string(path).to_lower()
		for word: String in words:
			assert_false(text.contains(word), "%s에 %s" % [path, word])
	var sounds: Array[String] = []
	_collect("res://assets/audio", sounds)
	assert_true(sounds.size() > 0)
	for path in sounds:
		assert_false(path.contains("shatter"), path)
	assert_true(FileAccess.file_exists("res://review/.gdignore"), "후보 소리 폴더는 빌드에 들어가지 않음")
	assert_false(AudioManager.has_method("play_shatter"))
	for path in ["res://shaders/laser.gdshader", "res://shaders/shard.gdshader", "res://scripts/logic/shatter.gd"]:
		assert_false(FileAccess.file_exists(path), path)
	var main := _make_main()
	await wait_frames()
	for node: Node in main.find_children("*", "", true, false):
		var low := node.name.to_lower()
		assert_false(low.contains("laser") or low.contains("shard"), node.name)
	main.queue_free()


func _collect(dir: String, into: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir):
		into.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)


## 2칸 벽 (v0.6.3): 같은 줄 이웃 레인의 기둥 둘은 그림 하나, 판정은 둘
func test_이웃_레인_기둥만_벽이_됨() -> void:
	var at := func(lane: int, kind: int, beat := 8.0) -> Dictionary: return {"lane": lane, "kind": kind, "beat": beat}
	assert_true(ObstacleField.forms_wall(at.call(0, K.BLOCK), at.call(1, K.BLOCK)), "왼쪽 + 가운데")
	assert_true(ObstacleField.forms_wall(at.call(2, K.BLOCK), at.call(1, K.BLOCK)), "가운데 + 오른쪽")
	assert_false(ObstacleField.forms_wall(at.call(0, K.BLOCK), at.call(2, K.BLOCK)), "양끝")
	assert_false(ObstacleField.forms_wall(at.call(0, K.BLOCK), at.call(1, K.LOW)), "기둥 + 턱")
	assert_false(ObstacleField.forms_wall(at.call(0, K.BLOCK), at.call(1, K.HIGH)), "기둥 + 막대")
	assert_false(ObstacleField.forms_wall(at.call(0, K.BLOCK), at.call(1, K.BLOCK, 8.5)), "다른 줄")


func _pair(main: Node, lanes: Array, beat := 1.0, z := -20.0) -> void:
	for lane: int in lanes:
		main._spawn_node({"id": 8300 + int(beat) * 10 + lane, "lane": lane, "beat": beat, "z": z, "kind": K.BLOCK})
	main._pieces_dirty = true
	main._sync_pieces()


func test_벽은_한_칸으로_그리고_몸통과_반사에_같은_값을_씀() -> void:
	var main := _make_main()
	await wait_frames()
	main.clear_pieces()
	main._leaving.clear()
	_pair(main, [0, 1])
	var body: MultiMesh = main._kind_meshes[K.BLOCK]["body"]
	var mirror: MultiMesh = main._kind_meshes[K.BLOCK]["mirror"]
	assert_eq(body.visible_instance_count, 1, "벽 하나")
	assert_eq(mirror.visible_instance_count, 1, "반사와 접지 그림자도 하나")
	var wall: Variant = main._obstacles.values().filter(func(p): return not p.hidden)[0]  # 헤드리스는 MultiMesh 값을 돌려주지 않아 조각 상태를 본다
	assert_true(is_equal_approx(wall.position.x, -0.75), "두 레인 가운데")
	assert_eq(wall.wide, 1.0, "벽 표시")
	var half := ObstacleField.BLOCK_SIZE * 0.5 + RunLogic.LANE_WIDTH * 0.5
	assert_true(is_equal_approx(-0.75 - half, RunLogic.lane_x(0) - ObstacleField.BLOCK_SIZE * 0.5), "바깥 왼쪽이 기둥과 같음")
	main.clear_pieces()
	_pair(main, [0, 2])
	assert_eq(body.visible_instance_count, 2, "양끝은 따로")
	for piece in main._obstacles.values():
		assert_eq(piece.wide, 0.0, "양끝은 벽이 아님")
	main.queue_free()


func test_벽_판정은_레인마다_따로이고_값이_그대로() -> void:
	assert_eq(ObstacleField.BLOCK_SIZE, 1.1)
	assert_eq(RunLogic.LANE_WIDTH, 1.5)
	var main := _make_main()
	await wait_frames()
	main.clear_pieces()
	main.field.items.clear()
	for lane: int in [0, 1]:
		var item := {"id": 8400 + lane, "lane": lane, "beat": 1.0, "z": -5.0, "kind": K.BLOCK, "arrive": main.travel + 5.0}
		main.field.items.append(item)
		main._spawn_node(item)
	assert_eq(main.field.items.size(), 2, "판정 항목은 둘")
	assert_eq(main._obstacles.size(), 2, "항목마다 조각이 있어 z가 따라간다")
	main.queue_free()


## 벌리는 셰이더는 x 부호로 양옆을 가른다: 가운데에 꼭짓점이 있으면 이음매가 생긴다
func test_기둥_메시_가운데에_꼭짓점이_없음() -> void:
	var meshes := ArtMeshes.obstacle(K.BLOCK)
	for surface in meshes["body"].get_surface_count():
		for p: Vector3 in meshes["body"].surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			assert_true(absf(p.x) > 0.1, "x %f" % p.x)
			if absf(p.x) <= 0.1:
				return


func test_벽_뒤_기둥도_연속으로_흐리고_다른_레인은_아님() -> void:
	var main := _make_main()
	await wait_frames()
	main.clear_pieces()
	_pair(main, [0, 1], 1.0, -10.0)
	main._spawn_node({"id": 8501, "lane": 1, "beat": 2.0, "z": -18.0, "kind": K.BLOCK})
	main._spawn_node({"id": 8502, "lane": 2, "beat": 2.0, "z": -18.0, "kind": K.BLOCK})
	assert_true(main._obstacles[8501].haze > 0.0, "벽이 덮은 레인")
	assert_eq(main._obstacles[8502].haze, 0.0, "벽이 안 덮은 레인")
	main.queue_free()


func test_시야각은_속도를_2마디_동안_따라_62도에서_68도() -> void:
	var main := _make_main()
	await wait_frames()
	main._apply_tint(0.0)
	assert_eq(main._camera.fov, 62.0)
	main._apply_tint(1.0)
	assert_eq(main._camera.fov, 68.0)
	var ladder := MusicLadder.new()
	ladder.add_segment(MusicLadder.span_time(0), 16, 1)
	var edge := MusicLadder.span_time(0)
	var two_bars := MusicLadder.beat_time(1) * 8.0
	assert_eq(ladder.tint_at(edge), MusicLadder.step_tint(0), "경계 순간에는 튀지 않음")
	assert_true(ladder.tint_at(edge + two_bars * 0.5) > MusicLadder.step_tint(0) and ladder.tint_at(edge + two_bars * 0.5) < MusicLadder.step_tint(1), "서서히")
	assert_eq(ladder.tint_at(edge + two_bars), MusicLadder.step_tint(1), "2마디에 도착")
	main.queue_free()


## 멀리서 툭 나타나지 않게 생성 자리에서는 안개 색이고, 장애물·대시·난간·바닥이 같은 안개 거리를 쓴다
func test_안개는_매_프레임_사다리의_시간_기준_거리이고_생성은_그_너머() -> void:
	var main := _make_main()
	await wait_frames()
	var ladder := MusicLadder.new(MusicLadder.TOP + 20)
	main._apply_fog(ladder, 3.0)
	var far := ladder.fog_at(3.0)
	assert_true(is_equal_approx(far, ladder.speed_at(3.0) * 0.75), "속도 × 보이는 시간 %f" % far)
	assert_true(is_equal_approx(ladder.fog_at(3.0) - ladder.fog_clear_at(3.0), ladder.speed_at(3.0) * 0.15), "0.15초 동안 진해짐")
	var materials: Array = [main._dash_material, main._rail_material]
	for shape: Dictionary in main._kind_meshes.values():
		materials.append(shape["block"])
	for material: ShaderMaterial in materials:
		assert_true(is_equal_approx(material.get_shader_parameter("fog_far"), far), material.shader.resource_path)
		assert_true(is_equal_approx(material.get_shader_parameter("fog_near"), ladder.fog_clear_at(3.0)), material.shader.resource_path)
	assert_true(is_equal_approx(main._floor_material.get_shader_parameter("haze_far"), far), "바닥도 같은 거리에서 안개 색")
	assert_true(ladder.spawn_distance_at(3.0) > far, "생성은 안개 너머")
	for path in ["res://shaders/block.gdshader", "res://shaders/pillar.gdshader", "res://shaders/dash.gdshader", "res://shaders/neon.gdshader"]:
		assert_true(FileAccess.get_file_as_string(path).contains("smoothstep(fog_near, fog_far, -"), "%s: 주인공 기준 월드 거리" % path)
	main.queue_free()


func test_160_뒤에는_대시와_빛_줄기가_속도를_따라_길어지고_시야각은_68도() -> void:
	var main := _make_main()
	await wait_frames()
	main._apply_tint(1.0)
	main._apply_stretch(2.0)
	assert_eq(main._dash_material.get_shader_parameter("dash_length"), main._dash_len * 2.0)
	assert_eq(main._streak_material.get_shader_parameter("streak_length"), main._streak_len * 2.0)
	assert_eq(main._camera.fov, 68.0)
	main.queue_free()


## 속도 33에서도 프레임 사이에 판정을 뚫고 지나가지 않는다: 120Hz 프레임당 0.275, 60Hz 0.55, 판정 폭 1.4
func test_속도_33에서_장애물이_판정을_뚫지_않음() -> void:
	var speed: float = MusicLadder.STEPS[-1]["speed"]
	assert_eq(speed, 33.0)
	for hz: float in [120.0, 60.0, 30.0]:
		var per_frame := speed / hz
		assert_true(per_frame < 2.0 * PlayerAction.HIT_Z, "%dHz 프레임당 %f" % [hz, per_frame])
		for kind in [K.BLOCK, K.LOW, K.HIGH]:
			for offset in 16:  # 프레임이 판정 경계와 어떻게 어긋나든
				var z := -40.0 + per_frame * offset / 16.0
				var hit := false
				while z < ObstacleField.REMOVE_Z and not hit:
					hit = PlayerAction.hits(kind, 0.0, z, 0.0, false)
					z += per_frame
				assert_true(hit, "%dHz 종류 %d 어긋남 %d" % [hz, kind, offset])
