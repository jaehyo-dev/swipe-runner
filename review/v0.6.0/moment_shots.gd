extends Node
## 같은 시드, 같은 순간을 찍는다 (웹 빌드에 들어가지 않음). 두 버전의 폴더에 복사해 실행해 전후를 비교한다.
##   godot --path <프로젝트> --resolution 720x1280 res://moment_shots.tscn -- <결과 폴더>
## 사다리를 한 단계에 고정하고 자동 플레이어로 달린 뒤 찍는다. 음악 없이 시간만 흐르므로 v0.5.1과 v0.6.0의 장면이 같다.

const STEP := 1.0 / 60.0
const SEED := 143
const AT := 9.0


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AudioServer.set_bus_mute(0, true)
	for bpm in [100, 160]:
		await _shot(bpm, "%s/moment_%d.png" % [out, bpm])
	get_tree().quit()


func _shot(bpm: int, path: String) -> void:
	var ladder := MusicLadder.new(MusicLadder.step_of_bpm(bpm))
	AudioManager.start_step = MusicLadder.step_of_bpm(bpm)
	AudioManager.ladder = ladder
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.seed_value = SEED
	main.best_path = "user://moment_best.txt"
	add_child(main)
	main.set_process(false)
	while not main.prewarmed:
		await get_tree().process_frame
	main.started = true
	var t := 0.0
	var last_input := -INF
	while t < AT:
		t += STEP
		main.advance(STEP, t)
		main._sync_pieces()
		if main.runner._move_tween and main.runner._move_tween.is_valid():
			main.runner._move_tween.custom_step(STEP)
		var dir := AutoPlayer.decide(main.field.items, main.lane, main.player, main.speed, t - last_input)
		if dir != SwipeDetector.Dir.NONE:
			main.apply_swipe(dir)
			last_input = t
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	main.queue_free()
	await get_tree().process_frame
