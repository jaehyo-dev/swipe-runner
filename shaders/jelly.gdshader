shader_type spatial;
// 발광 젤리: 가운데는 흰빛이 도는 밝은 민트(1을 넘겨서 글로우가 번짐), 가장자리는 민트.
render_mode unshaded;

uniform vec3 mint : source_color = vec3(0.498, 0.878, 0.784);
uniform float core_energy = 1.35;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	vec3 core = mix(mint, vec3(1.0), 0.6) * core_energy;
	ALBEDO = mix(core, mint, f);
}
