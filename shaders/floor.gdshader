shader_type spatial;
// 유리 바닥: 어두운 면 + 아주 옅은 비스듬한 빛 결 + 난간 빛이 비친 양 가장자리. 격자선은 없다 (ART_BIBLE.md 10).
// 텍스처 없이 월드 좌표만으로 그린다. 안개는 엔진 안개가 알아서 적용한다.
render_mode unshaded;

uniform float scroll = 0.0;          // 뒤로 흘러간 거리 (main.gd가 매 프레임 올림)
uniform float road_half = 2.25;      // 길 반폭
uniform vec3 base_color : source_color = vec3(0.04, 0.03, 0.11);
uniform vec3 road_color : source_color = vec3(0.141, 0.102, 0.29);   // #241A4A
uniform vec3 sheen_color : source_color = vec3(0.55, 0.5, 1.0);
uniform float sheen_strength = 0.05; // 빛 결 밝기 (너무 밝으면 줄무늬로 읽힌다)
uniform float sheen_flow = 0.35;     // 세상보다 느리게 흘러 면 안쪽에 있는 빛처럼 보인다
uniform vec3 rail_color : source_color = vec3(0.45, 0.5, 1.0);       // main.gd RAIL_COLOR와 같은 색조
uniform float rail_glow = 0.09;      // 가장자리에 비친 난간 빛

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 비스듬한 빛 띠 하나: u를 period로 되풀이, 가운데 밝고 양옆으로 부드럽게 사라진다
float band(float u, float period, float width) {
	return 1.0 - smoothstep(0.0, width, abs(fract(u / period + 0.5) - 0.5) * period);
}

void fragment() {
	float x = wpos.x;
	float edge_soft = max(fwidth(x), 0.004);
	float on_road = 1.0 - smoothstep(road_half + 0.1, road_half + 0.1 + edge_soft * 2.0, abs(x));

	float u = wpos.z - scroll * sheen_flow + x * 0.75;
	float sheen = band(u, 17.0, 2.6) + 0.55 * band(u + 6.0, 11.0, 0.9);

	float d = max(road_half + 0.1 - abs(x), 0.0);
	vec3 col = mix(base_color, road_color, on_road);
	col += (sheen_color * sheen * sheen_strength + rail_color * rail_glow * exp(-d * d * 3.0)) * on_road;
	ALBEDO = col;
}
