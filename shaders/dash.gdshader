shader_type spatial;
// 레인 경계 빛 대시 (MultiMesh 하나). 줄 z는 main.gd가 쓰고, 박 밝기와 옆을 지날 때의 반짝임은 셰이더에서 계산한다.
// 불투명이라 젤리 속으로 비쳐 보이고, 먼 줄은 크기가 0으로 줄어 안개 속으로 사라진다.
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
uniform float fade_near = 62.0;  // 카메라에서 이 거리부터 줄어들기 시작
uniform float fade_far = 85.0;   // 이 거리에서 사라짐

varying float glow;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = length(CAMERA_POSITION_WORLD - origin);
	VERTEX.z *= dash_length;
	VERTEX *= appear * (1.0 - smoothstep(fade_near, fade_far, dist));
	float beside = 1.0 - smoothstep(0.1, 0.8, abs(origin.z));  // 줄이 주인공(z=0) 옆을 지나는 순간
	glow = min(base_energy + pulse_energy * pulse + sparkle_energy * sparkle_on * beside, max_energy) + stage_add;
}

void fragment() {
	ALBEDO = color * glow;
}
