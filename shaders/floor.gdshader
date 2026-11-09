shader_type spatial;
// 어두운 반사 바닥: 면 + 난간 빛이 비친 양 가장자리. 격자선은 없다 (ART_BIBLE.md 10). 반사는 mirror.gdshader가 그 위에 그린다.
// 텍스처 없이 월드 좌표만으로 그린다. 엔진 안개를 쓰면 발밑까지 보라로 떠서, 먼 곳에서만 지평선 안개 색으로 섞는다.
render_mode unshaded, fog_disabled;

uniform float road_half = 2.25;      // 길 반폭
uniform vec3 base_color : source_color = vec3(0.024, 0.031, 0.09);   // #060817
uniform vec3 road_color : source_color = vec3(0.047, 0.039, 0.11);   // #0C0A1C
uniform vec3 rail_color : source_color;
uniform float rail_glow = 0.16;      // 가장자리에 비친 난간 빛
uniform vec3 haze_color : source_color;  // 지평선 안개 색
uniform float haze_near = 16.0;      // 이 거리부터 안개 띠가 시작한다
uniform float haze_far = 90.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = wpos.x;
	float edge_soft = max(fwidth(x), 0.004);
	float on_road = 1.0 - smoothstep(road_half + 0.1, road_half + 0.1 + edge_soft * 2.0, abs(x));
	float d = max(road_half + 0.1 - abs(x), 0.0);
	vec3 col = mix(base_color, road_color, on_road) + rail_color * rail_glow * exp(-d * d * 3.0) * on_road;
	ALBEDO = mix(col, haze_color, smoothstep(haze_near, haze_far, length(wpos - CAMERA_POSITION_WORLD)));
}
