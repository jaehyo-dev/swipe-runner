shader_type spatial;
// 점 눈: 눈이 바라보는 방향(몸의 -z)이 카메라 쪽일 때만 그린다.
// 몸이 반투명이라, 이렇게 하지 않으면 뒷모습에서 눈이 몸을 통해 비쳐 보인다.
render_mode unshaded;

uniform vec3 color : source_color = vec3(0.071, 0.2, 0.18);  // #12332E

void fragment() {
	vec3 face = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	if (face.z < 0.15) {
		discard;  // 뷰 공간에서 +z가 카메라 쪽
	}
	ALBEDO = color;
}
