extends TestCase
## 장애물 생성·이동·제거 규칙 테스트 (시드 고정).


func _run_for(field: ObstacleField, seconds: float, dt: float = 0.1) -> Dictionary:
	var spawned := 0
	var removed: Array[int] = []
	for i in int(seconds / dt):
		var r := field.step(dt)
		spawned += r["spawned"].size()
		removed.append_array(r["removed"])
	return {"spawned": spawned, "removed": removed}


func test_첫_장애물은_멀리서_생김() -> void:
	var field := ObstacleField.new(1)
	var r := field.step(0.0)
	assert_eq(r["spawned"].size(), 1)
	assert_eq(r["spawned"][0]["z"], ObstacleField.SPAWN_Z)


func test_일정_속도로_다가옴() -> void:
	var field := ObstacleField.new(1)
	field.step(0.0)
	field.step(0.5)
	assert_eq(field.items[0]["z"], ObstacleField.SPAWN_Z + RunLogic.SPEED * 0.5)


func test_지나가면_제거되고_목록에서_빠짐() -> void:
	var field := ObstacleField.new(1)
	field.step(0.0)
	var travel := (ObstacleField.REMOVE_Z - ObstacleField.SPAWN_Z) / RunLogic.SPEED
	field.step(travel - 0.05)
	assert_true(field.items.any(func(i): return i["id"] == 0), "아직 지나가기 전")
	var r := field.step(0.1)
	assert_true(r["removed"].has(0), "지나간 장애물 제거")
	assert_false(field.items.any(func(i): return i["id"] == 0), "목록에서도 빠짐")


func test_오래_달려도_장애물이_쌓이지_않음() -> void:
	var field := ObstacleField.new(7)
	var result := _run_for(field, 120.0)
	var max_alive := ceili((ObstacleField.REMOVE_Z - ObstacleField.SPAWN_Z) / RunLogic.SPEED / ObstacleField.SPAWN_INTERVAL) + 1
	assert_true(field.items.size() <= max_alive, "살아 있는 수 %d" % field.items.size())
	assert_eq(result["spawned"] - result["removed"].size(), field.items.size(), "생긴 수 - 지워진 수 = 남은 수")


func test_레인은_0에서_2_사이이고_세_레인이_모두_나옴() -> void:
	var field := ObstacleField.new(3)
	var seen := {}
	for i in 600:
		for item in field.step(0.1)["spawned"]:
			assert_true(item["lane"] >= 0 and item["lane"] <= 2, "레인 %d" % item["lane"])
			seen[item["lane"]] = true
	assert_eq(seen.size(), 3)


func test_같은_시드면_같은_레인_순서() -> void:
	var a := ObstacleField.new(42)
	var b := ObstacleField.new(42)
	for i in 100:
		var sa: Array = a.step(0.25)["spawned"]
		var sb: Array = b.step(0.25)["spawned"]
		assert_eq(sa.map(func(x): return x["lane"]), sb.map(func(x): return x["lane"]))


func test_큰_시간_조각이_들어와도_생성_간격을_지킴() -> void:
	var field := ObstacleField.new(1)
	var r := field.step(3.0)  # 처음 1개 + 3초치 3개
	assert_eq(r["spawned"].size(), 4)
