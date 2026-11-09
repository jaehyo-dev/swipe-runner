extends Node
## 압박 단계 0 / 4 / 8 / 12 장면 (웹 빌드에 들어가지 않음). 저장소 뿌리에 복사해 실행한다.
##   godot --path . --resolution 720x1280 res://pressure_shots.tscn -- <결과 폴더>
## 사다리를 그 박까지 올린 뒤(속도·보이는 시간·안개가 그 시점 값) 장애물을 그 자리에 놓고 한 장씩 찍는다. 긴 녹화 없이 찍는다.

const SEED := 143
var _main: Node3D
var _out: String


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.seed_value = SEED
	_main.best_path = "user://pressure_shots_best.txt"
	add_child(_main)
	while not _main.prewarmed:
		await get_tree().process_frame
	_main.set_process(false)  # 음악이 꺼져 있어 스스로 시간을 돌리지 않게
	var lines := []
	for p: int in [0, 4, 8, 12]:
		var ladder := MusicLadder.new()
		var beat: float = 32.0 * p + 20.0  # 압박 단계 안 20박째 (숨 고르기 마디 전)
		var t := 0.0
		while ladder.segments[-1]["beat"] <= beat:
			t += 1.0 / 30.0
			ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
		t = ladder.time_of_beat(beat) + 0.3 * MusicLadder.beat_time(ladder._segment_of_beat(beat)["step"])
		for tries in 20:  # 주인공 자리에 장애물이 겹친 순간이면 조금 옮긴다
			AudioManager.ladder = ladder
			_main.clear_pieces()
			_main.dead = false
			_main.field = ObstacleField.new(SEED, ladder)
			_main.started = true
			_main.advance(0.0, t)
			if not _main.dead:
				break
			t += 0.05
		var step: int = ladder.segment_at(t)["step"]
		lines.append("압박 %d: 박 %.1f, %.1f초, %dBPM, 속도 %.1f, 보이는 시간 %.2f초, 안개 거리 %.1f, 장애물 %d개" % [p, ladder.beat_at(t), t, MusicLadder.info(step)["bpm"], ladder.speed_at(t), MusicLadder.visible_time(step), ladder.fog_at(t), _main.field.items.size()])
		await _shot("pressure_%02d" % p)
	FileAccess.open("%s/pressure_shots.txt" % _out, FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	get_tree().quit()


func _shot(name_: String) -> void:
	_main._sync_pieces()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])
