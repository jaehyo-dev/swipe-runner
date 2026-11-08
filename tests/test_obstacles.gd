extends TestCase
## 장애물 생성·이동·제거 규칙 테스트 (시드 고정). 도착 박에서 거꾸로 계산해 생성한다.

const Kind := ObstacleField.Kind


func _run_for(field: ObstacleField, seconds: float, dt: float = 0.1) -> Dictionary:
	var spawned := 0
	var removed: Array[int] = []
	for i in int(seconds / dt):
		var r := field.step(dt)
		spawned += r["spawned"].size()
		removed.append_array(r["removed"])
	return {"spawned": spawned, "removed": removed}


func test_첫_장애물은_마디_첫_박_도착에_맞춰_멀리서_생김() -> void:
	var field := ObstacleField.new(1)
	var first_arrival := 3 * BeatClock.BAR  # 6.67초 이상 지난 첫 마디 첫 박 = 7.2초
	assert_eq(field.step(first_arrival - ObstacleField.TRAVEL - 0.01)["spawned"].size(), 0, "아직")
	var r := field.step(0.01)
	assert_eq(r["spawned"].size(), 1)
	assert_true(absf(r["spawned"][0]["z"] - ObstacleField.SPAWN_Z) < 0.001, "z %f" % r["spawned"][0]["z"])
	assert_eq(r["spawned"][0]["beat"], 12)


func test_장애물은_정확히_자기_박에_z_0에_도착함() -> void:
	var field := ObstacleField.new(9)
	var t := 0.0
	var dt := 1.0 / 60.0
	var checked := 0
	for frame in 60 * 60:
		var before := field.items.duplicate()
		field.step(dt)
		t += dt
		for item in before:
			if item in field.items and item["z"] >= 0.0 and item["z"] - RunLogic.SPEED * dt < 0.0:
				var crossed: float = t - item["z"] / RunLogic.SPEED
				assert_true(absf(crossed - item["beat"] * BeatClock.BEAT) < 0.000001, "박 %d: %f" % [item["beat"], crossed])
				checked += 1
	assert_true(checked > 40, "확인한 수 %d" % checked)


func test_일정_속도로_다가옴() -> void:
	var field := ObstacleField.new(1)
	field.step(1.0)
	var z: float = field.items[0]["z"]
	field.step(0.5)
	assert_true(absf(field.items[0]["z"] - (z + RunLogic.SPEED * 0.5)) < 0.000001)


func test_지나가면_제거되고_목록에서_빠짐() -> void:
	var field := ObstacleField.new(1)
	var id: int = field.step(1.0)["spawned"][0]["id"]
	var left: float = (ObstacleField.REMOVE_Z - field.items[0]["z"]) / RunLogic.SPEED
	field.step(left - 0.05)
	assert_true(field.items.any(func(i): return i["id"] == id), "아직 지나가기 전")
	var r := field.step(0.1)
	assert_true(r["removed"].has(id), "지나간 장애물 제거")
	assert_false(field.items.any(func(i): return i["id"] == id), "목록에서도 빠짐")


func test_오래_달려도_장애물이_쌓이지_않음() -> void:
	var field := ObstacleField.new(7)
	var result := _run_for(field, 120.0)
	var max_alive := ceili((ObstacleField.REMOVE_Z - ObstacleField.SPAWN_Z) / RunLogic.SPEED / BeatClock.BEAT) + 1
	assert_true(field.items.size() <= max_alive, "살아 있는 수 %d" % field.items.size())
	assert_eq(result["spawned"] - result["removed"].size(), field.items.size(), "생긴 수 - 지워진 수 = 남은 수")


func test_시간이_크게_건너뛰어도_이미_지나간_장애물은_만들지_않음() -> void:
	var field := ObstacleField.new(1)
	assert_eq(field.step(600.0)["spawned"].filter(func(i): return i["z"] > ObstacleField.REMOVE_Z), [], "지나간 것 없음")
	assert_true(field.items.size() < 40, "살아 있는 수 %d" % field.items.size())


func test_같은_시드면_같은_배치_세_레인_세_종류가_모두_나옴() -> void:
	var a := ObstacleField.new(42)
	var b := ObstacleField.new(42)
	var lanes := {}
	var kinds := {}
	for i in 240:
		var sa: Array = a.step(0.25)["spawned"]
		var sb: Array = b.step(0.25)["spawned"]
		assert_eq(sa.map(func(x): return [x["beat"], x["lane"], x["kind"]]), sb.map(func(x): return [x["beat"], x["lane"], x["kind"]]))
		for item in sa:
			assert_true(item["lane"] >= 0 and item["lane"] <= 2, "레인 %d" % item["lane"])
			lanes[item["lane"]] = true
			kinds[item["kind"]] = true
	assert_eq(lanes.size(), 3)
	assert_eq(kinds.size(), 3)
