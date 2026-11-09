shader_type spatial;
// 빛나는 관: 장애물 선·화살, 난간. 둥근 단면처럼 가운데가 밝고 가장자리는 어둡다. 불투명이라 젤리 속으로 비쳐 보인다.
// 멀어져도 끊기지 않게 관 굵기를 화면 기준 최소 굵기까지 넓힌다 (MSAA가 다듬을 수 있는 굵기).
render_mode unshaded;

uniform vec3 color : source_color = vec3(1.0);
uniform float energy = 1.0;         // 전체 밝기 배율 (난간이 단계가 오를 때 잠깐 올림)
uniform float min_pixels = 0.75;    // 관 반지름의 화면 최소 크기(픽셀)

void vertex() {
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pixel = 2.0 * dist / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);  // 이 거리에서 1픽셀의 세계 크기
	VERTEX += NORMAL * max(min_pixels * pixel - UV.x, 0.0);  // UV.x = 메시의 관 반지름
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), VIEW));
	ALBEDO = color * energy * COLOR.r * mix(0.5, 1.0, facing * facing * facing);
}
