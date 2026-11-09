shader_type spatial;
// 빛나는 관: 난간. 굵은 네온 색 가운데에 흰빛 심이 있다. 불투명이라 젤리 속으로 비쳐 보인다.
// 멀어져도 끊기지 않게 관 굵기를 화면 기준 최소 굵기까지 넓힌다 (MSAA가 다듬을 수 있는 굵기).
// 장애물과 같은 안개 거리에서 지평선 색으로 사라진다.
render_mode unshaded, fog_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float energy = 1.0;         // 전체 밝기 배율
uniform float min_pixels = 1.0;     // 관 반지름의 화면 최소 크기(픽셀)
uniform vec3 fog_color : source_color = vec3(0.2);
uniform float fog_near = 24.75;     // main.gd가 매 프레임 (장애물과 같은 값)
uniform float fog_far = 27.0;

varying float core;
varying float haze;

void vertex() {
	core = UV.y;  // 1이면 흰빛 심 (ArtMeshes.rails)
	haze = smoothstep(fog_near, fog_far, -(MODEL_MATRIX * vec4(VERTEX, 1.0)).z);
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pixel = 2.0 * dist / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);  // 이 거리에서 1픽셀의 세계 크기
	VERTEX += NORMAL * max(min_pixels * (core > 0.5 ? 0.3 : 1.0) * pixel - UV.x, 0.0);  // UV.x = 메시의 관 반지름
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), VIEW));
	ALBEDO = mix(energy * (core > 0.5 ? vec3(0.86, 0.82, 1.0) : color * mix(0.6, 1.0, facing)), fog_color, haze);
}
