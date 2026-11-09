shader_type spatial;
// 유리 바닥의 반사 흉내 (Compatibility 렌더러는 실제 반사가 없다): 바닥 아래로 뒤집은 메시를 카메라 시선을 따라 바닥 면으로 눌러 그린다.
// 화면에서는 진짜 거울상과 같은 자리에 보이고, 깊이는 바닥 위라서 불투명한 바닥을 그대로 둘 수 있다 (젤리가 바닥을 비춰 보는 화면 복사가 그대로 유지됨).
// 색은 재질 값이라 속도에 따라 바꿀 수 있다. 꼭짓점 색 COLOR.r이 면(0)과 선(1)을 고르고 COLOR.a가 불투명도다.
render_mode unshaded, cull_disabled, depth_draw_never, world_vertex_coords;

uniform vec3 glass_color : source_color = vec3(1.0);
uniform vec3 edge_color : source_color = vec3(1.0);
uniform float falloff = 1.1;  // 바닥에서 멀어질수록 빨리 흐려지는 정도

varying float below;

void vertex() {
	below = max(-VERTEX.y, 0.0);
	vec3 cam = CAMERA_POSITION_WORLD;
	VERTEX = cam + (VERTEX - cam) * cam.y / (cam.y - VERTEX.y);
	VERTEX.y = 0.008;
}

void fragment() {
	ALBEDO = mix(glass_color, edge_color, COLOR.r);
	ALPHA = COLOR.a * exp(-below * falloff);
}
