extends SceneTree
## v0.11.1: 배점이 0.5배가 되어 고비(140BPM)는 5000점이 아니라 박(약 66초)에 온다. "고비 시점 점수" 열: 고비 박에 닿은 판의 그때 점수(중앙·최소~최대).
## 점수 분포 표 (v0.10.1 점수 목표): 사람 모델(보통·잘함·욕심쟁이) 시드 50개의 최종 점수 구간 비율, 5000점 도달 시점의 속도·압박·보이는 시간,
## 생존 곡선(0~12000점, 500점마다 "이 점수에 도달한 판 비율"). 결과는 표준 출력(markdown) + 곡선 CSV(인자로 경로를 주면)
##   godot --headless --path . -s tools/score_report.gd -- [곡선.csv]
## 모델 값을 바꿔 보려면 환경 변수 MODELS='{"보통": {"delay": 0.2}}' (기존 모델 값 위에 덮어쓴다. 사용자 실제 기록에 맞춰 다시 맞출 때)

const SEEDS := 50
const LIMIT := 900.0
const WALL := 5000        # 고비 점수
const CURVE_TOP := 12000
const CURVE_STEP := 500
var sim: GDScript
var human: GDScript


func _initialize() -> void:
	process_frame.connect(_report, CONNECT_ONE_SHOT)  # 오토로드가 준비된 뒤에 시작한다


func _report() -> void:
	sim = load("res://tests/run_sim.gd")  # 오토로드에 기대는 클래스는 실행 중에 불러온다
	human = load("res://tests/human_player.gd")
	var models := {"보통": human.NORMAL.duplicate(), "잘함": human.GOOD.duplicate(), "욕심쟁이": human.GREEDY.duplicate()}
	var over: Variant = JSON.parse_string(OS.get_environment("MODELS")) if OS.has_environment("MODELS") else null
	if over is Dictionary:
		for title in over:
			models[title].merge(over[title], true)
	var curves := {}
	var scores := {}
	var wall_beat: float = MusicLadder.wall()["step"] * MusicLadder.STEP_BEATS
	print("| 모델 | 중앙값 | 5000 도달 | 5000~8000 사망 | 5000~7000 사망 | 8000 이상 | 10000 이상 | 5000 도달 시각(중앙) | 그때 단계·BPM·속도·압박·보이는 시간 | 고비(박 %d) 도달 | 고비 시점 점수 중앙 (최소~최대) |" % wall_beat)
	print("|---|---|---|---|---|---|---|---|---|---|---|")
	for title in models:
		var finals: Array[int] = []
		var walls: Array = []
		var at_wall: Array[int] = []
		for s in range(1, SEEDS + 1):
			var trace := []
			var r: Dictionary = sim.run(s, human.new(s, models[title]), LIMIT, 0, trace)
			finals.append(r["score"])
			for row in trace:
				if row[3] >= wall_beat:
					at_wall.append(row[1])
					break
			for row in trace:
				if row[1] >= WALL:
					walls.append(row)
					break
		finals.sort()
		scores[title] = finals
		var share := func(lo: int, hi: int) -> float: return 100.0 * finals.filter(func(v: int) -> bool: return v >= lo and v < hi).size() / SEEDS
		walls.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var wall_text := "-"
		var at_text := "-"
		if not walls.is_empty():
			var w: Array = walls[walls.size() / 2]
			var info := MusicLadder.info(w[2])
			wall_text = "%.0f초" % w[0]
			at_text = "%d · %dBPM · %.1f · %d · %.2f초" % [w[2], info["bpm"], info["speed"], BeatPattern.pressure(w[3]), MusicLadder.visible_time(w[2])]
		at_wall.sort()
		var wall_score := "%d (%d~%d)" % [at_wall[at_wall.size() / 2], at_wall[0], at_wall[-1]] if not at_wall.is_empty() else "-"
		print("| %s | %d | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %s | %s | %.0f%% | %s |" % [title, finals[SEEDS / 2], share.call(WALL, 1 << 30), share.call(WALL, 8000), share.call(WALL, 7000), share.call(8000, 1 << 30), share.call(10000, 1 << 30), wall_text, at_text, 100.0 * at_wall.size() / SEEDS, wall_score])
		var curve := []
		for p in range(0, CURVE_TOP + 1, CURVE_STEP):
			curve.append(100.0 * finals.filter(func(v: int) -> bool: return v >= p).size() / SEEDS)
		curves[title] = curve
	print("\n욕심쟁이 중앙값 / 잘함 중앙값 = %.2f" % (float(scores["욕심쟁이"][SEEDS / 2]) / scores["잘함"][SEEDS / 2]))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		file.store_line("score," + ",".join(curves.keys()))
		for i in curves["보통"].size():
			file.store_line("%d,%s" % [i * CURVE_STEP, ",".join(curves.keys().map(func(k): return "%.0f" % curves[k][i]))])
		file.close()
	quit()
