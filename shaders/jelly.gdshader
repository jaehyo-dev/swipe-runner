shader_type spatial;
// 빛나는 푸딩 슬라임 (ART_BIBLE.md 2-1, 2-2, 2-3 아쿠아 민트): 맑은 반투명 + 두께 색(밝은 테두리 → 진한 청록 띠 → 맑은 민트)
// + 작고 진한 숨 쉬는 심지 + 속이 빈 기포 + 긴 반사광·작은 반사점 + 일렁이는 표면 + 몸 뒤가 살짝 휘어 보이는 굴절.
// 글로우 기준(HDR 0.9)을 넘는 곳은 테두리·반사광·심지뿐이다. 몸 색이 0.9를 넘으면 몸 전체가 번져 안개처럼 뿌옇게 된다.
// 기포·반사광은 따로 메시를 겹치지 않고 여기서 몸 좌표(뒤에서 본 x·y)로 그린다.
// 굴절: 화면 텍스처(불투명 물체까지 그린 화면)를 휘어 읽고 직접 섞으므로 ALPHA는 1이다.
render_mode unshaded, depth_draw_always, cull_back, fog_disabled;  // 안개: 뒤 화면(screen_tex)에 이미 들어 있어 한 번 더 씌우면 몸이 보라·회색으로 탁해진다

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// --- 조절하기 쉬운 값 ---
uniform float alpha_center = 0.5;   // 가운데 투명도 (0 = 완전 투명, 1 = 불투명). 낮을수록 뒤가 또렷이 비침
uniform float alpha_edge = 0.92;    // 가장자리 투명도 (프레넬)
uniform float core_strength = 1.0;  // 심지 세기
uniform float core_size = 0.1;      // 심지 반지름 (m). 0.1이면 보이는 지름이 몸 높이(0.8)의 약 1/3
uniform float core_breath = 0.18;   // 심지가 박자에 맞춰 숨 쉬는 폭 (0 = 고정)
uniform float rim_start = 0.8;      // 테두리 빛이 시작하는 프레넬 값 (클수록 테두리가 얇아짐, 0.85를 넘으면 점선처럼 깨짐)
uniform float ground_dark = 0.55;   // 바닥에 닿은 부분이 진해지는 정도 (액체가 아래로 모인 느낌)
uniform float refraction = 0.025;   // 굴절 세기 (화면 비율, 0 = 휘지 않음)
uniform float ripple = 0.006;       // 표면 물결 높이
uniform float bubble_strength = 0.8;
uniform vec3 transmit_tint : source_color = vec3(0.18, 1.0, 0.58);  // 몸을 통과해 보이는 어두운 뒤 화면이 물드는 색 (보라 배경이 회색·초록이 아니라 하늘빛 민트로 섞이게)
uniform vec3 line_tint : source_color = vec3(0.6, 1.0, 1.0);        // 비쳐 보이는 밝은 길 선의 색: 위 색을 곱하면 파랑이 빠져 진한 초록 줄이 되므로 하늘빛 민트로 따로 칠한다

// --- 색 (ART_BIBLE.md 팔레트) ---
uniform vec3 rim_color : source_color = vec3(0.784, 1.0, 0.980);   // #C8FFFA 얇은 가장자리
uniform float rim_energy = 2.1;     // 테두리 발광: 화면에서 가장 밝아야 함 (장애물 선 1.6~1.8보다 위)
uniform vec3 band_color : source_color = vec3(0.184, 0.592, 0.659); // #2F97A8 안쪽 띠
uniform vec3 mint : source_color = vec3(0.525, 0.890, 0.902);      // #86E3E6 몸 (아쿠아 민트)
uniform vec3 core_color : source_color = vec3(0.918, 1.0, 1.0);     // #EAFFFF 속빛

// --- runner.gd가 매 프레임 넣는 값 ---
uniform float height = 1.0;  // 메시 높이 (아래 0 ~ 위 height)
uniform float radius = 0.42; // 메시 가장 넓은 반지름 (반사광 위치를 몸 크기에 맞춤)
uniform float lean = 0.0;    // 정수리가 옆으로 밀린 거리 (레인 이동 출렁임)
uniform float drag = 0.0;    // 슬라이드: 정수리가 뒤(+z)로 끌린 거리 (앞쪽이 낮고 길게 나감)
uniform float beat = 0.0;    // 달리기 박자 위상
uniform float flat_bottom = 1.0;  // 바닥 평평함: 1 = 땅에 닿은 평평한 푸딩 바닥, 0 = 공중의 둥근 물방울 바닥 (ART_BIBLE.md 2-4)
uniform float foot_ratio = 0.8;   // runner.gd FOOT_RATIO: 메시의 평평한 바닥 반지름 비율
uniform float widest_t = 0.375;   // runner.gd WIDEST_T: 가장 넓은 높이 비율 (이 아래만 둥글게 바꾼다)

varying vec3 lp;  // 출렁이기 전 몸 좌표: 반사광·기포가 표면에 붙어 같이 흔들린다

float ring(float d, float r, float w) {
	return smoothstep(r - w * 2.0, r - w, d) * (1.0 - smoothstep(r, r + w, d));
}

void vertex() {
	// 바닥 둥글기: 메시는 평평한 바닥(반지름 = 가장 넓은 폭 × foot_ratio)으로 만들어져 있다.
	// 가장 넓은 곳 아래의 반지름을 R·(k + (1-k)·√(1-c²))로 바꾼다. k = foot_ratio·flat_bottom, k=0이면 아래가 타원으로 둥글게 닫힌다.
	// runner.gd _blob_point와 같은 식이라 flat_bottom = 1이면 메시 그대로다. 바닥 원판은 반지름이 k배로 줄어 한 점이 된다.
	float wh = widest_t * height;
	if (VERTEX.y < wh) {
		float c = 1.0 - VERTEX.y / wh;
		float s = sqrt(max(1.0 - c * c, 0.0));
		float k = foot_ratio * flat_bottom;
		VERTEX.xz *= (k + (1.0 - k) * s) / (foot_ratio + (1.0 - foot_ratio) * s);
		// 회전체 법선 (cosθ, -dr/dy, sinθ)에 s·wh를 곱한 꼴: 맨 아래(s=0)에서도 나눗셈 없이 아래를 향한다
		vec2 d = VERTEX.xz / max(length(VERTEX.xz), 1e-5);
		NORMAL = normalize(vec3(d.x * s * wh, -radius * (1.0 - k) * c, d.y * s * wh));
	}
	lp = VERTEX;
	float vy = clamp(VERTEX.y / height, 0.0, 1.0);
	// 표면 물결: 서로 다른 두 물결을 겹쳐 계속 일렁이게. 바닥은 땅에 붙어 있게 움직이지 않는다
	float ang = atan(VERTEX.z, VERTEX.x);
	float w = sin(ang * 3.0 + vy * 9.0 + TIME * 5.0) * 0.6 + sin(ang * 5.0 - vy * 6.0 - TIME * 6.5) * 0.4;
	VERTEX += NORMAL * w * ripple * smoothstep(0.05, 0.3, vy);
	// 높이별 기울기: 바닥은 그대로, 위로 갈수록 크게 밀린다 (푸딩처럼 위가 늦게 따라옴)
	VERTEX.x += lean * vy * vy;
	VERTEX.z += drag * vy * vy;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float vy = clamp(lp.y / height, 0.0, 1.0);
	float f = 1.0 - clamp(dot(n, VIEW), 0.0, 1.0);  // 0 = 정면(두꺼움), 1 = 가장자리(얇음)

	// 두께 색: 가운데 민트 → 진한 청록 띠 → 밝은 테두리
	// 위에서 내려다보는 정수리가 띠 색으로 칠해져 뚜껑처럼 보이지 않게, 띠는 옆면(위로 갈수록 약하게)에만 둔다
	float band = smoothstep(0.3, 0.68, f) * (1.0 - smoothstep(0.55, 0.9, vy));
	// 맑은 몸은 어두운 보라 바닥과 섞이며 파랑이 올라오므로, 파랑을 살짝 빼서 화면에서 #86E3E6 색조(약 182°)로 읽히게 한다
	vec3 col = mix(mint * vec3(0.88, 1.03, 0.96), band_color, band);
	// 바닥에 닿은 부분: 진한 청록으로 모인다
	float ground = (1.0 - smoothstep(0.0, 0.22, vy)) * ground_dark;
	col = mix(col, band_color * 0.75, ground);
	float rim = smoothstep(rim_start, rim_start + 0.14, f);  // 끝까지 가파르면 1픽셀 안에서 켜졌다 꺼져 점선처럼 깨짐
	col = mix(col, rim_color * rim_energy, rim);

	// 심지: 몸 가운데 약간 아래의 작고 진한 빛, 박자에 맞춰 아주 약하게 밝아졌다 어두워짐
	vec2 cq = vec2(lp.x, lp.y - 0.32 * height) / core_size;
	float core = exp(-dot(cq, cq)) * (1.0 - f) * core_strength * (1.0 + core_breath * sin(beat));
	col += core_color * core;

	// 반사광: 표면 물결을 따라 살짝 흔들리는 좌표
	// 반사광 위치는 v0.2.2 몸(반지름 0.42, 높이 1) 좌표로 맞춰 그려서 몸 크기가 바뀌어도 같은 자리에 붙는다
	vec2 bp = vec2(lp.x * 0.42 / radius, lp.y / height);
	vec2 p = bp + 0.012 * vec2(sin(TIME * 4.0 + bp.y * 12.0), cos(TIME * 3.3 + bp.x * 10.0));
	// 왼쪽 위 길게 휜 반사광 (가장 밝은 점)
	vec2 a = p - vec2(0.04, 0.47);
	float ang = atan(a.y, a.x);
	float streak = (1.0 - smoothstep(0.014, 0.028, abs(length(a) - 0.25))) * smoothstep(1.65, 1.95, ang) * (1.0 - smoothstep(2.7, 3.0, ang));
	// 반대쪽 오른쪽 아래의 작은 반사점
	float dot_hl = 1.0 - smoothstep(0.018, 0.028, length(p - vec2(0.2, 0.33)));
	float hl = max(streak, dot_hl * 0.85);

	// 기포 4개: 크기·속도·위치 제각각, 아래에서 떠올라 몸 위쪽에서 사라진다
	float bub = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float t = fract(TIME * (0.18 + 0.07 * fract(fi * 0.618)) + fi * 0.29);
		float r = 0.045 + 0.022 * fract(fi * 0.71 + 0.3);
		vec2 c = vec2((fract(fi * 0.618 + 0.15) - 0.5) * 0.86 * radius + 0.02 * sin(TIME * 2.0 + fi * 3.0), mix(0.1, 0.72, t) * height);
		float fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.7, 1.0, t));
		float d = length(lp.xy - c);
		bub = max(bub, ring(d, r, max(0.006, fwidth(d))) * fade);  // 화면에서 1픽셀보다 얇아지지 않게
	}
	// 기포 테두리는 글로우 기준(0.9) 아래 색: 번지면 흰 얼룩이 된다
	col = mix(col, rim_color * 0.85, bub * bubble_strength);
	col += vec3(hl) * 2.4;

	// 굴절: 가운데(두꺼운 곳)일수록 뒤 화면을 법선 쪽으로 휘어 읽는다 (렌즈처럼)
	vec3 back = texture(screen_tex, SCREEN_UV - n.xy * refraction * (1.0 - f)).rgb;
	float lum = max(back.g, back.b);
	vec3 behind = mix(back * transmit_tint, line_tint * lum, smoothstep(0.35, 0.8, lum));  // 어두운 배경은 물들이고 밝은 선은 밝기만 살려 하늘빛 민트로
	float alpha = clamp(mix(alpha_center, alpha_edge, smoothstep(0.5, 0.95, f)) + ground * 0.4 + min(core, 1.0) * 0.5 + hl + bub * 0.5, 0.0, 1.0);
	ALBEDO = mix(behind, col, alpha);
}
