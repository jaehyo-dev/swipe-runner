shader_type spatial;
// 유리 느낌: 가장자리(비스듬히 보이는 면)가 더 진하고 가운데는 거의 투명한 연한 색 면.
// 멀리서는 면을 진하게 해서 안개 속에서도 키 큰 기둥 / 바닥에 붙은 턱 / 떠 있는 막대 실루엣이 먼저 읽힌다.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);
uniform float near_alpha = 0.16;
uniform float far_alpha = 0.72;
uniform float far_from = 12.0;  // 카메라 거리: 여기서부터 진해지기 시작
uniform float far_to = 34.0;    // 여기서 가장 진함

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = tint * (0.85 + 0.5 * f);
	ALPHA = clamp(mix(near_alpha, far_alpha, smoothstep(far_from, far_to, length(VERTEX))) + 0.4 * f, 0.0, 1.0);
}
