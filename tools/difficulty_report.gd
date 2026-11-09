extends SceneTree
## 사람 모델 난이도 표: 시드 50개로 버틴 시간 분포, 죽은 단계, 부딪힌 장애물 종류. 결과는 표준 출력(markdown).
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
	var results := []
	for s in range(1, SEEDS + 1):
		results.append(sim.run(s, human.new(s), LIMIT))
	var times: Array = results.map(func(r): return r["time"])
	times.sort()
	var bar := func(q: float) -> float: return times[int(q * (times.size() - 1))]
	print("| 시드 | 25% | 중앙값 | 75% | 최소 | 최대 |\n|---|---|---|---|---|---|")
	print("| %d | %.1f초 | %.1f초 | %.1f초 | %.1f초 | %.1f초 |" % [SEEDS, bar.call(0.25), bar.call(0.5), bar.call(0.75), times[0], times[-1]])
	var stage_name := ["1단계 원본", "2단계 A", "3단계 B"]
	var by_stage := [0, 0, 0]
	var by_bpm := {}
	var by_kind := {"BLOCK": 0, "LOW": 0, "HIGH": 0}
	var alive := 0
	for r in results:
		if r["hit"].is_empty():
			alive += 1
			continue
		var step: Dictionary = MusicLadder.STEPS[r["step"]]
		by_stage[step["stage"]] += 1
		by_bpm[step["bpm"]] = by_bpm.get(step["bpm"], 0) + 1
		by_kind[ObstacleField.Kind.keys()[r["hit"]["kind"]]] += 1
	print("\n| 죽은 단계 | 판 수 |\n|---|---|")
	for i in 3:
		print("| %s | %d |" % [stage_name[i], by_stage[i]])
	print("| %d초 생존 | %d |" % [int(LIMIT), alive])
	print("\n| 죽은 BPM | 판 수 |\n|---|---|")
	for step in MusicLadder.STEPS:
		print("| %d | %d |" % [step["bpm"], by_bpm.get(step["bpm"], 0)])
	print("\n| 장애물 | 판 수 |\n|---|---|")
	print("| 기둥 | %d |\n| 턱 | %d |\n| 막대 | %d |" % [by_kind["BLOCK"], by_kind["LOW"], by_kind["HIGH"]])
	# 중앙값에 가까운 시드 (mp4 기록용)
	var mid: float = bar.call(0.5)
	var near := 1
	for i in results.size():
		if absf(results[i]["time"] - mid) < absf(results[near - 1]["time"] - mid):
			near = i + 1
	print("\n중앙값에 가까운 시드: %d (%.1f초)" % [near, results[near - 1]["time"]])
	var perfect := []
	for s in [11, 143, 2024, 7777, 90001]:
		var r: Dictionary = sim.run(s, "perfect", 240.0)
		perfect.append("%d: %s (최소 입력 간격 %.2f초)" % [s, "충돌 0" if r["hit"].is_empty() else "%.1f초에 충돌" % r["time"], r["min_gap"]])
	print("\n완벽한 자동 플레이어 4분: " + ", ".join(perfect))
	quit()
