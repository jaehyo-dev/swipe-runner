shader_type spatial;
// 장애물 몸통 + 앞면 테두리 (한 메시, 종류마다 MultiMesh 하나). 같은 셰이더로 두 번 그린다:
//   먼저 pass_alpha 0으로 깊이만 쓰고, 그다음 색을 칠한다. 그래서 화소마다 가장 앞면 하나만 보인다: 몸통은 정확히 70%이고, 뒤 장애물의 면과 선은 앞 몸통에 가려진다.
// 테두리 관(UV.x > 0)은 멀어져도 끊기지 않게 화면 기준 최소 굵기까지 넓힌다 (MSAA가 다듬을 수 있는 굵기). 메시와 재질이 같아 그리는 횟수가 장애물 수와 무관하다.
render_mode unshaded, cull_disabled, depth_draw_always;

uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);
uniform vec3 edge_color : source_color = vec3(1.0);
uniform vec3 fog_color : source_color = vec3(0.2);  // 지금의 안개 색
uniform float pass_alpha = 1.0;     // 0: 깊이만 쓰는 차례, 1: 색을 칠하는 차례
uniform float body = 0.85;          // 면 밝기: 밝기 순서(난간·물방울 > 유리 면)를 지키는 값
uniform float body_alpha = 0.7;     // 몸통 불투명도 (사용자 확정값)
uniform float min_pixels = 0.75;    // 관 반지름의 화면 최소 크기(픽셀)
uniform float haze_near = 6.0;      // 연속 기둥의 뒤쪽 것이 흐려지기 시작하는 카메라 거리: 가까워지면 또렷해진다
uniform float haze_far = 16.0;

varying float is_edge;
varying float haze;

void vertex() {
	is_edge = step(0.0001, UV.x);
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(view_pos);
	float pixel = 2.0 * dist / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);  // 이 거리에서 1픽셀의 세계 크기
	VERTEX += NORMAL * max(min_pixels * pixel - UV.x, 0.0) * is_edge;
	haze = INSTANCE_CUSTOM.r * smoothstep(haze_near, haze_far, dist);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec3 col;
	float alpha;
	if (is_edge > 0.5) {
		col = edge_color * COLOR.r * mix(0.5, 1.0, facing * facing * facing);
		alpha = 1.0;
	} else {
		float f = pow(1.0 - facing, 2.0);
		col = tint * (body + 0.25 * f);
		alpha = body_alpha;
	}
	ALBEDO = mix(col, fog_color, haze);
	ALPHA = alpha * pass_alpha;
}
