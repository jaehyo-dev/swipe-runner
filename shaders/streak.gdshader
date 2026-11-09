shader_type spatial;
// 카메라 옆으로 스쳐 지나가는 빛 줄기 (MultiMesh 하나). 자리는 인스턴스 원점과 이동 거리로 셰이더가 계산해 프레임마다 값을 쓰지 않는다.
// 불투명이다: 화면 복사에 들어가 젤리 굴절과 어긋나지 않는다. 색을 낮추면 안개 띠 위에 검은 점이 남으므로 굵기를 줄여 사라진다.
render_mode unshaded, world_vertex_coords, fog_disabled;

uniform float scroll = 0.0;       // 이동 거리 (main.gd)
uniform float streak_length = 2.0;
uniform float level = 0.3;        // 밝기
uniform float z_near = 6.0;       // 이 z까지 왔다가 z_near - z_range로 돌아간다
uniform float z_range = 60.0;
uniform float width = 0.018;

varying float shade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float z = z_near - z_range + mod(origin.z + scroll, z_range);
	float fade = smoothstep(z_near - z_range, z_near - z_range + 15.0, z) * (1.0 - smoothstep(z_near - 3.0, z_near, z));
	VERTEX = (VERTEX - origin) * vec3(width * fade, width * fade, streak_length) + vec3(origin.x, origin.y, z);
	shade = level;
}

void fragment() {
	ALBEDO = vec3(shade);
}
