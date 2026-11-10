shader_type spatial;
// 빛 방울 구슬 (MultiMesh 하나). 심은 연보라빛 흰색 #F4F0FF, 가장자리는 연보라 #C9B8FF로 은은하게 어두워진다.
// 밝기 순서: 장애물 테두리(1.7 이상) > 빛 방울(energy + pulse_energy) > 난간(단계 빛남 때도 1.6 이하). 자리·크기는 main.gd가 매 프레임 쓴다.
// 안개 거리에서는 대시처럼 크기가 0으로 줄어 안개 속에서 나타난다. 박마다 살짝 부풀었다 돌아온다 (대시와 같은 pulse).
render_mode unshaded;

uniform vec3 color : source_color = vec3(0.957, 0.941, 1.0);      // 심 #F4F0FF
uniform vec3 rim_color : source_color = vec3(0.788, 0.722, 1.0);  // 바깥 테 #C9B8FF: 흰 빛 줄기와 구분
uniform float energy = 1.62;
uniform float pulse = 0.0;          // 박마다 1 → 0 (main.gd, 대시와 같은 값)
uniform float pulse_grow = 0.25;    // 박에 커지는 비율 (1.0 → 1.25)
uniform float pulse_energy = 0.06;  // 박에 더 밝아지는 양
uniform float fog_near = 24.75;
uniform float fog_far = 27.0;

varying float glow;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX *= (1.0 - smoothstep(fog_near, fog_far, -origin.z)) * (1.0 + pulse_grow * pulse);
	glow = energy + pulse_energy * pulse;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// 가운데는 흰 심, 가장자리로 갈수록 연보라 테. 가장 센 채널은 가운데(glow)라 밝기 순서는 그대로
	ALBEDO = mix(rim_color, color, smoothstep(0.2, 0.75, facing)) * glow * mix(0.55, 1.0, facing);
}
