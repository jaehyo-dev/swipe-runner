class_name BrightnessOrder
extends RefCounted
## 밝기 순서 표 (자동 테스트와 review 기록이 같은 계산을 쓴다, ART_BIBLE.md 4장). 값은 HDR의 가장 센 채널.


static func peak(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## 진하기 t의 단계별 밝기. mark·edge는 세 종류 중 어두운 것(기호)·밝은 것(테두리)으로 가장 빡빡하게 비교하고, stage는 번쩍임이 가장 셀 때 값이다.
static func table(t: float, hero_peak: float) -> Dictionary:
	var c := SpeedPalette.at(t)
	var mark := INF
	var edge := 0.0
	for kind in ["block", "low", "high"]:
		mark = minf(mark, peak(c[kind + "_mark"]))
		edge = maxf(edge, peak(c[kind + "_edge"]))
	var laser_color := maxf(peak(c["laser_blue"]), peak(c["laser_pink"]))
	var laser_flash: float = laser_color * StageLight.energy(c["laser_energy"], StageLight.BAR_BOOST, 1.0, laser_color)
	return {
		"hero": hero_peak,
		"mark": mark,
		"edge": edge,
		"stage": maxf(laser_flash, maxf(StageLight.PEAK_MAX, peak(c["rail"]) * c["rail_energy"])),
		"laser_rest": laser_color * c["laser_energy"],
		"streak": c["streak_alpha"],
		"ground": maxf(maxf(peak(c["sky_top"]), peak(c["horizon"])), peak(c["floor"])),
	}
