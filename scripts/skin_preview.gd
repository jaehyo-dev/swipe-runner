class_name SkinPreview
extends Control
## 게임 오버 NEW SKIN의 젤리 미리보기 (2D 선·면 그림). 3D 젤리는 그 순간 충돌로 납작한 모양이고 하나 더 그리면 무거워서 따로 그린다.
## 찹쌀떡 윤곽(평평한 바닥 + 둥근 돔)을 몸 색으로 채우고, 테두리 빛·속빛·반사광·점 눈을 그린다. 무늬는 그리지 않는다.

const STEPS := 24
var params := {}  # SkinBook.shader_params 결과


func _draw() -> void:
	if params.is_empty():
		return
	var w := minf(size.x, size.y * 1.25) * 0.42  # 반지름 (px)
	var base := Vector2(size.x * 0.5, size.y * 0.92)
	var h := w * 1.25  # 키: 화면에서 본 젤리처럼 폭보다 낮게
	var outline := PackedVector2Array()
	for i in STEPS + 1:  # 오른쪽 바닥 → 정수리 → 왼쪽 바닥
		var a := PI * i / STEPS
		outline.append(base + Vector2(cos(a) * w * (0.9 + 0.1 * sin(a)), -sin(a) * h))  # 바닥은 반지름 90%, 위로 둥근 돔
	var body: Color = params["mint"]
	draw_colored_polygon(outline, Color(body, 0.85))
	var rim: Color = params["rim_color"]
	draw_polyline(outline, rim, 3.0, true)
	draw_line(outline[0], outline[-1], Color(params["band_color"], 0.9), 3.0, true)
	var core: Color = params["core_color"]
	var center := base + Vector2(0.0, -h * 0.35)
	for k in 4:  # 속빛: 겹친 원으로 부드럽게
		draw_circle(center, w * (0.32 - 0.07 * k), Color(core, 0.18), true, -1.0, true)
	draw_arc(base + Vector2(-w * 0.1, -h * 0.55), w * 0.5, PI * 1.08, PI * 1.38, 10, Color(1, 1, 1, 0.8), 3.0, true)  # 반사광
	for side in [-1.0, 1.0]:
		draw_circle(base + Vector2(side * w * 0.31, -h * 0.48), w * 0.07, Color("12332e"), true, -1.0, true)
