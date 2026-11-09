shader_type spatial;
// 어두운 바닥의 반사 (Compatibility 렌더러는 실제 반사가 없다): 바닥 아래로 뒤집은 메시를 카메라 시선을 따라 바닥 면으로 눌러 그린다.
// 화면에서는 진짜 거울상과 같은 자리에 보이고, 깊이는 바닥 위라서 불투명한 바닥을 그대로 둘 수 있다 (젤리가 바닥을 비춰 보는 화면 복사가 그대로 유지됨).
// 색은 재질 값이라 속도에 따라 바꿀 수 있다. 꼭짓점 색 COLOR.r이 몸통(0)과 빛(1)을, COLOR.g가 그림자를 고르고 COLOR.a가 불투명도다.
// 렉 줄이기: 반사는 가까운 것만 그린다. 먼 것은 꼭짓점을 한 점으로 모아 칠할 화소가 없다. COLOR.b가 1인 바닥 흔적(빛 웅덩이, 접지 그림자)은 멀어도 그린다.
render_mode unshaded, cull_disabled, depth_draw_never, world_vertex_coords;

uniform vec3 body_color : source_color = vec3(0.07);
uniform vec3 edge_color : source_color = vec3(1.0);
const vec3 SHADOW_COLOR = vec3(0.0009, 0.0, 0.005);  // #030010 (선형 값)
uniform float falloff = 0.8;     // 바닥에서 멀어질수록 빨리 흐려지는 정도
uniform float reflect_on = 1.0;  // 0이면 반사 끄기 (프레임이 밀릴 때). 바닥 흔적은 남는다
uniform float far_cut = -30.0;   // 이 z보다 먼 반사는 그리지 않는다
uniform float far_full = -26.0;  // 여기서부터 온전히 보인다
uniform float wall_stretch = 0.75;  // 2칸 벽이 양옆으로 벌어지는 양 (main.gd)
uniform float wall_shadow = 0.88;   // 2칸 벽의 접지 그림자가 넓어지는 비율 (main.gd)

varying float below;
varying float shown;

void vertex() {
	shown = max(COLOR.b, reflect_on * smoothstep(far_cut, far_full, MODEL_MATRIX[3].z));
	below = max(-VERTEX.y, 0.0);
	float off = VERTEX.x - MODEL_MATRIX[3].x;  // 그림자 타원은 가운데 점이 있어 벌리지 않고 넓힌다
	VERTEX.x += INSTANCE_CUSTOM.g * (COLOR.b > 0.5 ? off * wall_shadow : sign(off) * wall_stretch * length(MODEL_MATRIX[0].xyz));
	vec3 cam = CAMERA_POSITION_WORLD;
	VERTEX = cam + (VERTEX - cam) * cam.y / (cam.y - VERTEX.y);
	VERTEX.y = 0.008;
	if (shown <= 0.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = mix(mix(body_color, edge_color, COLOR.r), SHADOW_COLOR, COLOR.g);
	ALPHA = COLOR.a * exp(-below * falloff) * shown;
}
