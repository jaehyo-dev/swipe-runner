extends SceneTree
# 고치기 전/후 표: WebKit 흉내 계단·되돌림에서 멈춘 프레임 수와 이동량 흔들림
func _init() -> void:
	var T = load("res://tests/test_beat_clock.gd")
	print("| 화면 | 계단 | 되돌림 | 멈춘 프레임 | 이동량 흔들림 최대 |")
	print("|---|---|---|---|---|")
	for frame in [1.0 / 60.0, 1.0 / 120.0]:
		for stair in [0.010, 0.0213, 0.0427]:
			for back in [false, true]:
				var r: Dictionary = T.webkit_motion(frame, stair, back)
				print("| %dHz | %.1fms | %s | %d | %.1f%% |" % [roundi(1.0 / frame), stair * 1000.0, "20ms" if back else "-", r["stalls"], r["worst"] * 100.0])
	quit()
