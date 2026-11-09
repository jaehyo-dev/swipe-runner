extends TestCase
## 장애물 생성·이동·제거 규칙 테스트 (시드 고정). 도착 박에서 거꾸로 계산해 생성한다.

const Kind := ObstacleField.Kind


func _run_for(field: ObstacleField, seconds: float, dt: float = 0.1) -> Dictionary:
	var spawned := 0
	var removed: Array[int] = []
	for i in int(seconds / dt):
		var r := field.step(field.travel + RunLogic.SPEED * dt)
		spawned += r["spawned"].size()
		removed.append_array(r["removed"])
	return {"spawned": spawned, "removed": removed}


func test_첫_입력에_음악_0초면_첫_장애물은_2_4초에_도착() -> void:
	assert_eq(ObstacleField.new(1).step(0.0)["spawned"][0]["beat"], 4.0)


func test_미리_놓기는_도착_박에서_거꾸로_계산하고_z_60보다_가까운_것만() -> void:
	var field := ObstacleField.new(1)
	var placed: Array = field.step(RunLogic.SPEED)["spawned"]
	assert_true(placed.size() >= 2, "여러 개 %d" % placed.size())
	for item in placed:
		assert_true(absf(item["z"] + RunLogic.SPEED * (item["beat"] * 0.6 - 1.0)) < 0.001, "z %f" % item["z"])
		assert_true(item["z"] >= ObstacleField.SPAWN_Z and item["z"] < 0.0, "z %f" % item["z"])
	assert_eq(field.step(field.travel)["spawned"].size(), 0, "두 번 놓지 않음")
	# 그 뒤부터는 기존 방식: 다음 것이 z -60에서 생긴다
	var next: Array = []
	while next.is_empty():
		next = field.step(field.travel + RunLogic.SPEED * 0.01)["spawned"]
	assert_true(absf(next[0]["z"] - ObstacleField.SPAWN_Z) < RunLogic.SPEED * 0.011, "z %f" % next[0]["z"])


func test_미리_놓은_배치는_같은_시드의_패턴과_같아서_공정성_규칙을_지킴() -> void:
	var field := ObstacleField.new(77)
	var pattern := BeatPattern.new(77, ObstacleField.FIRST_BEAT)
	for item in field.step(0.0)["spawned"]:
		var want := pattern.next()
		assert_eq([item["beat"], item["lane"], item["kind"]], [want["beat"], want["lane"], want["kind"]])


func test_장애물은_정확히_자기_박에_z_0에_도착함() -> void:
	var field := ObstacleField.new(9)
	var t := 0.0
	var dt := 1.0 / 60.0
	var checked := 0
	for frame in 60 * 60:
		var before := field.items.duplicate()
		field.step(field.travel + RunLogic.SPEED * dt)
		t += dt
		for item in before:
			if item in field.items and item["z"] >= 0.0 and item["z"] - RunLogic.SPEED * dt < 0.0:
				var crossed: float = t - item["z"] / RunLogic.SPEED
				assert_true(absf(crossed - item["beat"] * 0.6) < 0.000001, "박 %d: %f" % [item["beat"], crossed])
				checked += 1
	assert_true(checked > 40, "확인한 수 %d" % checked)


func test_일정_속도로_다가옴() -> void:
	var field := ObstacleField.new(1)
	field.step(field.travel + RunLogic.SPEED)
	var z: float = field.items[0]["z"]
	field.step(field.travel + RunLogic.SPEED * 0.5)
	assert_true(absf(field.items[0]["z"] - (z + RunLogic.SPEED * 0.5)) < 0.000001)


func test_지나가면_제거되고_목록에서_빠짐() -> void:
	var field := ObstacleField.new(1)
	var id: int = field.step(field.travel + RunLogic.SPEED)["spawned"][0]["id"]
	var left: float = (ObstacleField.REMOVE_Z - field.items[0]["z"]) / RunLogic.SPEED
	field.step(field.travel + RunLogic.SPEED * (left - 0.05))
	assert_true(field.items.any(func(i): return i["id"] == id), "아직 지나가기 전")
	var r := field.step(field.travel + RunLogic.SPEED * 0.1)
	assert_true(r["removed"].has(id), "지나간 장애물 제거")
	assert_false(field.items.any(func(i): return i["id"] == id), "목록에서도 빠짐")


func test_오래_달려도_장애물이_쌓이지_않음() -> void:
	var field := ObstacleField.new(7)
	var result := _run_for(field, 120.0)
	var rows := ceili((ObstacleField.REMOVE_Z - ObstacleField.SPAWN_Z) / MusicLadder.beat_distance(0)) + 1
	var max_alive := rows * 3  # 한 줄에 최대 3개 (벽)
	assert_true(field.items.size() <= max_alive, "살아 있는 수 %d" % field.items.size())
	assert_eq(result["spawned"] - result["removed"].size(), field.items.size(), "생긴 수 - 지워진 수 = 남은 수")


func test_시간이_크게_건너뛰어도_이미_지나간_장애물은_만들지_않음() -> void:
	var field := ObstacleField.new(1)
	assert_eq(field.step(RunLogic.SPEED * 600.0)["spawned"].filter(func(i): return i["z"] > ObstacleField.REMOVE_Z), [], "지나간 것 없음")
	assert_true(field.items.size() < 40, "살아 있는 수 %d" % field.items.size())


func test_같은_시드면_같은_배치_세_레인_세_종류가_모두_나옴() -> void:
	var a := ObstacleField.new(42)
	var b := ObstacleField.new(42)
	var lanes := {}
	var kinds := {}
	for i in 240:
		var sa: Array = a.step(a.travel + RunLogic.SPEED * 0.25)["spawned"]
		var sb: Array = b.step(b.travel + RunLogic.SPEED * 0.25)["spawned"]
		assert_eq(sa.map(func(x): return [x["beat"], x["lane"], x["kind"]]), sb.map(func(x): return [x["beat"], x["lane"], x["kind"]]))
		for item in sa:
			assert_true(item["lane"] >= 0 and item["lane"] <= 2, "레인 %d" % item["lane"])
			lanes[item["lane"]] = true
			kinds[item["kind"]] = true
	assert_eq(lanes.size(), 3)
	assert_eq(kinds.size(), 3)
