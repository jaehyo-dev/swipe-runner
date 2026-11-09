class_name BrightnessOrder
extends RefCounted
## 밝기 순서 표 (자동 테스트와 review 기록이 같은 계산을 쓴다, ART_BIBLE.md 4장). 값은 HDR의 가장 센 채널.


static func peak(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## 진하기 t의 단계별 밝기. mark·edge는 가장 빡빡하게 비교하려고 어두운 기호·밝은 테두리를 고른다. rail은 단계 빛남이 가장 셀 때 값이다.
## 파란 기둥은 빛나는 테두리까지 포함해 "테두리" 칸으로 읽는다. pillar_body는 몸통 면만의 값(기록용)이다.
static func table(t: float, hero_peak: float) -> Dictionary:
	var c := SpeedPalette.at(t)
	var mark := INF
	var edge := 0.0
	for kind in ["low", "high"]:
		mark = minf(mark, peak(c[kind + "_mark"]))
	for kind in ["block", "low", "high"]:
		edge = maxf(edge, peak(c[kind + "_edge"]))
	return {
		"hero": hero_peak,
		"mark": mark,
		"edge": edge,
		"pillar_body": peak(c["block_body"]),
		"rail": peak(c["rail"]) * StageLight.energy(c["rail_energy"], 1.0),
		"rail_rest": peak(c["rail"]) * c["rail_energy"],
		"streak": c["streak_alpha"],
		"ground": maxf(maxf(peak(c["sky_top"]), peak(c["horizon"])), peak(c["floor"])),
	}
