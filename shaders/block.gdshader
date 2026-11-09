shader_type spatial;
// 장애물 (한 메시, 종류마다 MultiMesh 하나): 불투명한 어두운 몸통 + 색 빛 테두리 + 앞면 기호. 파란 기둥은 이 재질로 테두리만 그리고 몸통은 pillar.gdshader다. UV.y가 부위를, UV.x가 관 반지름을 담는다.
// 관은 멀어져도 끊기지 않게 화면 기준 최소 굵기까지 넓힌다. 환경 안개 대신 직접 섞는다: 안개가 진하면 z -45의 기호가 안 읽히고, 얇으면 세상 끝이 드러나기 때문이다.
render_mode unshaded, fog_disabled;

uniform vec3 body_color : source_color = vec3(0.07, 0.055, 0.14);
uniform vec3 tint : source_color = vec3(1.0);        // 앞면에 아주 옅게 비치는 색
uniform vec3 edge_color : source_color = vec3(1.0);
uniform vec3 mark_color : source_color = vec3(1.0);
uniform vec3 fog_color : source_color = vec3(0.2);   // 지금의 안개 색
uniform float face_tint = 0.07;     // 앞면 바탕의 색 비침
uniform float top_gloss = 0.24;     // 윗면 반사 하이라이트
uniform float min_pixels = 0.75;    // 관 반지름의 화면 최소 크기(픽셀)
uniform float mark_min_pixels = 1.0; // 기호는 더 굵게: 멀리서도 읽혀야 한다
uniform float haze_near = 6.0;      // 연속 블록의 뒤쪽 것이 흐려지기 시작하는 카메라 거리
uniform float haze_far = 16.0;
uniform float far_full = 51.0;      // z -45까지는 또렷하게
uniform float far_gone = 65.0;      // 생성 지점 z -60에서는 안개 색: 툭 나타나지 않게

varying float part;
varying float haze;
varying vec3 local_normal;

void vertex() {
	part = UV.y;
	local_normal = NORMAL;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float pixel = 2.0 * dist / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);  // 이 거리에서 1픽셀의 세계 크기
	if (UV.x > 0.0) {
		VERTEX += NORMAL * max((part > 1.5 ? mark_min_pixels : min_pixels) * pixel - UV.x, 0.0);
	}
	haze = max(INSTANCE_CUSTOM.r * smoothstep(haze_near, haze_far, dist), smoothstep(far_full, far_gone, dist));
}

void fragment() {
	vec3 col;
	if (part > 0.5) {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		col = (part > 1.5 ? mark_color : edge_color) * mix(0.7, 1.0, facing * facing);
	} else {
		float front = max(local_normal.z, 0.0);
		float top = max(local_normal.y, 0.0);
		col = body_color + tint * face_tint * front + vec3(0.62, 0.6, 0.85) * top_gloss * top * top;
	}
	ALBEDO = mix(col, fog_color, haze);
}
