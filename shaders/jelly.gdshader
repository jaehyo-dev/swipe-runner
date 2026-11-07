shader_type spatial;
// 반투명 젤리: 진한 민트 몸통(아래가 더 진함) + 프레넬 림 라이트 + 위쪽 작은 하이라이트 반점.
// 색이 흰색으로 날아가지 않게 몸통 밝기는 1 아래로 두고, 발광(1 넘는 값)은 가장자리 림에만 준다.
render_mode unshaded, depth_draw_always;

uniform vec3 mint : source_color = vec3(0.498, 0.878, 0.784);
uniform vec3 rim_color : source_color = vec3(0.75, 1.0, 0.93);
uniform float rim_energy = 1.25;
uniform float bottom_dark = 0.55;      // 아래쪽 몸통 밝기 (1 = 위와 같음)
uniform float height = 1.0;            // 메시 높이 (아래 0 ~ 위 height)
uniform float highlight = 1.0;         // 하이라이트 반점 세기 (발은 0)
uniform float alpha_center = 0.93;     // 가운데 투명도 (가장자리로 갈수록 진해짐)

varying float vy;

void vertex() {
	vy = clamp(VERTEX.y / height, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.5);
	vec3 body = mint * mix(bottom_dark, 1.0, smoothstep(0.0, 0.7, vy));
	// 하이라이트: 카메라 쪽 위 왼쪽을 향한 면에 작은 반점 하나
	float spot = smoothstep(0.92, 0.95, dot(n, normalize(vec3(-0.35, 0.45, 0.82)))) * smoothstep(0.5, 0.58, vy) * (1.0 - smoothstep(0.66, 0.74, vy)) * highlight;
	vec3 col = body + rim_color * rim_energy * f + vec3(spot);
	ALBEDO = col;
	ALPHA = clamp(mix(alpha_center, 1.0, f) + spot, 0.0, 1.0);
}
