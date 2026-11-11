class_name SettingsPanel
extends Control
## 설정 (메인 화면 톱니, 일시정지의 SETTINGS): 화면 가운데 반투명 패널.
## MUSIC·SFX 크기 슬라이더, VIBRATION 켜기/끄기(지원하지 않는 기기는 숨김), SHOW GUIDE(다음 3판 안내), DONE.
## 글자는 메인 화면과 같은 Poppins ExtraLight, 연보라 포인트. 값은 바로 적용하고 손을 떼거나 닫을 때 저장한다.
## 트리가 일시정지여도 움직인다 (process_mode ALWAYS). 누름은 여기서 자리로 판단한다.

signal closed

const WIDTH := 600.0
const ROW := 96.0
const TOP := 150.0          # 패널 위에서 첫 줄까지
const SIDE := 48.0          # 패널 안쪽 여백
const LABEL_SIZE := 40
const TITLE_SIZE := 64
const PANEL_COLOR := Color(0.02, 0.016, 0.051, 0.93)  # 무대 바탕색(BOOT_COLOR) 반투명
const DIM := Color(0.02, 0.016, 0.051, 0.55)

var save: SaveData
var haptics: Haptics
var panel: Panel
var music_slider: UiSlider
var sfx_slider: UiSlider
var vibration_value: Label
var guide_value: Label
var done_label: Label

var _rows := {}       # 이름 -> 누르는 줄 (Control)
var _drag: UiSlider    # 끌고 있는 슬라이더
var _drag_index := -1


func _init() -> void:
	name = "SettingsPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = Panel.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_COLOR
	box.border_color = Color(TitleScreen.LAVENDER, 0.35)
	box.set_border_width_all(2)
	box.set_corner_radius_all(28)
	box.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var title := TitleScreen.text_label("SettingsTitle", "SETTINGS", TITLE_SIZE, TitleScreen.TITLE_COLOR)
	title.offset_top = 36.0
	panel.add_child(title)
	music_slider = _slider_row("MUSIC")
	sfx_slider = _slider_row("SFX")
	vibration_value = _value_row("VIBRATION")
	guide_value = _value_row("SHOW GUIDE")
	done_label = TitleScreen.text_label("Done", "DONE", LABEL_SIZE, Color.WHITE)
	panel.add_child(done_label)
	_rows["DONE"] = done_label


## 한 줄: 왼쪽 이름 + 오른쪽 슬라이더
func _slider_row(title: String) -> UiSlider:
	var row := _row(title)
	var slider := UiSlider.new()
	slider.name = title.capitalize() + "Slider"
	slider.position = Vector2(WIDTH - SIDE - 300.0, (ROW - slider.custom_minimum_size.y) * 0.5)
	slider.size = slider.custom_minimum_size
	row.add_child(slider)
	return slider


## 한 줄: 왼쪽 이름 + 오른쪽 값 글자(연보라). 줄 전체를 누른다
func _value_row(title: String) -> Label:
	var row := _row(title)
	var value := TitleScreen.text_label(title.capitalize().replace(" ", "") + "Value", "", LABEL_SIZE, TitleScreen.LAVENDER)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.offset_left = SIDE
	value.offset_right = -SIDE
	value.offset_top = (ROW - LABEL_SIZE * 1.5) * 0.5
	row.add_child(value)
	return value


func _row(title: String) -> Control:
	var row := Control.new()
	row.name = title.capitalize().replace(" ", "") + "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size = Vector2(WIDTH, ROW)
	var label := TitleScreen.text_label("", title, LABEL_SIZE, Color(1, 1, 1, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.offset_left = SIDE
	label.offset_top = (ROW - LABEL_SIZE * 1.5) * 0.5
	row.add_child(label)
	panel.add_child(row)
	_rows[title] = row
	return row


## 열기: 지금 값을 보이고, 진동을 지원하지 않으면 그 줄을 숨기고 아래 줄을 올린다
func open(data: SaveData, buzz: Haptics) -> void:
	save = data
	haptics = buzz
	music_slider.value = save.music
	sfx_slider.value = save.sfx
	_rows["VIBRATION"].visible = haptics.supported
	var y := TOP
	for key in ["MUSIC", "SFX", "VIBRATION", "SHOW GUIDE"]:
		var row: Control = _rows[key]
		if row.visible:
			row.position = Vector2(0.0, y)
			y += ROW
	done_label.offset_top = y + 28.0
	done_label.offset_bottom = done_label.offset_top + LABEL_SIZE * 1.5
	var height := y + 28.0 + LABEL_SIZE * 1.5 + 44.0
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -WIDTH * 0.5
	panel.offset_right = WIDTH * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	_show_values()
	visible = true


func _show_values() -> void:
	vibration_value.text = "ON" if save.vibration else "OFF"
	guide_value.text = "NEXT %d RUNS" % save.guide_left if save.guide_left > 0 else ""


func close() -> void:
	_drag = null
	save.save()
	print("SETTINGS 음악 %.2f 효과음 %.2f 진동 %s 안내 %d판" % [save.music, save.sfx, save.vibration, save.guide_left])  # 저장 확인용 한 줄
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()  # 설정 뒤의 게임·메뉴는 누름을 받지 않는다
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		close()
		return
	if event is InputEventScreenDrag and _drag and event.index == _drag_index:
		_drag.set_from_x(event.position.x)
		_apply_volumes()
		return
	if not event is InputEventScreenTouch:
		return
	if not event.pressed:
		if _drag and event.index == _drag_index:
			_drag = null
			save.save()
		return
	tap(event.position, event.index)


## 화면 자리를 누름 (테스트에서도 부른다)
func tap(point: Vector2, index := 0) -> void:
	for slider: UiSlider in [music_slider, sfx_slider]:
		if slider.hit(point):
			_drag = slider
			_drag_index = index
			slider.set_from_x(point.x)
			_apply_volumes()
			return
	if _hit("VIBRATION", point):
		save.vibration = not save.vibration
		haptics.enabled = save.vibration
		save.save()
		haptics.fire(Haptics.Event.PERFECT)  # 켜면 바로 한 번 짧게 울려 알려 준다
	elif _hit("SHOW GUIDE", point):
		save.replay_guide()
	elif _hit("DONE", point) or not panel.get_global_rect().has_point(point):
		close()
		return
	_show_values()


func _hit(key: String, point: Vector2) -> bool:
	var row: Control = _rows[key]
	return row.is_visible_in_tree() and row.get_global_rect().has_point(point)


func _apply_volumes() -> void:
	save.music = music_slider.value
	save.sfx = sfx_slider.value
	AudioManager.set_volumes(save.music, save.sfx)
