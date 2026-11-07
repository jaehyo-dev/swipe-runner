shader_type spatial;
// 유리 느낌: 가장자리(비스듬히 보이는 면)가 더 진하고 가운데는 거의 투명한 연한 색 면.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = tint * (0.85 + 0.5 * f);
	ALPHA = 0.14 + 0.4 * f;
}
