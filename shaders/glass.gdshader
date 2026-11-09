shader_type spatial;
// 유리 면: 반투명(겹쳐 보이는 두 면을 합쳐 55~70%)이라 뒤 모서리와 안쪽 결이 살짝 비친다. 비스듬히 보이는 면은 조금 더 진하다.
// 멀리서는 면을 진하게 해서 안개 속에서도 키 큰 기둥 / 바닥에 붙은 턱 / 떠 있는 막대 실루엣이 먼저 읽힌다.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 tint : source_color = vec3(0.62, 0.86, 1.0);
uniform float body = 0.85;       // 면 밝기: 밝기 순서(난간·물방울 > 유리 면)를 지키는 값
uniform float near_alpha = 0.37; // 한 면의 불투명도 (앞뒤 두 면이 겹쳐 보인다: 1 - (1 - a)^2)
uniform float far_alpha = 0.45;
uniform float far_from = 12.0;   // 카메라 거리: 여기서부터 진해지기 시작
uniform float far_to = 34.0;     // 여기서 가장 진함

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = tint * (body + 0.25 * f);
	ALPHA = clamp(mix(near_alpha, far_alpha, smoothstep(far_from, far_to, length(VERTEX))) + 0.08 * f, 0.0, 1.0);
}
