shader_type spatial;
// 한 줄의 이웃 빛 방울을 잇는 아주 옅은 빛 실선 (MultiMesh 하나). 방울 줄이 '길'로 읽히게 한다.
// 연보라 #C9B8FF, 불투명도 0.18 (지시 15~20%). 안개 거리에서는 방울처럼 사라진다. 자리·길이는 main.gd가 매 프레임 쓴다.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.788, 0.722, 1.0);
uniform float opacity = 0.18;
uniform float pulse = 0.0;          // 방울과 같은 박 빛 (박에 살짝 진해짐)
uniform float pulse_gain = 0.2;
uniform float fog_near = 24.75;
uniform float fog_far = 27.0;

varying float world_z;

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	ALBEDO = color;
	// 선의 각 점이 자기 거리에서 안개에 녹는다 (줄 앞쪽이 먼저 보인다)
	ALPHA = opacity * (1.0 + pulse_gain * pulse) * (1.0 - smoothstep(fog_near, fog_far, -world_z));
}
