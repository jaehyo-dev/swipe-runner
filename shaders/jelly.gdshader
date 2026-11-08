shader_type spatial;
// 빛나는 푸딩 슬라임 (ART_BIBLE.md 2-1): 반투명 + 두께 색(밝은 테두리 → 진한 청록 띠 → 밝은 속빛)
// + 숨 쉬는 속빛 + 떠오르는 기포 + 긴 반사광·작은 반사점 + 일렁이는 표면 + 몸 뒤가 살짝 휘어 보이는 굴절.
// 기포·반사광은 따로 메시를 겹치지 않고 여기서 몸 좌표(뒤에서 본 x·y)로 그린다.
// 굴절: 화면 텍스처(불투명 물체까지 그린 화면)를 휘어 읽고 직접 섞으므로 ALPHA는 1이다.
render_mode unshaded, depth_draw_always, cull_back;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// --- 조절하기 쉬운 값 ---
uniform float alpha_center = 0.62;  // 가운데 투명도 (0 = 완전 투명, 1 = 불투명)
uniform float alpha_edge = 0.95;    // 가장자리 투명도 (프레넬)
uniform float core_strength = 1.15; // 속빛 세기
uniform float core_breath = 0.18;   // 속빛이 박자에 맞춰 숨 쉬는 폭 (0 = 고정)
uniform float refraction = 0.025;   // 굴절 세기 (화면 비율, 0 = 휘지 않음)
uniform float ripple = 0.006;       // 표면 물결 높이
uniform float bubble_strength = 0.8;
uniform vec3 transmit_tint : source_color = vec3(0.55, 1.0, 0.88);  // 몸을 통과해 보이는 뒤 화면이 물드는 색 (보라 배경이 회색으로 섞이지 않게)

// --- 색 (ART_BIBLE.md 팔레트) ---
uniform vec3 rim_color : source_color = vec3(0.749, 1.0, 0.929);   // #BFFFED 얇은 가장자리
uniform float rim_energy = 2.1;     // 테두리 발광: 화면에서 가장 밝아야 함 (장애물 선 1.6~1.8보다 위)
uniform vec3 band_color : source_color = vec3(0.247, 0.659, 0.580); // #3FA894 안쪽 띠
uniform vec3 mint : source_color = vec3(0.498, 0.878, 0.784);      // #7FE0C8 몸
uniform vec3 core_color : source_color = vec3(0.91, 1.0, 0.973);    // #E8FFF8 속빛

// --- runner.gd가 매 프레임 넣는 값 ---
uniform float height = 1.0;  // 메시 높이 (아래 0 ~ 위 height)
uniform float lean = 0.0;    // 정수리가 옆으로 밀린 거리 (레인 이동 출렁임)
uniform float beat = 0.0;    // 달리기 박자 위상

varying vec3 lp;  // 출렁이기 전 몸 좌표: 반사광·기포가 표면에 붙어 같이 흔들린다

float ring(float d, float r, float w) {
	return smoothstep(r - w * 2.0, r - w, d) * (1.0 - smoothstep(r, r + w, d));
}

void vertex() {
	lp = VERTEX;
	float vy = clamp(VERTEX.y / height, 0.0, 1.0);
	// 표면 물결: 서로 다른 두 물결을 겹쳐 계속 일렁이게. 바닥은 땅에 붙어 있게 움직이지 않는다
	float ang = atan(VERTEX.z, VERTEX.x);
	float w = sin(ang * 3.0 + vy * 9.0 + TIME * 5.0) * 0.6 + sin(ang * 5.0 - vy * 6.0 - TIME * 6.5) * 0.4;
	VERTEX += NORMAL * w * ripple * smoothstep(0.05, 0.3, vy);
	// 높이별 기울기: 바닥은 그대로, 위로 갈수록 크게 밀린다 (푸딩처럼 위가 늦게 따라옴)
	VERTEX.x += lean * vy * vy;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float vy = clamp(lp.y / height, 0.0, 1.0);
	float f = 1.0 - clamp(dot(n, VIEW), 0.0, 1.0);  // 0 = 정면(두꺼움), 1 = 가장자리(얇음)

	// 두께 색: 가운데 민트 → 진한 청록 띠 → 밝은 테두리
	// 위에서 내려다보는 정수리가 띠 색으로 칠해져 뚜껑처럼 보이지 않게, 띠는 옆면(위로 갈수록 약하게)에만 둔다
	float band = smoothstep(0.3, 0.68, f) * (1.0 - smoothstep(0.55, 0.9, vy));
	vec3 col = mix(mint * 1.1, band_color, band);
	col = mix(col, rim_color * rim_energy, smoothstep(0.7, 0.98, f));  // 너무 얇으면 가장자리가 점점이 깨져 보임

	// 속빛: 몸 가운데 약간 아래, 박자에 맞춰 아주 약하게 밝아졌다 어두워짐
	vec2 cq = vec2(lp.x / 0.3, (lp.y - 0.36 * height) / 0.26);
	float core = exp(-dot(cq, cq)) * (1.0 - f) * core_strength * (1.0 + core_breath * sin(beat));
	col += core_color * core;

	// 반사광: 표면 물결을 따라 살짝 흔들리는 좌표
	vec2 p = lp.xy + 0.012 * vec2(sin(TIME * 4.0 + lp.y * 12.0), cos(TIME * 3.3 + lp.x * 10.0));
	// 왼쪽 위 길게 휜 반사광 (가장 밝은 점)
	vec2 a = p - vec2(0.04, 0.47 * height);
	float ang = atan(a.y, a.x);
	float streak = (1.0 - smoothstep(0.014, 0.028, abs(length(a) - 0.25))) * smoothstep(1.65, 1.95, ang) * (1.0 - smoothstep(2.7, 3.0, ang));
	// 반대쪽 오른쪽 아래의 작은 반사점
	float dot_hl = 1.0 - smoothstep(0.018, 0.028, length(p - vec2(0.2, 0.33 * height)));
	float hl = max(streak, dot_hl * 0.85);

	// 기포 4개: 크기·속도·위치 제각각, 아래에서 떠올라 몸 위쪽에서 사라진다
	float bub = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float t = fract(TIME * (0.18 + 0.07 * fract(fi * 0.618)) + fi * 0.29);
		float r = 0.032 + 0.02 * fract(fi * 0.71 + 0.3);
		vec2 c = vec2((fract(fi * 0.618 + 0.15) - 0.5) * 0.36 + 0.02 * sin(TIME * 2.0 + fi * 3.0), mix(0.1, 0.72, t) * height);
		float fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.7, 1.0, t));
		bub = max(bub, ring(length(lp.xy - c), r, 0.009) * fade);
	}
	col = mix(col, core_color * 1.3, bub * bubble_strength);
	col += vec3(hl) * 2.4;

	// 굴절: 가운데(두꺼운 곳)일수록 뒤 화면을 법선 쪽으로 휘어 읽는다 (렌즈처럼)
	vec3 behind = texture(screen_tex, SCREEN_UV - n.xy * refraction * (1.0 - f)).rgb * transmit_tint;
	float alpha = clamp(mix(alpha_center, alpha_edge, smoothstep(0.5, 0.95, f)) + hl + bub * 0.3, 0.0, 1.0);
	ALBEDO = mix(behind, col, alpha);
}
