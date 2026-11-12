class_name BrightnessOrder
extends RefCounted
## 밝기 순서 표 (자동 테스트와 review 기록이 같은 계산을 쓴다, ART_BIBLE.md 4장). 값은 HDR의 가장 센 채널.


const MAIN := preload("res://scripts/main.gd")


static func peak(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## 진하기 t의 단계별 밝기. mark·edge는 가장 빡빡하게 비교하려고 어두운 기호·밝은 테두리를 고른다. rail은 단계 빛남이 가장 셀 때 값이다.
## 파란 기둥은 빛나는 테두리까지 포함해 "테두리" 칸으로 읽는다. pillar_body는 몸통 면만의 값(기록용)이다.
static func table(t: float, hero_peak: float) -> Dictionary:
	var c := SpeedPalette.at(t)
	var mark := INF
	var edge := 0.0
	var edge_min := INF
	for kind in ["low", "high"]:
		mark = minf(mark, peak(c[kind + "_mark"]))
	for kind in ["block", "low", "high"]:
		edge = maxf(edge, peak(c[kind + "_edge"]))
		edge_min = minf(edge_min, peak(c[kind + "_edge"]))
	return {
		"hero": hero_peak,
		"mark": mark,
		"edge": edge,
		"edge_min": edge_min,  # 빛 방울과는 가장 어두운 테두리로 비교한다
		"pillar_body": peak(c["block_body"]),
		"orb": MAIN.ORB_ENERGY,  # 빛 방울 평소 (#F4F0FF의 가장 센 채널 1.0 × 세기)
		"orb_peak": MAIN.ORB_ENERGY + MAIN.ORB_PULSE_ENERGY,  # 박에 밝아질 때
		"rail": peak(c["rail"]) * StageLight.energy(c["rail_energy"], 1.0),
		"rail_rest": peak(c["rail"]) * c["rail_energy"],
		"streak": c["streak_alpha"],
		"ground": maxf(maxf(peak(c["sky_top"]), peak(c["horizon"])), peak(c["floor"])),
	}


## 스킨 몸 색과 다른 요소(장애물·난간·방울)의 구분 (v0.11.0, tests/test_skins.gd·review/v0.11.0/colors.md).
## 통과: 색상 30도 이상, 또는 밝기(WCAG) 대비 1.5 이상, 또는 색상 15도 이상 + 상대가 더 진함(ART_BIBLE 4장 파랑 예외). HDR 값은 화면처럼 1에서 자른다
static func skin_gap(hero: Color, other: Color) -> Dictionary:
	var o := Color(minf(other.r, 1.0), minf(other.g, 1.0), minf(other.b, 1.0))
	var hue := absf(hero.h - o.h) * 360.0
	hue = minf(hue, 360.0 - hue)
	var la := _luminance(hero)
	var lb := _luminance(o)
	var contrast := (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
	return {"hue": snappedf(hue, 0.1), "contrast": snappedf(contrast, 0.01), "ok": hue >= 30.0 or contrast >= 1.5 or (hue >= 15.0 and o.s > hero.s)}


static func _luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
