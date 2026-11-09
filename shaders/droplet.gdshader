shader_type spatial;
// 레인 경계 박자 물방울 (MultiMesh 하나). 줄 z는 main.gd가 프레임마다 넣고, 부풂·반짝임·빛남은 셰이더에서 계산한다.
// 불투명이라 젤리 속으로 비쳐 보이고, 먼 줄은 크기가 0으로 줄어 안개 속으로 사라진다.
render_mode unshaded;

uniform vec3 color : source_color = vec3(1.0);
uniform float pulse = 1.0;       // 박마다 1 → 1.15 → 1 (main.gd)
uniform float appear = 1.0;      // 재시작 때 0 → 1: 박 격자가 새 자리로 옮겨 가는 순간을 가린다
uniform float flash = 0.0;       // 음악 단계가 오를 때 1 → 0
uniform float sparkle_on = 0.0;  // 달리는 동안만 1 (멈춘 화면에서 줄이 계속 빛나지 않게)
uniform float base_energy = 1.0;
uniform float sparkle_energy = 0.45;
uniform float flash_energy = 0.45;
uniform float max_energy = 1.5;  // 밝기 순서: 어떤 순간에도 장애물 선보다 어둡게
uniform float fade_near = 42.0;  // 카메라에서 이 거리부터 줄어들기 시작
uniform float fade_far = 60.0;   // 이 거리에서 사라짐

varying float glow;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);  // 박 줄 1, 반 박 줄 BeatRows.SMALL_SCALE
	float dist = length(CAMERA_POSITION_WORLD - origin);
	VERTEX *= pulse * appear * (1.0 - smoothstep(fade_near, fade_far, dist));
	float beside = 1.0 - smoothstep(0.1, 0.8, abs(origin.z));  // 줄이 주인공(z=0) 옆을 지나는 순간
	glow = min(base_energy + sparkle_energy * sparkle_on * beside * size * size + flash_energy * flash, max_energy);
}

void fragment() {
	float facing = dot(normalize(NORMAL), VIEW);
	ALBEDO = color * glow * mix(0.55, 1.0, facing * facing);
}
