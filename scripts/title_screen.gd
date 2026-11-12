class_name TitleScreen
extends Control
## 메인 화면 글자 (ART_BIBLE.md 14): 위에 "SWIPE / PULSE", 그 아래 BEST, 처음 몇 판만 조작 안내, 아래쪽 "SWIPE TO START", 오른쪽 위 소리 버튼과 그 왼쪽 설정 톱니.
## 글자는 모두 Poppins ExtraLight(점수 숫자와 같은 계열). 무대·젤리·음악은 main이 맡고 여기서는 글자만 보이고 감춘다.
## v0.10.0: "SWIPE TO START" 아래 DAILY 버튼(연보라 테, 오늘 안 했으면 점). 누르면 같은 무대 위에서 0.3초 교차 페이드로
## 오늘의 판 시작 화면(DAILY #n, TODAY BEST, STREAK, NEW IN, 왼쪽 위 집 버튼)으로 바뀐다. SWIPE TO START는 두 화면이 함께 쓴다.

const FONT := preload("res://assets/fonts/Poppins-ExtraLight.ttf")
const LAVENDER := Color(0.788, 0.722, 1.0)       # #C9B8FF: 방울 테와 같은 연보라
const TITLE_COLOR := Color(0.93, 0.9, 1.0)       # 흰색에 가까운 연보라 글자
const TITLE_GLOW := Color(0.788, 0.722, 1.0, 0.45)  # 글자 둘레 은은한 빛
const TITLE_SIZE := 190    # 점수 숫자(170)보다 크게
const TITLE_TOP := 130.0
const TITLE_LINE := -70    # 두 줄 사이를 좁힌다 (Poppins는 줄 높이가 커서)
const LINE_SIZE := 40      # BEST·조작 안내: 게임의 BEST 줄과 같은 크기
const BEST_TOP := 560.0
const GUIDE_TOP := 640.0
const GUIDE_ROW := 64.0
const ICON_COLUMN := 96.0  # 조작 안내 기호 칸 폭
const GUIDE_ART := 0.7     # 조작 안내 기호 크기 (글자 높이에 맞춘다)
const TEXT_COLUMN := 150.0
const START_GAP := 40.0     # 젤리 빛 웅덩이 앞 끝에서 "SWIPE TO START"까지 (v0.9.1: 빛 바깥 아래)
const START_BOTTOM := 190.0  # 화면 아래에서 "SWIPE TO START"까지 가장 높은 자리 (세로 화면: 길 위 가운데쯤)
const START_FLOOR := 64.0    # 화면 아래에서 이만큼은 비운다 (버전 글자 자리)
const START_LOW := 0.4     # 박에 맞춰 이 밝기와 START_HIGH 사이를 천천히 오간다 (v0.9.1: 더 밝게, BEST 0.7보다 살짝 어둡게)
const START_HIGH := 0.62
const START_BEATS := 2.0   # 한 번 밝아졌다 흐려지는 데 걸리는 박 수
const SOUND_SIDE := 96.0   # 소리 버튼 누르는 자리(px). 그림은 그 절반
const SOUND_MARGIN := 20.0
const DAILY_GAP := 14.0      # SWIPE TO START 아래에서 DAILY 버튼까지
const DAILY_ROW := 76.0      # DAILY 버튼 높이 (테 포함). START_FLOOR 위에 이만큼 더 비운다
const DAILY_PAD := Vector2(26.0, 6.0)
const DOT_RADIUS := 7.0      # 오늘 아직 안 했으면 버튼 오른쪽 위의 작은 점
const DAILY_TITLE_SIZE := 110
const DAILY_TITLE_TOP := 300.0
const SWITCH_TIME := 0.3     # 메인 ↔ 오늘의 판 시작 화면

var best_label: Label
var guide: VBoxContainer
var start_label: Label
var sound: UiIcon
var gear: UiIcon  # 설정 (소리 버튼 왼쪽)
var daily_button: Label  # 메인 화면의 "DAILY #n"
var daily_dot: Control
var daily_home: UiIcon   # 오늘의 판 시작 화면의 왼쪽 위 집
var daily_shown := false  # 오늘의 판 시작 화면인가
var _menu_items: Control   # 메인 화면에만 있는 글자 (제목·BEST·안내·DAILY 버튼)
var _daily_items: Control  # 오늘의 판 시작 화면에만 있는 글자
var _daily_title: Label
var _daily_lines: Label   # TODAY BEST / STREAK / NEW IN
var _switch: Tween


func _init() -> void:
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_items = _group("MenuItems")
	_daily_items = _group("DailyItems")
	var title := text_label("TitleLabel", "SWIPE\nPULSE", TITLE_SIZE, TITLE_COLOR)
	title.label_settings.line_spacing = TITLE_LINE
	title.label_settings.shadow_color = TITLE_GLOW
	title.label_settings.shadow_size = 18
	title.label_settings.shadow_offset = Vector2.ZERO
	title.offset_top = TITLE_TOP
	_menu_items.add_child(title)
	best_label = text_label("MenuBestLabel", "", LINE_SIZE, Color(1, 1, 1, 0.7))
	best_label.offset_top = BEST_TOP
	_menu_items.add_child(best_label)
	_build_guide()
	_build_daily()
	start_label = text_label("StartLabel", "SWIPE TO START", LINE_SIZE, Color.WHITE)
	start_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(start_label)
	place_start(0.0, 1280.0)
	sound = UiIcon.new(UiIcon.Kind.SOUND_ON, Color(1, 1, 1, 0.7), SOUND_SIDE)
	sound.name = "SoundButton"
	corner(sound, true)
	add_child(sound)
	gear = UiIcon.new(UiIcon.Kind.GEAR, Color(1, 1, 1, 0.7), SOUND_SIDE)
	gear.name = "SettingsButton"
	corner(gear, true)
	gear.offset_left -= SOUND_SIDE
	gear.offset_right -= SOUND_SIDE
	add_child(gear)


## 아이콘을 화면 위 모서리(right면 오른쪽, 아니면 왼쪽)에 둔다. 게임 오버의 집 버튼도 같은 자리 규칙을 쓴다
static func corner(icon: Control, right: bool) -> void:
	var side := icon.custom_minimum_size.x
	icon.set_anchors_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
	icon.offset_left = -side - SOUND_MARGIN if right else SOUND_MARGIN
	icon.offset_right = icon.offset_left + side
	icon.offset_top = SOUND_MARGIN
	icon.offset_bottom = SOUND_MARGIN + side


## "SWIPE TO START"를 젤리 빛 웅덩이(pool: 화면 y) 아래에 둔다. 화면이 짧으면 아래 끝까지만 (main._fit_camera가 부른다)
func place_start(pool: float, height: float) -> void:
	var line := LINE_SIZE * 1.6
	var top := clampf(pool + START_GAP, height - START_BOTTOM - DAILY_ROW, height - START_FLOOR - line - DAILY_GAP - DAILY_ROW)
	start_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	start_label.offset_top = top
	start_label.offset_bottom = top + line
	daily_button.offset_top = top + line + DAILY_GAP
	daily_button.offset_bottom = daily_button.offset_top + DAILY_ROW


## 메인 화면을 다시 보일 때: 기록(없으면 숨김), 조작 안내, 소리 상태, 오늘의 판 번호와 점(오늘 안 했으면)
func show_menu(best: int, show_guide: bool, muted: bool, daily_number: int, daily_new: bool) -> void:
	best_label.visible = best > 0
	best_label.text = "BEST %d" % best
	guide.visible = show_guide
	set_daily_button(daily_number, daily_new)
	set_muted(muted)
	_cross(false, 0.0)
	modulate.a = 1.0
	visible = true


func set_daily_button(daily_number: int, daily_new: bool) -> void:
	daily_button.text = "DAILY #%d" % daily_number
	daily_dot.visible = daily_new


## 메인 ↔ 오늘의 판 시작 화면 (0.3초 교차 페이드). 집 버튼은 오늘의 판 화면에서만 누를 수 있다
func show_daily(on: bool) -> void:
	_cross(on, SWITCH_TIME)


## 오늘의 판 시작 화면 글자. best 0이면 TODAY BEST 줄은 숨긴다
func set_daily(daily_number: int, best: int, streak: int, countdown: String) -> void:
	_daily_title.text = "DAILY #%d" % daily_number
	var lines := PackedStringArray()
	if best > 0:
		lines.append("TODAY BEST %d" % best)
	lines.append("STREAK %d" % streak)
	lines.append("NEW IN " + countdown)
	_daily_lines.text = "\n".join(lines)


func _cross(to_daily: bool, time: float) -> void:
	daily_shown = to_daily
	daily_home.visible = to_daily
	if _switch:
		_switch.kill()
	_menu_items.visible = true
	_daily_items.visible = true
	_switch = create_tween().set_parallel() if time > 0.0 and is_inside_tree() else null
	for pair: Array in [[_menu_items, not to_daily], [_daily_items, to_daily]]:
		var group: Control = pair[0]
		if _switch:
			_switch.tween_property(group, "modulate:a", 1.0 if pair[1] else 0.0, time)
		else:
			group.modulate.a = 1.0 if pair[1] else 0.0
		group.visible = pair[1] or _switch != null
	if _switch:
		_switch.chain().tween_callback(func() -> void:
			_menu_items.visible = not to_daily
			_daily_items.visible = to_daily)


## DAILY 버튼을 눌렀는가 (메인 화면에서만)
func daily_hit(point: Vector2) -> bool:
	return not daily_shown and daily_button.is_visible_in_tree() and daily_button.get_global_rect().has_point(point)


func set_muted(muted: bool) -> void:
	sound.kind = UiIcon.Kind.SOUND_OFF if muted else UiIcon.Kind.SOUND_ON


## beat: 지금 박(소수). "SWIPE TO START"가 박에 맞춰 천천히 밝아졌다 흐려진다
func pulse(beat: float) -> void:
	var k := 0.5 - 0.5 * cos(TAU * beat / START_BEATS)
	start_label.modulate.a = lerpf(START_LOW, START_HIGH, k)


func _group(node_name: String) -> Control:
	var group := Control.new()
	group.name = node_name
	group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(group)
	return group


## 메인 화면의 DAILY 버튼(BEST 줄과 같은 글씨, 연보라 가는 테, 오늘 안 했으면 오른쪽 위 점)과 오늘의 판 시작 화면 글자
func _build_daily() -> void:
	daily_button = text_label("DailyButton", "DAILY", LINE_SIZE, Color(1, 1, 1, 0.7))
	daily_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	daily_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	daily_button.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.border_color = Color(LAVENDER, 0.8)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(int(DAILY_ROW * 0.5))
	frame.content_margin_left = DAILY_PAD.x
	frame.content_margin_right = DAILY_PAD.x
	frame.content_margin_top = DAILY_PAD.y
	frame.content_margin_bottom = DAILY_PAD.y
	daily_button.add_theme_stylebox_override("normal", frame)
	_menu_items.add_child(daily_button)
	daily_dot = Control.new()
	daily_dot.name = "DailyDot"
	daily_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	daily_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	daily_dot.position = Vector2(-DOT_RADIUS * 1.5, DOT_RADIUS * 0.5)
	daily_dot.draw.connect(func() -> void: daily_dot.draw_circle(Vector2.ZERO, DOT_RADIUS, LAVENDER, true, -1.0, true))
	daily_button.add_child(daily_dot)
	_daily_title = text_label("DailyTitle", "DAILY", DAILY_TITLE_SIZE, TITLE_COLOR)
	_daily_title.label_settings.shadow_color = TITLE_GLOW
	_daily_title.label_settings.shadow_size = 14
	_daily_title.label_settings.shadow_offset = Vector2.ZERO
	_daily_title.offset_top = DAILY_TITLE_TOP
	_daily_items.add_child(_daily_title)
	_daily_lines = text_label("DailyLines", "", LINE_SIZE, Color(1, 1, 1, 0.7))
	_daily_lines.offset_top = BEST_TOP
	_daily_lines.label_settings.line_spacing = 14
	_daily_items.add_child(_daily_lines)
	daily_home = UiIcon.new(UiIcon.Kind.HOME, Color(1, 1, 1, 0.7), SOUND_SIDE)
	daily_home.name = "DailyHomeButton"
	corner(daily_home, false)
	daily_home.visible = false
	add_child(daily_home)


## 조작 안내 세 줄: 기호 ‹ › ↑ ↓(연보라, 선으로 그림) + 말(흰색). 기호 칸을 맞춰 세 줄이 같은 세로줄에 선다
func _build_guide() -> void:
	guide = VBoxContainer.new()
	guide.name = "Guide"
	guide.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	guide.offset_top = GUIDE_TOP
	guide.offset_left = -(ICON_COLUMN + TEXT_COLUMN) * 0.5
	guide.offset_right = (ICON_COLUMN + TEXT_COLUMN) * 0.5
	guide.add_theme_constant_override("separation", 0)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_items.add_child(guide)
	for row: Array in [[UiIcon.Kind.LEFT_RIGHT, "MOVE"], [UiIcon.Kind.UP, "JUMP"], [UiIcon.Kind.DOWN, "SLIDE"]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		line.custom_minimum_size.y = GUIDE_ROW
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mark := UiIcon.new(row[0], LAVENDER, LINE_SIZE)
		mark.art = GUIDE_ART
		mark.custom_minimum_size.x = ICON_COLUMN
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mark)
		var word := text_label("", row[1], LINE_SIZE, Color(1, 1, 1, 0.7))
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		word.custom_minimum_size.x = TEXT_COLUMN
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(word)
		guide.add_child(line)


## 메인 화면 글자 모양(Poppins ExtraLight, 가운데 정렬, 누름은 받지 않음). 일시정지·설정 화면도 같은 모양을 쓴다
static func text_label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	if not node_name.is_empty():
		label.name = node_name
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = font_size
	settings.font_color = color
	label.label_settings = settings
	return label
