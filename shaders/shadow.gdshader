shader_type spatial;
// 발밑: 민트빛이 번지는 빛 웅덩이 + 가운데 작은 어두운 그림자 (몸이 떠 보이지 않게).
render_mode unshaded, depth_draw_never, fog_disabled;

uniform vec3 glow_color : source_color = vec3(0.498, 0.878, 0.784);  // 몸 민트
uniform float glow_strength = 0.32;  // 웅덩이 빛 세기 (주인공보다 훨씬 어둡게)
uniform float shadow_strength = 0.75;
uniform float shadow_size = 0.42;    // 그림자 반지름 (웅덩이 반지름 = 1)

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = (1.0 - smoothstep(0.25, 1.0, r)) * glow_strength;
	float dark = (1.0 - smoothstep(shadow_size * 0.4, shadow_size, r)) * shadow_strength;
	ALBEDO = mix(glow_color, vec3(0.01, 0.0, 0.06), dark / max(dark + glow, 0.001));
	ALPHA = clamp(dark + glow, 0.0, 1.0);
}
