shader_type spatial;
// 빛 조각 (MultiMesh 풀 하나). 자리·크기·색은 조각이 살아 있는 동안 main.gd가 쓴다 (MultiMesh 사용자 값은 half-float라 시각을 담을 수 없다).
// 가산 혼합이라 젤리보다 뒤에 그려야(render_priority) 젤리에 덮이지 않는다.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
}
