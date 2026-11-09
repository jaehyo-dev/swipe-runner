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
	return MusicLadder.info(MusicLadder.scheduled_step(start_step, beat))["bpm"]


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


## v0.7.0: 겹줄·콤보·섞인 동작이 모두 기둥 벽을 바탕으로 해 기둥 비율 상한을 45%에서 70%로 올렸다
func test_겹줄은_기둥만이_아니라_섞여서_나오고_기둥_비율은_70퍼센트_이하() -> void:
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
	assert_true(float(blocks) / total <= 0.7, "기둥 비율 %f" % (float(blocks) / total))


func test_지그재그는_반_박이_입력_간격_0_22초_이상인_BPM만이고_빠르면_1박_콤보() -> void:
	assert_true(BeatPattern.can_zigzag(100) and BeatPattern.can_zigzag(135))
	assert_false(BeatPattern.can_zigzag(140))
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
	assert_true(fast_combos.size() >= 4, "여러 BPM에서 3연속 이상 콤보: %s" % str(fast_combos))


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


## 압박 단계는 음악 처음부터 센다 (?bpm으로 시작한 판도 0부터)
func test_압박_단계는_8마디마다_1씩_상한_없이_오름() -> void:
	assert_eq(BeatPattern.pressure(0.0), 0)
	assert_eq(BeatPattern.pressure(31.9), 0)
	assert_eq(BeatPattern.pressure(32.0), 1, "8마디")
	assert_eq(BeatPattern.pressure(32.0 * 100), 100, "상한 없음")
	var top: int = MusicLadder.TOP * MusicLadder.STEP_BEATS
	assert_eq(_bpm_of(top + 1000.0), 160, "160 뒤 BPM은 그대로")


func test_콤보는_2줄에서_4줄까지_길어지고_확률은_상한에서_멈춤() -> void:
	var every: int = MusicLadder.data()["combo_every"]
	assert_eq(BeatPattern.combo_length(0), 2)
	assert_eq(BeatPattern.combo_length(every), 3)
	assert_eq(BeatPattern.combo_length(every * 2), 4)
	assert_eq(BeatPattern.combo_length(1000), 4)
	for name: String in MusicLadder.data()["pattern"]:
		var r: Array = MusicLadder.data()["pattern"][name]
		assert_eq(BeatPattern.rate(name, 2, 100000), r[2], name + " 상한")
		assert_true(BeatPattern.rate(name, 0, 3) >= BeatPattern.rate(name, 0, 0), name + " 오름")


func test_숨_고르기_마디는_8마디에_한_마디_기둥_하나씩_2박_간격이고_다른_패턴이_넘어오지_않음() -> void:
	var breathers := 0
	for bar in 64:
		breathers += 1 if BeatPattern.is_breather(bar * 4.0) else 0
	assert_eq(breathers, 8)
	for s in range(1, 21):
		var rows := _rows(s, 500.0)
		for beat: float in rows:
			if BeatPattern.is_breather(beat):
				assert_eq(rows[beat][0]["shape"], "숨 고르기", "시드 %d 박 %f: 앞 마디의 여러 줄 패턴이 넘어오지 않음" % [s, beat])
				assert_eq(rows[beat].size(), 1, "기둥 하나")
				assert_false(rows.has(beat + 1.0) and BeatPattern.is_breather(beat + 1.0), "시드 %d 박 %f: 1박 뒤 줄 없음" % [s, beat])
	assert_eq(BeatPattern.beats_to_breather(0.0), 28.0, "7번째 마디(0부터)")
	assert_eq(BeatPattern.beats_to_breather(27.5), 0.5)
	assert_true(BeatPattern.beats_to_breather(29.0) < 0.0, "숨 고르기 마디 안")


func test_섞인_동작_콤보와_겹줄과_긴_콤보가_나옴() -> void:
	var shapes := {}
	var long_combo := false
	for s in range(1, 21):
		var rows := _rows(s, 800.0)
		for beat: float in rows:
			shapes[rows[beat][0]["shape"]] = true
			if rows[beat][0]["shape"] == "1박 콤보" and rows.has(beat + 3.0) and rows[beat + 3.0][0]["shape"] == "1박 콤보" and rows.has(beat + 1.0) and rows.has(beat + 2.0):
				long_combo = true
	for want in ["섞인 동작", "겹줄", "1박 콤보", "반 박 이동", "줄 읽기", "숨 고르기"]:
		assert_true(shapes.has(want), want)
	assert_true(long_combo, "4줄 콤보")


func test_줄_읽기는_열린_줄이_보이는_시간_안에_들어올_때만() -> void:
	assert_true(BeatPattern.can_read(2, 0))
	assert_false(BeatPattern.can_read(4, MusicLadder.TOP), "160에서 깊은 줄 읽기는 안 보임")
	assert_false(BeatPattern.can_read(2, MusicLadder.TOP + 12), "보이는 시간 최소에서는 얕은 것도 없음")


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


## 보이는 줄만 보고 사람 입력 간격(0.22초)만 쓰는 완벽한 자동 플레이어가 부딪히지 않으면 풀 수 없는 패턴이 없다는 증거다.
## 처음부터 10분이면 속도 117, 압박 단계 40 안팎까지 간다. 시드 5개는 tools/difficulty_report.gd가 돌린다.
func test_완벽한_자동_플레이어가_처음부터_10분_충돌_없음() -> void:
	for s in [11, 2024]:
		var result := RunSim.run(s, "perfect", 600.0)
		assert_true(result["hit"].is_empty(), "시드 %d: %.1f초에 충돌 %s" % [s, result["time"], str(result["hit"])])
		assert_true(result["min_gap"] >= BeatPattern.MIN_INPUT_GAP - 0.001, "입력 간격 %f" % result["min_gap"])
		assert_true(MusicLadder.info(result["step"])["speed"] > 100.0, "속도 상한 없음")


func test_완벽한_자동_플레이어가_처음부터_끝까지_올라감() -> void:
	for s in [11, 143, 2024, 7777, 90001]:
		var result := RunSim.run(s, "perfect", 240.0)
		assert_true(result["hit"].is_empty(), "시드 %d: %.1f초에 충돌" % [s, result["time"]])
		assert_true(result["ladder"].segments[-1]["step"] > MusicLadder.TOP, "160 넘어 오름")


func test_모든_시작_BPM과_더_많은_시드에서_풀림() -> void:
	for s in range(1, 7):
		for start in MusicLadder.STEPS.size():
			var result := RunSim.run(s, "perfect", 70.0, start)
			assert_true(result["hit"].is_empty(), "시드 %d 시작 %d: %.1f초 %s" % [s, MusicLadder.info(start)["bpm"], result["time"], str(result["hit"])])


func _runs(model: Dictionary) -> Array:
	var runs := []
	for s in range(1, 51):
		runs.append(RunSim.run(s, HumanPlayer.new(s, model), 400.0))
	return runs


func _times(runs: Array) -> Array:
	var times: Array = runs.map(func(r): return r["time"])
	times.sort()
	return times


## 사망이 한 패턴 종류에 절반 넘게 몰리지 않는다
func _assert_mixed(runs: Array) -> void:
	var by_shape := {}
	for r: Dictionary in runs:
		if not r["hit"].is_empty():
			by_shape[r["hit"]["shape"]] = by_shape.get(r["hit"]["shape"], 0) + 1
	assert_true(by_shape.size() >= 4, "사망 패턴 %s" % str(by_shape))
	assert_true(by_shape.values().max() <= 25, "쏠림 %s" % str(by_shape))


func test_보통_모델은_중앙값_25에서_40초() -> void:
	var runs := _runs(HumanPlayer.NORMAL)
	var median: float = _times(runs)[24]
	assert_true(median >= 25.0 and median <= 40.0, "중앙값 %f" % median)
	_assert_mixed(runs)


func test_잘하는_모델은_중앙값_50에서_80초_95퍼센트_150초_최대_240초() -> void:
	var runs := _runs(HumanPlayer.GOOD)
	var times := _times(runs)
	assert_true(times[24] >= 50.0 and times[24] <= 80.0, "중앙값 %f" % times[24])
	assert_true(times[47] <= 150.0, "95%% %f" % times[47])
	assert_true(times[49] <= 240.0, "최대 %f" % times[49])
	_assert_mixed(runs)


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
