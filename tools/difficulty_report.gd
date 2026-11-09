extends SceneTree
## 사람 모델 두 종류의 난이도 표: 시드 50개로 버틴 시간 분포, 죽은 BPM, 부딪힌 장애물 종류, 기둥 비율. 결과는 표준 출력(markdown).
##   godot --headless --path . -s tools/difficulty_report.gd

const SEEDS := 50
const LIMIT := 600.0
## -s 스크립트는 오토로드(AudioManager)보다 먼저 컴파일되므로 그것에 기대는 클래스를 이름으로 부르지 않고 실행 중에 불러온다
var sim: GDScript
var human: GDScript


func _initialize() -> void:
	process_frame.connect(_report, CONNECT_ONE_SHOT)  # 오토로드가 준비된 뒤에 시작한다


func _report() -> void:
	sim = load("res://tests/run_sim.gd")
	human = load("res://tests/human_player.gd")
	_model("보통 모델", human.NORMAL)
	_model("잘하는 모델", human.GOOD)
	_block_share()
	var perfect := []
	for s in [11, 143, 2024, 7777, 90001]:
		var r: Dictionary = sim.run(s, "perfect", 240.0, MusicLadder.STEPS.size() - 1)
		perfect.append("%d: %s (최소 입력 간격 %.2f초)" % [s, "충돌 0" if r["hit"].is_empty() else "%.1f초에 충돌" % r["time"], r["min_gap"]])
	print("\n완벽한 자동 플레이어 160BPM 4분: " + ", ".join(perfect))
	quit()


func _model(title: String, model: Dictionary) -> void:
	var results := []
	for s in range(1, SEEDS + 1):
		results.append(sim.run(s, human.new(s, model), LIMIT))
	var times: Array = results.map(func(r): return r["time"])
	times.sort()
	var bar := func(q: float) -> float: return times[int(q * (times.size() - 1))]
	print("\n## %s\n" % title)
	print("| 시드 | 25%% | 중앙값 | 75%% | 95%% | 최소 | 최대 |\n|---|---|---|---|---|---|---|")
	print("| %d | %.1f초 | %.1f초 | %.1f초 | %.1f초 | %.1f초 | %.1f초 |" % [SEEDS, bar.call(0.25), bar.call(0.5), bar.call(0.75), bar.call(0.95), times[0], times[-1]])
	var by_bpm := {}
	var by_kind := {"BLOCK": 0, "LOW": 0, "HIGH": 0}
	var by_level := {}  # 160BPM 뒤 밀도 칸
	var alive := 0
	for r in results:
		if r["hit"].is_empty():
			alive += 1
			continue
		var bpm: int = MusicLadder.STEPS[r["step"]]["bpm"]
		by_bpm[bpm] = by_bpm.get(bpm, 0) + 1
		by_kind[ObstacleField.Kind.keys()[r["hit"]["kind"]]] += 1
		if bpm == MusicLadder.STEPS[-1]["bpm"]:
			var level: int = BeatPattern.new(1, 0).density(r["hit"]["beat"])
			by_level[level] = by_level.get(level, 0) + 1
	print("\n| 죽은 BPM | 판 수 |\n|---|---|")
	var top := 0
	for step in MusicLadder.STEPS:
		print("| %d | %d |" % [step["bpm"], by_bpm.get(step["bpm"], 0)])
		top = maxi(top, by_bpm.get(step["bpm"], 0))
	print("\n한 BPM에 가장 많이 몰린 사망: %d판 (%.0f%%), %d초 생존 %d판" % [top, 100.0 * top / maxi(SEEDS - alive, 1), int(LIMIT), alive])
	var levels := []
	var top_level := 0
	for level in range(BeatPattern.DENSITY_MAX + 1):
		levels.append("%d칸 %d판" % [level, by_level.get(level, 0)])
		top_level = maxi(top_level, by_level.get(level, 0))
	print("\n160BPM 안의 밀도 칸별 사망: %s. 밀도 칸을 난이도 한 칸으로 치면 가장 많이 몰린 곳 %.0f%%" % [", ".join(levels), 100.0 * top_level / maxi(SEEDS - alive, 1)])
	print("\n| 장애물 | 판 수 |\n|---|---|")
	print("| 기둥 | %d |\n| 턱 | %d |\n| 막대 | %d |" % [by_kind["BLOCK"], by_kind["LOW"], by_kind["HIGH"]])
	# 중앙값에 가까운 시드 (mp4 기록용)
	var mid: float = bar.call(0.5)
	var near := 1
	for i in results.size():
		if absf(results[i]["time"] - mid) < absf(results[near - 1]["time"] - mid):
			near = i + 1
	print("\n중앙값에 가까운 시드: %d (%.1f초)" % [near, results[near - 1]["time"]])


func _block_share() -> void:
	print("\n## 패턴 구성 (시드 %d개, 150마디씩)\n" % SEEDS)
	var count := [0, 0, 0]
	for s in range(1, SEEDS + 1):
		var pattern := BeatPattern.new(s, ObstacleField.FIRST_BEAT)
		while pattern.beat < 600.0:
			var item := pattern.next()
			count[item["kind"]] += 1
	var total: int = count[0] + count[1] + count[2]
	print("| 기둥 | 턱 | 막대 |\n|---|---|---|\n| %.1f%% | %.1f%% | %.1f%% |" % [100.0 * count[0] / total, 100.0 * count[1] / total, 100.0 * count[2] / total])
