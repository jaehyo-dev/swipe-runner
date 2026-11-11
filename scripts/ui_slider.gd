class_name UiSlider
extends Control
## 설정의 크기 슬라이더: 가는 선 위에 연보라로 채운 부분과 동그란 손잡이 (선으로 그림, 텍스처 없음).
## 누름·끌기는 SettingsPanel이 자리로 판단해 set_from_x로 넘긴다.

const KNOB := 13.0

var value := 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(300, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y := size.y * 0.5
	var left := KNOB
	var right := size.x - KNOB
	var at := lerpf(left, right, value)
	draw_line(Vector2(left, y), Vector2(right, y), Color(1, 1, 1, 0.25), 2.0, true)
	draw_line(Vector2(left, y), Vector2(at, y), TitleScreen.LAVENDER, 3.0, true)
	draw_circle(Vector2(at, y), KNOB, TitleScreen.LAVENDER, true, -1.0, true)


## 화면 x 좌표에서 값을 정한다 (손잡이 반지름만큼 양끝 여유)
func set_from_x(global_x: float) -> void:
	var rect := get_global_rect()
	value = inverse_lerp(rect.position.x + KNOB, rect.end.x - KNOB, global_x)


## 누르는 자리: 위아래로 넉넉하게
func hit(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().grow_individual(16, 20, 16, 20).has_point(point)
