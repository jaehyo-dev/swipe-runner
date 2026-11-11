class_name TitleScreen
extends Control
## 메인 화면 글자 (ART_BIBLE.md 14): 위에 "SWIPE / PULSE", 그 아래 BEST, 처음 몇 판만 조작 안내, 아래쪽 "SWIPE TO START", 오른쪽 위 소리 버튼과 그 왼쪽 설정 톱니.
## 글자는 모두 Poppins ExtraLight(점수 숫자와 같은 계열). 무대·젤리·음악은 main이 맡고 여기서는 글자만 보이고 감춘다.

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

var best_label: Label
var guide: VBoxContainer
var start_label: Label
var sound: UiIcon
var gear: UiIcon  # 설정 (소리 버튼 왼쪽)


func _init() -> void:
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("TitleLabel", "SWIPE\nPULSE", TITLE_SIZE, TITLE_COLOR)
	title.label_settings.line_spacing = TITLE_LINE
	title.label_settings.shadow_color = TITLE_GLOW
	title.label_settings.shadow_size = 18
	title.label_settings.shadow_offset = Vector2.ZERO
	title.offset_top = TITLE_TOP
	add_child(title)
	best_label = _label("MenuBestLabel", "", LINE_SIZE, Color(1, 1, 1, 0.7))
	best_label.offset_top = BEST_TOP
	add_child(best_label)
	_build_guide()
	start_label = _label("StartLabel", "SWIPE TO START", LINE_SIZE, Color.WHITE)
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
	var top := clampf(pool + START_GAP, height - START_BOTTOM, height - START_FLOOR - line)
	start_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	start_label.offset_top = top
	start_label.offset_bottom = top + line


## 메인 화면을 다시 보일 때: 기록(없으면 숨김), 조작 안내, 소리 상태
func show_menu(best: int, show_guide: bool, muted: bool) -> void:
	best_label.visible = best > 0
	best_label.text = "BEST %d" % best
	guide.visible = show_guide
	set_muted(muted)
	modulate.a = 1.0
	visible = true


func set_muted(muted: bool) -> void:
	sound.kind = UiIcon.Kind.SOUND_OFF if muted else UiIcon.Kind.SOUND_ON


## beat: 지금 박(소수). "SWIPE TO START"가 박에 맞춰 천천히 밝아졌다 흐려진다
func pulse(beat: float) -> void:
	var k := 0.5 - 0.5 * cos(TAU * beat / START_BEATS)
	start_label.modulate.a = lerpf(START_LOW, START_HIGH, k)


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
	add_child(guide)
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
		var word := _label("", row[1], LINE_SIZE, Color(1, 1, 1, 0.7))
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		word.custom_minimum_size.x = TEXT_COLUMN
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(word)
		guide.add_child(line)


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	return text_label(node_name, text, font_size, color)


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
