shader_type spatial;
// 한 줄의 이웃 빛 방울을 잇는 아주 옅은 빛 실선 (MultiMesh 하나). 방울 줄이 '길'로 읽히게 한다.
// 연보라 #C9B8FF, 불투명도 0.18 (지시 15~20%). 안개 거리에서는 방울처럼 사라진다. 자리·길이는 main.gd가 매 프레임 쓴다.
// v0.12.1: 1픽셀보다 가는 먼 선은 끊긴 점선처럼 보인다 → 화면 최소 굵기까지 넓히고 그만큼 옅게(빛의 양은 그대로). 이미 옅은 반투명이라 가장자리 처리는 하지 않는다
// (상자 면마다 녹이면 윗면·옆면이 만나는 모서리가 어두워져 두 줄로 보였다).
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.788, 0.722, 1.0);
uniform float opacity = 0.18;
uniform float pulse = 0.0;          // 방울과 같은 박 빛 (박에 살짝 진해짐)
uniform float pulse_gain = 0.2;
uniform float fog_near = 24.75;
uniform float fog_far = 27.0;
uniform float half_width = 0.0175;  // 메시 굵기의 절반 (main.gd ORB_LINK_WIDTH)
uniform float min_pixels = 1.5;     // 선 굵기의 화면 최소 크기(픽셀)

varying float world_z;
varying float thin;   // 넓힌 배율의 역수 (옅게)

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	float pixel = 2.0 * length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz) / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);
	float widen = max(min_pixels * pixel / (2.0 * half_width), 1.0);
	VERTEX.xy *= widen;
	thin = 1.0 / widen;
}

void fragment() {
	ALBEDO = color;
	// 선의 각 점이 자기 거리에서 안개에 녹는다 (줄 앞쪽이 먼저 보인다)
	ALPHA = opacity * thin * (1.0 + pulse_gain * pulse) * (1.0 - smoothstep(fog_near, fog_far, -world_z));
}
