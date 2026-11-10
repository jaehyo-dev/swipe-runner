extends SceneTree
## 사람 모델(보통·잘함·욕심쟁이·도전)의 난이도 표: 시드 50개로 버틴 시간 분포, 사망 시점의 속도·보이는 시간·압박 단계·패턴 종류. 결과는 표준 출력(markdown).
##   godot --headless --path . -s tools/difficulty_report.gd
## 끝에 완벽한 자동 플레이어(지연 0, 입력 간격 0.22초)가 처음부터 10분을 달린 결과를 붙인다.

const SEEDS := 50
const LIMIT := 600.0
const PERFECT_SEEDS := [11, 143, 2024, 7777, 90001]
## -s 스크립트는 오토로드(AudioManager)보다 먼저 컴파일되므로 그것에 기대는 클래스를 이름으로 부르지 않고 실행 중에 불러온다
var sim: GDScript
var human: GDScript


func _initialize() -> void:
	process_frame.connect(_report, CONNECT_ONE_SHOT)  # 오토로드가 준비된 뒤에 시작한다


func _report() -> void:
	sim = load("res://tests/run_sim.gd")
	human = load("res://tests/human_player.gd")
	_model("보통 모델", human.NORMAL)
	var safe := _model("잘하는 모델 (= 안전 모델, 방울 무시)", human.GOOD)
	var greedy := _model("욕심쟁이 모델 (잘하는 모델 + 방울 쫓기)", human.GREEDY)
	var dare := _model("도전 모델 (잘하는 모델 + 점프·슬라이드를 늦게)", human.DARE)
	_compare({"안전": safe, "욕심쟁이": greedy, "도전": dare})
	_kind_share()
	print("\n## 완벽한 자동 플레이어 (처음부터 10분)\n")
	for s in PERFECT_SEEDS:
		var r: Dictionary = sim.run(s, "perfect", LIMIT)
		var speed: float = MusicLadder.info(r["step"])["speed"]
		print("- 시드 %d: %s, 끝 속도 %.0f, 최소 입력 간격 %.2f초" % [s, "충돌 0" if r["hit"].is_empty() else "%.1f초에 충돌 %s" % [r["time"], str(r["hit"])], speed, r["min_gap"]])
	quit()


func _count(table: Dictionary, key: Variant) -> void:
	table[key] = table.get(key, 0) + 1


func _table(title: String, table: Dictionary, deaths: int) -> int:
	var keys := table.keys()
	keys.sort()
	print("\n| %s | 판 수 |\n|---|---|" % title)
	var top := 0
	for key in keys:
		print("| %s | %d |" % [str(key), table[key]])
		top = maxi(top, table[key])
	print("가장 많이 몰린 곳 %.0f%%" % (100.0 * top / maxi(deaths, 1)))
	return top


## 모델들의 버틴 시간·점수·방울·PERFECT 비교표
func _compare(models: Dictionary) -> void:
	print("\n## 안전·욕심쟁이·도전 모델 (시드 %d개, 중앙값. PERFECT/판은 평균)\n" % SEEDS)
	print("| 모델 | 버틴 시간 | 점수 | 거리 | 먹은 방울 비율 | PERFECT/판 | 25% 점수 | 75% 점수 |\n|---|---|---|---|---|---|---|---|")
	for title in models:
		var rs: Array = models[title]
		var mid := func(key: String, q := 0.5) -> float:
			var v: Array = rs.map(func(r): return float(r[key]))
			v.sort()
			return v[int(q * (v.size() - 1))]
		var orbs: float = rs.reduce(func(a, r): return a + r["orbs"], 0)
		var seen: float = rs.reduce(func(a, r): return a + r["orbs_seen"], 0)
		var close: float = rs.reduce(func(a, r): return a + r["close"], 0)
		print("| %s | %.1f초 | %d | %dm | %.0f%% | %.1f | %d | %d |" % [title, mid.call("time"), mid.call("score"), mid.call("distance"), 100.0 * orbs / maxf(seen, 1.0), close / rs.size(), mid.call("score", 0.25), mid.call("score", 0.75)])


func _model(title: String, model: Dictionary) -> Array:
	var results := []
	for s in range(1, SEEDS + 1):
		results.append(sim.run(s, human.new(s, model), LIMIT))
	var times: Array = results.map(func(r): return r["time"])
	times.sort()
	var bar := func(q: float) -> float: return times[int(q * (times.size() - 1))]
	print("\n## %s\n" % title)
	print("| 시드 | 25% | 중앙값 | 75% | 95% | 최소 | 최대 |\n|---|---|---|---|---|---|---|")
	print("| %d | %.1f초 | %.1f초 | %.1f초 | %.1f초 | %.1f초 | %.1f초 |" % [SEEDS, bar.call(0.25), bar.call(0.5), bar.call(0.75), bar.call(0.95), times[0], times[-1]])
	var by_speed := {}
	var by_visible := {}
	var by_pressure := {}
	var by_shape := {}
	var by_kind := {}
	var deaths := 0
	for r in results:
		if r["hit"].is_empty():
			continue
		deaths += 1
		var info := MusicLadder.info(r["step"])
		_count(by_speed, "%03d~" % (int(info["speed"]) / 10 * 10))
		_count(by_visible, "%.2f초" % MusicLadder.visible_time(r["step"]))
		_count(by_pressure, "%02d" % BeatPattern.pressure(r["hit"]["beat"]))
		_count(by_shape, r["hit"]["shape"])
		_count(by_kind, ObstacleField.Kind.keys()[r["hit"]["kind"]])
	print("\n%d초 생존 %d판" % [int(LIMIT), SEEDS - deaths])
	_table("사망 속도", by_speed, deaths)
	_table("사망 때 보이는 시간", by_visible, deaths)
	_table("사망 압박 단계", by_pressure, deaths)
	_table("부딪힌 패턴", by_shape, deaths)
	_table("부딪힌 장애물", by_kind, deaths)
	# 중앙값에 가까운 시드 (mp4 기록용)
	var mid: float = bar.call(0.5)
	var near := 1
	for i in results.size():
		if absf(results[i]["time"] - mid) < absf(results[near - 1]["time"] - mid):
			near = i + 1
	print("\n중앙값에 가까운 시드: %d (%.1f초)" % [near, results[near - 1]["time"]])
	return results


func _kind_share() -> void:
	print("\n## 패턴 구성 (시드 %d개, 150마디씩)\n" % SEEDS)
	var count := [0, 0, 0]
	for s in range(1, SEEDS + 1):
		var pattern := BeatPattern.new(s, ObstacleField.FIRST_BEAT)
		while pattern.beat < 600.0:
			var item := pattern.next()
			count[item["kind"]] += 1
	var total: int = count[0] + count[1] + count[2]
	print("| 기둥 | 턱 | 막대 |\n|---|---|---|\n| %.1f%% | %.1f%% | %.1f%% |" % [100.0 * count[0] / total, 100.0 * count[1] / total, 100.0 * count[2] / total])
