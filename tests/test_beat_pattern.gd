extends TestCase
## 박자 패턴과 공정성 테스트 (시드 고정).

const Kind := ObstacleField.Kind
const SEEDS := [1, 7, 42, 136, 2026]


## 박 → 그 박의 장애물들. start_step부터 사다리가 오르는 순서 그대로
func _rows(seed_value: int, last_beat: float, start_step := 0) -> Dictionary:
	var pattern := BeatPattern.new(seed_value, ObstacleField.FIRST_BEAT, start_step)
	var rows := {}
	while true:
		var item := pattern.next()
		if item["beat"] > last_beat:
			return rows
		if not rows.has(item["beat"]):
			rows[item["beat"]] = []
		rows[item["beat"]].append(item)
	return rows


func _is_big(item: Dictionary) -> bool:
	return item["kind"] != Kind.BLOCK


func _big_of(row: Array) -> bool:
	return row.any(_is_big)


func _bpm_of(beat: float, start_step := 0) -> int:
	return MusicLadder.STEPS[MusicLadder.scheduled_step(start_step, beat)]["bpm"]


func _sorted_beats(rows: Dictionary) -> Array:
	var beats: Array = rows.keys()
	beats.sort()
	return beats


func test_처음_8마디부터_1박_간격이_섞이고_첫_장애물은_1마디_뒤() -> void:
	var ones := 0
	for s in SEEDS:
		var rows := _rows(s, 36.0)
		var beats := _sorted_beats(rows)
		assert_eq(beats[0], float(ObstacleField.FIRST_BEAT), "첫 장애물")
		for i in range(1, beats.size()):
			ones += 1 if beats[i] - beats[i - 1] == 1.0 else 0
	assert_true(ones >= SEEDS.size(), "1박 간격 %d" % ones)


func test_겹줄은_기둥만이_아니라_섞여서_나오고_기둥_비율은_45퍼센트_이하() -> void:
	var pairs := {}
	var blocks := 0
	var total := 0
	for s in range(1, 41):
		var rows := _rows(s, 600.0)
		for beat in rows:
			var kinds: Array = rows[beat].map(func(item): return item["kind"])
			kinds.sort()
			pairs[str(kinds)] = true
			blocks += kinds.count(Kind.BLOCK)
			total += kinds.size()
	for want in [[Kind.BLOCK, Kind.LOW], [Kind.BLOCK, Kind.HIGH], [Kind.LOW, Kind.HIGH], [Kind.BLOCK, Kind.LOW, Kind.HIGH]]:
		assert_true(pairs.has(str(want)), "조합 %s" % str(want))
	assert_true(float(blocks) / total <= 0.45, "기둥 비율 %f" % (float(blocks) / total))


func test_지그재그는_반_박이_입력_간격_이상인_BPM만이고_빠르면_3연속_콤보() -> void:
	assert_true(BeatPattern.can_zigzag(100) and BeatPattern.can_zigzag(105))
	assert_false(BeatPattern.can_zigzag(110))
	var zigzags := {}
	var combos := {}
	for s in range(1, 61):
		for start in [0, 2, 8]:
			var rows := _rows(s, 300.0, start)
			var beats := _sorted_beats(rows)
			for i in range(1, beats.size()):
				var both_forced: bool = rows[beats[i]].size() == 2 and rows[beats[i - 1]].size() == 2
				if beats[i] - beats[i - 1] == 0.5 and both_forced:
					var a: Array = rows[beats[i - 1]].map(func(item): return item["lane"])
					var b: Array = rows[beats[i]].map(func(item): return item["lane"])
					a.sort()
					b.sort()
					if a != b and rows[beats[i - 1]].all(func(item): return item["lane"] != 1 or item["kind"] == Kind.BLOCK) and _is_zigzag(rows[beats[i - 1]], rows[beats[i]]):
						var bpm := _bpm_of(beats[i], start)
						assert_true(BeatPattern.can_zigzag(bpm), "%dBPM 지그재그" % bpm)
						zigzags[bpm] = true
				if i >= 2 and beats[i] - beats[i - 1] == 1.0 and beats[i - 1] - beats[i - 2] == 1.0:
					if rows[beats[i]].size() == 2 and rows[beats[i - 1]].size() == 2 and rows[beats[i - 2]].size() == 2:
						if _open_lane(rows[beats[i]]) != _open_lane(rows[beats[i - 1]]) and _open_lane(rows[beats[i - 1]]) != _open_lane(rows[beats[i - 2]]):
							combos[_bpm_of(beats[i], start)] = true
	assert_true(zigzags.has(100) or zigzags.has(105), "지그재그가 나옴")
	var fast_combos := combos.keys().filter(func(bpm): return not BeatPattern.can_zigzag(bpm))
	assert_true(fast_combos.size() >= 6, "여러 BPM에서 3연속 콤보: %s" % str(fast_combos))


func _open_lane(row: Array) -> int:
	var open := 3
	for item in row:
		open -= item["lane"]
	return open


## 줄 읽기의 벽은 가운데 기둥 한 개씩이고, 지그재그는 두 레인을 막은 줄 두 개다
func _is_zigzag(first: Array, second: Array) -> bool:
	return first.all(func(item): return item["kind"] == Kind.BLOCK) and second.all(func(item): return item["kind"] == Kind.BLOCK) and _open_lane(first) != _open_lane(second)


func test_반_박_간격은_입력이_필요_없는_가운데_벽과_지그재그뿐() -> void:
	for s in range(1, 41):
		for start in [0, 4, 12]:
			var rows := _rows(s, 400.0, start)
			var beats := _sorted_beats(rows)
			for i in range(1, beats.size()):
				if beats[i] - beats[i - 1] >= 1.0:
					continue
				var bpm := _bpm_of(beats[i], start)
				if BeatPattern.can_zigzag(bpm) and rows[beats[i]].size() == 2 and rows[beats[i - 1]].size() == 2:
					continue
				var middle_before: bool = rows[beats[i - 1]].size() == 1 and rows[beats[i - 1]][0]["lane"] == 1 and rows[beats[i - 1]][0]["kind"] == Kind.BLOCK
				assert_true(middle_before, "시드 %d 박 %f: 반 박 앞 줄은 가운데 벽" % [s, beats[i]])


func test_160BPM_뒤에는_밀도만_오르고_상한이_있음() -> void:
	var pattern := BeatPattern.new(1, 4)
	var top: int = (MusicLadder.STEPS.size() - 1) * MusicLadder.STEP_BEATS
	assert_eq(pattern.density(top - 1.0), 0, "160 전")
	assert_eq(pattern.density(top), 0, "도착")
	assert_eq(pattern.density(top + MusicLadder.STEP_BEATS), 1, "4마디 뒤")
	assert_eq(pattern.density(top + 1000.0 * MusicLadder.STEP_BEATS), BeatPattern.DENSITY_MAX, "상한")
	assert_eq(MusicLadder.scheduled_step(0, top + 1000.0), MusicLadder.STEPS.size() - 1, "BPM은 그대로")


## 공정성 규칙: 모든 시드, 끝까지
func test_열린_레인이_항상_있고_점프_슬라이드_줄끼리는_2박_이상_벌어짐() -> void:
	for s in range(1, 41):
		for start in [0, 2, 4, 6, 12]:
			var rows := _rows(s, 500.0, start)
			var last_big := -INF
			var beats := _sorted_beats(rows)
			for beat: float in beats:
				var used := {}
				var blocked := 0
				for item: Dictionary in rows[beat]:
					assert_false(used.has(item["lane"]), "한 레인에 둘")
					used[item["lane"]] = true
					blocked += 1 if item["kind"] == Kind.BLOCK else 0
				assert_true(blocked < RunLogic.LANE_COUNT, "박 %f 세 레인이 모두 막힘" % beat)
				if _big_of(rows[beat]):
					assert_true(beat - last_big >= BeatPattern.GAP_AFTER_BIG, "시드 %d 박 %f 앞 동작 %f" % [s, beat, last_big])
					last_big = beat


## 사람 입력 간격(0.28초)만 쓰는 완벽한 자동 플레이어가 부딪히지 않으면 풀 수 없는 패턴이 없다는 증거다.
func test_완벽한_자동_플레이어가_160BPM에서_시드_5개_4분_충돌_없음() -> void:
	for s in [11, 143, 2024, 7777, 90001]:
		var result := RunSim.run(s, "perfect", 240.0, MusicLadder.STEPS.size() - 1)
		assert_true(result["hit"].is_empty(), "시드 %d: %.1f초에 충돌" % [s, result["time"]])
		assert_true(result["min_gap"] >= 0.28 - 0.001, "입력 간격 %f" % result["min_gap"])


func test_완벽한_자동_플레이어가_처음부터_끝까지_올라감() -> void:
	for s in [11, 143, 2024, 7777, 90001]:
		var result := RunSim.run(s, "perfect", 240.0)
		assert_true(result["hit"].is_empty(), "시드 %d: %.1f초에 충돌" % [s, result["time"]])
		assert_eq(result["ladder"].segments[-1]["step"], MusicLadder.STEPS.size() - 1, "160까지 오름")


func test_모든_시작_BPM과_더_많은_시드에서_풀림() -> void:
	for s in range(1, 7):
		for start in MusicLadder.STEPS.size():
			var result := RunSim.run(s, "perfect", 70.0, start)
			assert_true(result["hit"].is_empty(), "시드 %d 시작 %d: %.1f초 %s" % [s, MusicLadder.STEPS[start]["bpm"], result["time"], str(result["hit"])])


func _median(model: Dictionary) -> float:
	var times := []
	for s in range(1, 51):
		times.append(RunSim.run(s, HumanPlayer.new(s, model), 600.0)["time"])
	times.sort()
	return times[24]


func test_보통_모델은_중앙값_35에서_60초() -> void:
	var median := _median(HumanPlayer.NORMAL)
	assert_true(median >= 35.0 and median <= 60.0, "중앙값 %f" % median)


func test_잘하는_모델은_중앙값_90에서_150초() -> void:
	var median := _median(HumanPlayer.GOOD)
	assert_true(median >= 90.0 and median <= 150.0, "중앙값 %f" % median)


func test_늦어서_길이_없어도_열린_레인을_돌려줌() -> void:
	var rows := [{"beat": 8.0, "eta": 0.05, "lanes": {0: Kind.BLOCK, 1: Kind.BLOCK}}]
	assert_eq(AutoPlayer.best_path(rows, 0), [2] as Array[int], "한 칸 안에 길이 없어도 멈추지 않음")
	assert_eq(AutoPlayer.best_path(rows, 2), [2] as Array[int], "이미 열린 레인이면 그대로")


func test_사람_모델은_반응_지연을_지킴() -> void:
	var human := HumanPlayer.new(5)
	var delays := []
	for i in 2000:
		delays.append(human._delay())
	var late := delays.filter(func(d): return d > 0.33 + 0.0001).size()
	for d: float in delays:
		assert_true(d >= 0.17 and d <= 0.48 + 0.0001, "지연 %f" % d)
	assert_true(late >= 2 and late <= 60, "1%% 안팎으로 늦음: %d" % late)
	var seeded := HumanPlayer.new(5)
	assert_eq(seeded._delay(), delays[0], "시드 고정")


## 160BPM에서도 동작 사이 2박이 동작 시간보다 길어야 연달아 피할 수 있다.
func test_160BPM의_2박이_점프와_슬라이드보다_김() -> void:
	var two_beats := MusicLadder.beat_time(MusicLadder.STEPS.size() - 1) * BeatPattern.GAP_AFTER_BIG
	assert_true(absf(two_beats - 0.75) < 0.001)
	assert_true(two_beats > PlayerAction.SLIDE_TIME and two_beats > PlayerAction.JUMP_TIME)


func test_잘하는_모델은_반응이_빠르고_더_멀리_봄() -> void:
	assert_true(HumanPlayer.GOOD["delay"] < HumanPlayer.NORMAL["delay"])
	assert_eq(HumanPlayer.NORMAL["look"], 2)
	assert_eq(HumanPlayer.GOOD["look"], 4)
