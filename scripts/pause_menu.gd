class_name PauseMenu
extends Control
## 일시정지 화면: 게임 위를 어둡게 덮고 "PAUSED", RESUME / HOME / SETTINGS.
## RESUME을 누르면 3 → 2 → 1을 박에 맞춰 보인 뒤 resumed를 보낸다 (숫자 동안 게임은 멈춰 있어 판정이 없다).
## 트리가 일시정지여도 움직인다 (process_mode ALWAYS). 누름은 여기서 자리로 판단한다.

signal resume_pressed   # 숫자 세기를 시작해 달라 (main이 박 길이를 넘겨 count를 부른다)
signal resumed          # 숫자가 끝났다: 음악과 게임을 다시 움직인다
signal home_pressed
signal settings_pressed

const DIM := Color(0.02, 0.016, 0.051, 0.72)   # 무대 바탕색(BOOT_COLOR)으로 어둡게
const COUNT_DIM := 0.35                          # 숫자 동안은 옅게: 다시 달릴 길이 보인다
const TITLE_TOP := 400.0
const BUTTON_TOP := 660.0
const BUTTON_GAP := 100.0
const COUNT_SIZE := 220
const COUNT_POP := 1.25
const STUCK_TIME := 1.0  # 오디오 시계가 이만큼 늦게까지 서 있으면 숫자를 끝낸다 (소리 없이도 게임은 이어진다)

var dim: ColorRect
var title: Label
var buttons := {}     # "RESUME"/"HOME"/"SETTINGS" -> Label
var count_label: Label
var counting := false
## 설정이 위에 열려 있으면 누름을 받지 않는다 (main이 정한다)
var blocked := false

var _count: PauseCountdown
var _count_start := 0.0   # 숫자 세기 시작 (AudioManager.clock 기준)
var _wall_start := 0       # 실제 시간 시작: 오디오 시계가 서 있으면(브라우저가 소리를 재움) 이것으로 끝낸다
var _digit := 0


func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	dim = ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	title = TitleScreen.text_label("PausedLabel", "PAUSED", 120, TitleScreen.TITLE_COLOR)
	title.label_settings.shadow_color = TitleScreen.TITLE_GLOW
	title.label_settings.shadow_size = 14
	title.label_settings.shadow_offset = Vector2.ZERO
	title.offset_top = TITLE_TOP
	add_child(title)
	var y := BUTTON_TOP
	for pair in [["RESUME", 56, Color.WHITE], ["HOME", 44, Color(1, 1, 1, 0.7)], ["SETTINGS", 44, Color(1, 1, 1, 0.7)]]:
		var button := TitleScreen.text_label(pair[0].capitalize() + "Button", pair[0], pair[1], pair[2])
		button.offset_top = y
		button.offset_bottom = y + BUTTON_GAP * 0.8
		button.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(button)
		buttons[pair[0]] = button
		y += BUTTON_GAP
	count_label = TitleScreen.text_label("CountLabel", "", COUNT_SIZE, TitleScreen.TITLE_COLOR)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	count_label.offset_left = -200.0
	count_label.offset_right = 200.0
	count_label.offset_top = -COUNT_SIZE * 0.8
	count_label.offset_bottom = COUNT_SIZE * 0.8
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.label_settings.shadow_color = TitleScreen.TITLE_GLOW
	count_label.label_settings.shadow_size = 18
	count_label.label_settings.shadow_offset = Vector2.ZERO
	add_child(count_label)


## 일시정지 화면을 보인다 (숫자 세는 중이었으면 멈춘다)
func open() -> void:
	counting = false
	dim.color = DIM
	title.visible = true
	for b: Label in buttons.values():
		b.visible = true
	count_label.visible = false
	visible = true


## 3·2·1 숫자를 세기 시작한다. 다 세면 resumed. start: 오디오 시계로 센 시작 시각 (숫자 끝 = 음악이 다시 들리는 순간)
func count(countdown: PauseCountdown, start: float) -> void:
	_count = countdown
	_count_start = start
	_wall_start = Time.get_ticks_usec()
	_digit = 0
	counting = true
	dim.color = Color(DIM, COUNT_DIM)
	title.visible = false
	for b: Label in buttons.values():
		b.visible = false
	count_label.visible = true
	_process(0.0)


func _process(_delta: float) -> void:
	if not (visible and counting):
		return
	var elapsed := AudioManager.clock() - _count_start
	if _count.done(elapsed) or (Time.get_ticks_usec() - _wall_start) / 1000000.0 > _count.resume_at() + STUCK_TIME:
		counting = false
		count_label.visible = false
		resumed.emit()
		return
	var digit := _count.digit(elapsed)
	if digit != _digit:  # 박마다 숫자가 톡 커졌다 돌아온다
		_digit = digit
		count_label.text = str(digit)
		count_label.pivot_offset = count_label.size * 0.5
		count_label.scale = Vector2.ONE * COUNT_POP
		var pop := create_tween()
		pop.tween_property(count_label, "scale", Vector2.ONE, minf(_count.beat * 0.5, 0.2)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if not visible or blocked:
		return
	get_viewport().set_input_as_handled()  # 일시정지 뒤의 게임은 누름을 받지 않는다
	if counting:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_P, KEY_ENTER, KEY_SPACE]:
		resume_pressed.emit()
	elif event is InputEventScreenTouch and event.pressed:
		tap(event.position)


## 화면 자리를 누름 (테스트에서도 부른다). 글자 줄 전체가 누르는 자리
func tap(point: Vector2) -> void:
	for key: String in buttons:
		var b: Label = buttons[key]
		var rect := b.get_global_rect()
		rect.position.x = rect.position.x + rect.size.x * 0.5 - 220.0  # 화면 가운데 440px 폭
		rect.size.x = 440.0
		if b.is_visible_in_tree() and rect.has_point(point):
			match key:
				"RESUME": resume_pressed.emit()
				"HOME": home_pressed.emit()
				"SETTINGS": settings_pressed.emit()
			return
