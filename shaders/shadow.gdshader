shader_type spatial;
// 발밑 (ART_BIBLE.md 2-2): 몸이 닿는 면 둘레의 짧고 진한 접촉 그림자 + 몸 둘레 바닥에 번지는 약한 빛 고리.
// 몸 아래 한가운데는 어둡게 둔다 (밝으면 몸이 떠 보임). r은 판 반지름(runner.gd SHADOW_SIZE/2 = 1.13m)을 1로 본 거리.
render_mode unshaded, depth_draw_never, fog_disabled;

uniform vec3 glow_color : source_color = vec3(0.525, 0.890, 0.902);  // 몸 아쿠아 민트 #86E3E6
uniform float glow_strength = 0.2;   // 빛 고리 세기 (주인공보다 훨씬 어둡게)
uniform float glow_inner = 0.46;     // 빛 고리가 시작하는 곳 (몸의 가장 넓은 폭 0.44 바로 바깥, 판 크기를 몸에 비례시켜 값은 그대로)
uniform float shadow_strength = 0.85;  // 접촉 그림자 진하기
uniform float shadow_edge = 0.4;     // 접촉 그림자가 진하게 유지되는 반지름 (몸 바닥 0.35보다 살짝 바깥)
uniform float shadow_fade = 0.07;    // 접촉 그림자가 흐려지는 폭 (짧을수록 또렷하게 붙어 보임)
// --- runner.gd가 점프 높이에 따라 넣는 값 (ART_BIBLE.md 2-4) ---
uniform float opacity = 1.0;  // 그림자·빛 고리 진하기 배율 (땅 1, 최고 높이 약 0.3)
uniform float soft = 0.0;     // 0 = 땅에 붙은 또렷한 그림자, 1 = 최고 높이의 부드럽게 번진 그림자

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = smoothstep(glow_inner, glow_inner + 0.12, r) * (1.0 - smoothstep(glow_inner + 0.12, 1.0, r)) * glow_strength * opacity;
	// 뜰수록 가장자리를 안팎으로 넓게 번지게 해서 까만 구멍처럼 또렷한 원이 남지 않게 한다
	float dark = (1.0 - smoothstep(shadow_edge - 0.15 * soft, shadow_edge + shadow_fade + 0.2 * soft, r)) * shadow_strength * opacity;
	ALBEDO = mix(glow_color, vec3(0.01, 0.0, 0.06), dark / max(dark + glow, 0.001));
	ALPHA = clamp(dark + glow, 0.0, 1.0);
}
