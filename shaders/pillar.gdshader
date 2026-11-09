shader_type spatial;
// 파란 기둥의 반투명 몸통: 뒤 장애물이 비쳐 보이게 깊이를 기록하지 않는다. 테두리는 block.gdshader(불투명)로 먼저 그려져 또렷하다.
// 볼록한 상자에 뒷면을 잘라 내므로 한 화소에 기둥 하나당 한 겹만 쌓인다. 그래서 뒤 기둥은 앞 기둥을 통해 더 흐리게 보인다.
render_mode unshaded, fog_disabled, depth_draw_never, cull_back;

uniform vec3 body_color : source_color = vec3(0.11, 0.435, 0.69);
uniform vec3 fog_color : source_color = vec3(0.2);
uniform float body_alpha = 0.55;
uniform float top_gloss = 0.24;     // 윗면 반사 (block.gdshader와 같은 값)
uniform float corner_gloss = 0.3;   // 둥근 모서리의 은은한 반사
uniform float haze_near = 6.0;      // 아래 네 값은 block.gdshader와 같게 유지한다
uniform float haze_far = 16.0;
uniform float fog_near = 24.75;     // 주인공 앞 이 거리부터 안개 속에서 진해진다 (main.gd가 매 프레임: 보이는 시간 기준)
uniform float fog_far = 27.0;       // 이 거리부터는 안개 색: 툭 나타나지 않게 (생성은 더 먼 곳)
uniform float wall_stretch = 0.75;  // main.gd가 레인 폭의 절반을 넣는다

varying float haze;
varying vec3 local_normal;

void vertex() {
	VERTEX.x += sign(VERTEX.x) * INSTANCE_CUSTOM.g * wall_stretch;  // 2칸 벽: 양옆만 벌려 둥근 모서리와 테두리 굵기를 그대로 둔다
	local_normal = NORMAL;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	haze = max(INSTANCE_CUSTOM.r * smoothstep(haze_near, haze_far, dist), smoothstep(fog_near, fog_far, -(MODEL_MATRIX * vec4(VERTEX, 1.0)).z));
}

void fragment() {
	float top = max(local_normal.y, 0.0);
	vec3 n = abs(normalize(local_normal));
	float corner = 1.0 - max(n.x, max(n.y, n.z));
	// 반사는 불투명도로 나눠 둔다: 몸통만 비치고 반사는 불투명할 때와 같은 세기로 남는다
	vec3 gloss = vec3(0.62, 0.6, 0.85) * (top_gloss * top * top + corner_gloss * corner) / body_alpha;
	ALBEDO = mix(body_color + gloss, fog_color, haze);
	ALPHA = body_alpha;
}
