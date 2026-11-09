shader_type spatial;
// 지평선 양쪽의 레이저 (메시 하나에 6줄). 줄의 각도·개수·밝기는 재질 값이라 프레임마다 메시를 쓰지 않는다.
// 꼭짓점: VERTEX 줄의 시작점, UV 길이(0~1)·폭(-1~1), COLOR.r 분홍 여부, COLOR.g 줄 번호/5, COLOR.b 흔들림 위상, COLOR.a 기본 각도.
// 얇은 사각형만 칠해 오버드로를 줄이고, 번짐은 번쩍일 때 글로우에 맡긴다. 안개를 끄지 않으면 가산 혼합에 안개 색이 그대로 더해진다.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 blue : source_color = vec3(0.3, 0.4, 0.8);
uniform vec3 pink : source_color = vec3(0.7, 0.3, 0.6);
uniform float energy = 0.5;
uniform float count = 6.0;     // 보이는 줄 수. 소수면 다음 줄이 서서히 나타나는 중
uniform float clock = 0.0;     // 무대 시간(초)
uniform float beam_length = 300.0;
uniform float beam_width = 0.8;
uniform float sweep = 0.22;    // 좌우로 쓰는 폭(라디안)
uniform float sweep_rate = 0.4;

varying vec3 beam;
varying float across;

void vertex() {
	float side = sign(VERTEX.x);
	float angle = mix(0.85, 1.35, COLOR.a) + sweep * sin(clock * sweep_rate + COLOR.b * TAU);
	vec2 dir = vec2(-side * cos(angle), sin(angle));
	VERTEX.xy += dir * UV.x * beam_length + vec2(-dir.y, dir.x) * UV.y * beam_width;
	across = UV.y;
	float index = round(COLOR.g * 5.0);
	float tail = 1.0 - UV.x;
	beam = mix(blue, pink, COLOR.r) * energy * clamp(count - index, 0.0, 1.0) * tail * tail;
	if (count <= index) {
		VERTEX = vec3(0.0);  // 꺼진 줄은 칠할 화소가 없게 한 점으로 모은다
	}
}

void fragment() {
	ALBEDO = beam * (1.0 - across * across);
}
