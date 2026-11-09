extends SceneTree
## 밝기 순서 표를 마크다운으로 찍는다 (ART_BIBLE.md 4장). 자동 테스트와 같은 계산, 순서가 깨지면 종료 코드 1.
##   godot --headless --path . -s tools/brightness_report.gd

const HERO_PEAK := 2.4  # jelly.gdshader rim_energy × #C8FFFA의 가장 센 채널


func _init() -> void:
	print("| t | 주인공 | 기호(가장 어두운 종류) | 테두리(가장 밝은 종류) | 기둥 몸통 면 | 난간(단계 빛남 최대) | 평소 난간 | 빛 줄기 | 바닥·하늘(가장 밝은 곳) | 순서 |")
	print("|---|---|---|---|---|---|---|---|---|---|")
	var ok := true
	for t in [0.0, 0.5, 1.0]:
		var r := BrightnessOrder.table(t, HERO_PEAK)
		var good: bool = r["hero"] > r["mark"] and r["mark"] > r["edge"] and r["edge"] > r["rail"] and r["rail_rest"] > r["streak"] and r["streak"] > r["ground"]
		ok = ok and good
		print("| %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %s |" % [t, r["hero"], r["mark"], r["edge"], r["pillar_body"], r["rail"], r["rail_rest"], r["streak"], r["ground"], "통과" if good else "실패"])
	quit(0 if ok else 1)
