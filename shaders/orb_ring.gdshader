shader_type spatial;
// 방울을 먹은 순간 주인공 둘레에 퍼졌다 사라지는 작은 빛 고리 (카메라를 보는 판 하나). age 0 → 1을 main.gd가 0.15초에 돌린다.
// 연보라 #C9B8FF 가산. 반지름 0.35 → 0.95, 굵기는 얇아지고 빛은 사라진다.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.788, 0.722, 1.0);
uniform float strength = 0.9;
uniform float age = 0.0;

void vertex() {
	// 판을 카메라 쪽으로 돌린다 (크기는 메시 그대로)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;  // 판 가장자리 = 1 (메시 반폭 1.0m)
	float radius = mix(0.35, 0.95, 1.0 - (1.0 - age) * (1.0 - age));  // 처음 빠르게 퍼진다
	float width = mix(0.08, 0.03, age);
	float band = 1.0 - smoothstep(0.0, width, abs(r - radius));
	ALBEDO = color * strength;
	ALPHA = band * (1.0 - age);
}
