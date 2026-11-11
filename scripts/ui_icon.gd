class_name UiIcon
extends Control
## 기호를 가는 선으로 그린다: 조작 안내 ‹ › ↑ ↓(↑↓는 Poppins에 없고, ‹ ›는 글자로는 너무 작아 같은 굵기로 그린다), 소리 켜기/끄기, 집. 텍스처 그림은 쓰지 않는다.
## 그림은 크기(size)의 가운데 정사각형 안에 art 비율로 그린다. 크기를 넉넉히 두면 누르는 자리가 넓어진다.

enum Kind { LEFT_RIGHT, UP, DOWN, SOUND_ON, SOUND_OFF, HOME }

var kind := Kind.UP:
	set(value):
		kind = value
		queue_redraw()
var color := Color.WHITE
var width := 2.0  # 선 굵기(px, 720x1280 기준). Poppins ExtraLight 글자 획과 비슷하게
var art := 0.5    # 정사각형 한 변 중 그림이 차지하는 비율


func _init(icon_kind := Kind.UP, icon_color := Color.WHITE, side := 48.0) -> void:
	kind = icon_kind
	color = icon_color
	custom_minimum_size = Vector2.ONE * side
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 누름은 main이 자리로 판단한다 (게임 입력과 한 곳에서)


func _draw() -> void:
	var u := minf(size.x, size.y) * art * 0.5  # 그림 반 폭
	var c := size * 0.5
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * u
	match kind:
		Kind.LEFT_RIGHT:
			for s in [-1.0, 1.0]:
				draw_polyline(PackedVector2Array([p.call(s * 0.35, -0.55), p.call(s * 0.9, 0), p.call(s * 0.35, 0.55)]), color, width, true)
		Kind.UP, Kind.DOWN:
			var s := -1.0 if kind == Kind.UP else 1.0
			draw_line(p.call(0, -s), p.call(0, s), color, width, true)
			draw_polyline(PackedVector2Array([p.call(-0.55, s * 0.45), p.call(0, s), p.call(0.55, s * 0.45)]), color, width, true)
		Kind.SOUND_ON, Kind.SOUND_OFF:
			draw_polyline(PackedVector2Array([p.call(-0.9, -0.35), p.call(-0.45, -0.35), p.call(0.05, -0.85), p.call(0.05, 0.85), p.call(-0.45, 0.35), p.call(-0.9, 0.35), p.call(-0.9, -0.35)]), color, width, true)
			if kind == Kind.SOUND_ON:
				for r in [0.45, 0.85]:
					draw_arc(p.call(0.05, 0), u * r, -PI * 0.3, PI * 0.3, 12, color, width, true)
			else:
				draw_line(p.call(0.4, -0.35), p.call(1.0, 0.35), color, width, true)
				draw_line(p.call(0.4, 0.35), p.call(1.0, -0.35), color, width, true)
		Kind.HOME:
			draw_polyline(PackedVector2Array([p.call(-0.9, -0.05), p.call(0, -0.85), p.call(0.9, -0.05)]), color, width, true)
			draw_polyline(PackedVector2Array([p.call(-0.65, -0.25), p.call(-0.65, 0.85), p.call(0.65, 0.85), p.call(0.65, -0.25)]), color, width, true)


## 화면 좌표 point가 이 아이콘의 누르는 자리 안인가
func hit(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(point)
