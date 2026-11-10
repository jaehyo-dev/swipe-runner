shader_type spatial;
// 빛 방울 둘레의 연보라 빛 번짐(#C9B8FF): 카메라를 보는 판에 가운데가 진한 둥근 빛을 더한다. 구슬 뒤쪽은 깊이에 가려 둘레만 보인다.
// 흰 심(#F4F0FF)과 연보라 테로 흰 빛 줄기와 구분한다.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.788, 0.722, 1.0);
uniform float strength = 0.6;
uniform float pulse = 0.0;
uniform float pulse_grow = 0.25;
uniform float fog_near = 24.75;
uniform float fog_far = 27.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz) * (1.0 - smoothstep(fog_near, fog_far, -origin.z)) * (1.0 + pulse_grow * pulse);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = max(1.0 - r, 0.0);
	// ALPHA를 써야 투명 단계에서 가산으로 섞인다 (안 쓰면 불투명한 판으로 그려진다)
	ALBEDO = color * strength;
	ALPHA = a * a;
}
