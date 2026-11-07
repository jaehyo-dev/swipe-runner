shader_type spatial;
// 발밑의 부드러운 원형 그림자: 가운데가 가장 진하고 가장자리로 갈수록 투명해진다.
render_mode unshaded, depth_draw_never, fog_disabled;

uniform float strength = 0.7;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.01, 0.0, 0.06);
	ALPHA = (1.0 - smoothstep(0.1, 1.0, r)) * strength;
}
