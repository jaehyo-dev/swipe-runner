shader_type spatial;
// 길 바닥: 어두운 바닥 + 레인 경계 발광선(점선이 뒤로 흘러옴) + 가로 줄무늬.
// 텍스처 없이 월드 좌표만으로 그린다. 안개는 엔진 안개가 알아서 적용한다.
render_mode unshaded;

uniform float scroll = 0.0;          // 뒤로 흘러간 거리 (main.gd가 매 프레임 올림)
uniform float lane_width = 1.5;
uniform vec3 base_color : source_color = vec3(0.025, 0.03, 0.09);
uniform vec3 road_color : source_color = vec3(0.05, 0.06, 0.16);
uniform vec3 line_color : source_color = vec3(0.45, 1.0, 0.9);
uniform float energy = 1.5;  // 밝기 순서: 장애물 모서리 선(가장 센 채널 1.6~1.8)보다 낮게
uniform float flash = 0.0;   // 음악 단계가 오를 때 잠깐 1 → 0 (main.gd)
uniform float flash_energy = 1.59;  // 빛날 때 밝기: 여기서도 모서리 선을 넘지 않으므로 선을 굵게 채워 눈에 띄게 한다

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 거리 d에서 폭 half인 선의 밝기. 멀리서도 최소 1픽셀로 보이게 fwidth만큼 넓힌다.
float line(float d, float half_w, float aa) {
	return 1.0 - smoothstep(half_w, half_w + aa, d);
}

void fragment() {
	float x = wpos.x;
	float zc = wpos.z - scroll;
	float road_half = lane_width * 1.5;
	float on_road = step(abs(x), road_half + 0.001);

	// 레인 경계선: x = -2.25, -0.75, 0.75, 2.25
	float dx = abs(fract((x - lane_width * 0.5) / lane_width + 0.5) - 0.5) * lane_width;
	float aa = fwidth(x) * 1.5;
	float edge = line(dx, 0.022 * (1.0 + 1.5 * flash), aa) * on_road;
	// 점선: 흐르는 밝은 마디와 은은한 바탕선
	float dash = step(fract(zc / 3.0), 0.6);
	float edge_i = edge * mix(mix(0.3, 1.0, dash), 1.0, flash);

	// 가로 줄무늬 (6 간격으로 흘러옴)
	float dz = abs(fract(zc / 6.0 + 0.5) - 0.5) * 6.0;
	float bar = line(dz, 0.025 * (1.0 + 2.0 * flash), fwidth(zc) * 1.5) * on_road * mix(0.35, 1.0, flash);

	vec3 col = mix(base_color, road_color, on_road);
	col += line_color * mix(energy, flash_energy, flash) * min(edge_i + bar, 1.0);
	ALBEDO = col;
}
