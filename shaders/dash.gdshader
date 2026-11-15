shader_type spatial;
// 레인 경계 빛 대시 (MultiMesh 하나). 줄 z는 main.gd가 쓰고, 박 밝기와 옆을 지날 때의 반짝임은 셰이더에서 계산한다.
// 불투명이라 젤리 속으로 비쳐 보이고, 먼 줄은 크기가 0으로 줄어 안개 속으로 사라진다.
// v0.12.1: 먼 대시는 화면 최소 폭까지 넓히고 그만큼 어둡게(밝기 합은 그대로), 윗면 가장자리는 화면 미분(fwidth)으로 바닥 색에 녹인다.
render_mode unshaded;

uniform vec3 color : source_color = vec3(1.0);
uniform float pulse = 0.0;       // 박마다 1 → 0 (main.gd)
uniform float appear = 1.0;      // 재시작 때 0 → 1: 박 격자가 새 자리로 옮겨 가는 순간을 가린다
uniform float sparkle_on = 0.0;  // 달리는 동안만 1 (멈춘 화면에서 줄이 계속 빛나지 않게)
uniform float base_energy = 0.55;
uniform float pulse_energy = 0.5;
uniform float sparkle_energy = 0.3;
uniform float max_energy = 1.0;  // 평소 빛의 상한
uniform float stage_add = 0.0;   // 음악 단계가 오를 때 0.3초 더하는 빛 (main.gd). 더해도 장애물 테두리보다 어둡다
uniform float dash_length = 1.2;  // 속도에 맞춰 길어진다 (main.gd)
uniform float fog_near = 24.75;  // 주인공 앞 이 거리부터 줄어들기 시작 (장애물과 같은 안개, main.gd)
uniform float fog_far = 27.0;    // 이 거리에서 사라짐
uniform float half_width = 0.035; // 메시 폭의 절반 (main.gd DASH_SIZE)
uniform float min_pixels = 1.5;   // 대시 폭의 화면 최소 크기(픽셀)
uniform float edge_pixels = 1.25; // 가장자리를 녹이는 폭(픽셀)
uniform vec3 edge_bg : source_color = vec3(0.047, 0.039, 0.11);  // 바닥 색 #0C0A1C

varying float glow;
varying vec2 local;  // 윗면 안 자리: x는 폭의 절반 = 1, z는 길이의 절반 = 1

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	local = vec2(sign(VERTEX.x), sign(VERTEX.z));
	float pixel = 2.0 * length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz) / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x);  // 1픽셀의 세계 크기
	float widen = max(min_pixels * pixel / (2.0 * half_width), 1.0);
	VERTEX.x *= widen;
	VERTEX.z *= dash_length;
	VERTEX *= appear * (1.0 - smoothstep(fog_near, fog_far, -origin.z));
	float beside = 1.0 - smoothstep(0.1, 0.8, abs(origin.z));  // 줄이 주인공(z=0) 옆을 지나는 순간
	glow = (min(base_energy + pulse_energy * pulse + sparkle_energy * sparkle_on * beside, max_energy) + stage_add) / widen;
}

void fragment() {
	vec2 d = (1.0 - abs(local)) / max(fwidth(local) * edge_pixels, vec2(1e-4));  // 가장자리까지 픽셀 수 (보간된 ±1 자리)
	ALBEDO = mix(edge_bg, color * glow, clamp(min(d.x, d.y), 0.0, 1.0));
}
