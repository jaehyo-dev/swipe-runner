shader_type spatial;
// 하늘 돔. ProceduralSky는 값이 바뀔 때마다 반사 큐브맵을 다시 그려 렉이 생겨서, 재질 값만 바꾸는 돔으로 그린다.
// 그림은 ProceduralSky와 같은 공식: 지평선에서 위로 갈수록 top 색. 지평선 아래도 horizon 색(바닥과 안개가 덮는다).
render_mode unshaded, cull_front, fog_disabled;

uniform vec3 top : source_color;
uniform vec3 horizon : source_color;
uniform float curve = 0.18;

varying vec3 dir;

void vertex() {
	dir = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	float c = 1.0 - acos(clamp(normalize(dir).y, 0.0, 1.0)) / (PI * 0.5);
	ALBEDO = mix(horizon, top, clamp(1.0 - pow(1.0 - c, 1.0 / curve), 0.0, 1.0));
}
