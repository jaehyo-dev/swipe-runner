extends TestCase
## 레이저 번쩍임과 조각 계산 (화면 없이).

const K := ObstacleField.Kind


func test_마디_첫_박은_크게_다른_박은_살짝_번쩍이고_곧_사라짐() -> void:
	var beat_time := 0.6
	assert_eq(StageLight.beat_flash(4.0, beat_time), StageLight.BAR_BOOST, "마디 첫 박")
	assert_eq(StageLight.beat_flash(5.0, beat_time), StageLight.BEAT_BOOST, "다른 박")
	assert_true(StageLight.BAR_BOOST > StageLight.BEAT_BOOST)
	assert_eq(StageLight.beat_flash(4.5, beat_time), 0.0, "다음 박 전에 사라짐")
	assert_eq(StageLight.beat_flash(-0.5, beat_time), 0.0, "시작 전")


func test_어떤_번쩍임에도_상한을_넘지_않음() -> void:
	for color_peak in [0.5, 0.77, 1.0]:
		for base in [0.5, 0.85]:
			assert_true(StageLight.energy(base, StageLight.BAR_BOOST, 1.0, color_peak) * color_peak <= StageLight.PEAK_MAX + 0.0001)
	assert_eq(StageLight.energy(0.5, 0.0, 0.0, 0.77), 0.5, "평소 그대로")


func test_조각은_8에서_14개이고_같은_시드면_같음() -> void:
	var counts := {}
	for seed_value in 200:
		for kind in K.values():
			var shards := Shatter.burst(kind, seed_value, 12.0)
			assert_true(shards.size() >= Shatter.COUNT_MIN and shards.size() <= Shatter.COUNT_MAX, str(shards.size()))
			counts[shards.size()] = true
	assert_eq(counts.size(), Shatter.COUNT_MAX - Shatter.COUNT_MIN + 1, "범위 전체가 나옴")
	assert_eq(Shatter.burst(K.LOW, 7, 12.0), Shatter.burst(K.LOW, 7, 12.0))


func test_조각은_앞면에서_나와_바깥과_뒤로_흩어짐() -> void:
	for kind in K.values():
		var area := Shatter.face(kind)
		for shard in Shatter.burst(kind, 11, 20.0):
			var from: Vector3 = shard["from"]
			assert_true(absf(from.x - area["center"].x) <= area["half"].x + 0.001 and absf(from.y - area["center"].y) <= area["half"].y + 0.001, "면 안")
			var at := Shatter.position_at(shard, Shatter.LIFE)
			assert_true(at.z > from.z + 2.0, "뒤로")
			var out := Vector2(from.x - area["center"].x, from.y - area["center"].y)
			assert_true(Vector2(shard["velocity"].x, shard["velocity"].y).dot(out) >= 0.0, "바깥으로")


func test_기호_자리_조각이_있고_0_35초에_사라짐() -> void:
	var marks := 0
	for shard in Shatter.burst(K.HIGH, 3, 12.0):
		marks += 1 if shard["mark"] else 0
	assert_true(marks >= 1)
	assert_eq(Shatter.fade(0.0), 1.0)
	assert_eq(Shatter.fade(Shatter.LIFE), 0.0)
	assert_true(Shatter.LIFE <= 0.35)
