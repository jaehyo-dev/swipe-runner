extends TestCase
## 속도에 따른 색 진하기: 데이터 파일 값, 선형 섞기, 색상 차이·대비·색약 시뮬레이션 자동 검사 (t = 0, 0.5, 1).

const TS := [0.0, 0.5, 1.0]
const KINDS := ["block", "low", "high"]
const HERO := Color("86e3e6")  # 주인공 몸 (ART_BIBLE.md 2-3). 팔레트에 없다: 주인공 색은 바뀌지 않는다
const HERO_PEAK := 2.1 * 1.0   # 주인공 가장자리 최대 밝기 (jelly.gdshader rim_color #C8FFFA × rim_energy 2.1)
## Machado 2009 적록색약 (선형 RGB에 곱한다, review/v0.4.1/read_sheet.py와 같은 값)
const DEUTAN := [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]


func _screen(c: Color) -> Color:
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


## WCAG 상대 밝기 (입력은 sRGB 화면 값)
func _luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _hue_gap(a: Color, b: Color) -> float:
	var gap := absf(a.h - b.h) * 360.0
	return minf(gap, 360.0 - gap)


func _deutan(c: Color) -> Color:
	var l := c.srgb_to_linear()
	var out := Color()
	for i in 3:
		out[i] = clampf(DEUTAN[i][0] * l.r + DEUTAN[i][1] * l.g + DEUTAN[i][2] * l.b, 0.0, 1.0)
	return out.linear_to_srgb()


func _gray(c: Color) -> Color:
	var v := _luminance(c)
	return Color(v, v, v, 1.0).linear_to_srgb()


func test_표의_값이_데이터_파일_양끝과_같음() -> void:
	var want0 := {"sky_top": "0b0a24", "horizon": "3a2470", "floor": "241a4a", "rail": "8fa8ff", "block": "bfdcff", "low": "ffd25a", "high": "ff5fd2"}
	var want1 := {"sky_top": "0a0030", "horizon": "8a1fd6", "floor": "3a0f6e", "rail": "7b5cff", "block": "4fa0ff", "low": "ffa000", "high": "ff0fa0"}
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	for key in want0:
		assert_eq(at0[key].to_html(false), want0[key], key)
		assert_eq(at1[key].to_html(false), want1[key], key)
	assert_eq(at0["rail_energy"], 1.0)
	assert_eq(at1["rail_energy"], 1.6)


func test_사이_값은_선형으로_섞임() -> void:
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	var mid := SpeedPalette.at(0.25)
	for key in at0:
		if key == "rail_energy":
			assert_true(is_equal_approx(mid[key], lerpf(at0[key], at1[key], 0.25)))
		else:
			assert_true(mid[key].is_equal_approx(at0[key].lerp(at1[key], 0.25)), key)


func test_장애물_세_색의_색상_차이는_60도_이상() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for part in ["", "_edge"]:
			for pair in [["block", "low"], ["low", "high"], ["high", "block"]]:
				var gap := _hue_gap(_screen(c[pair[0] + part]), _screen(c[pair[1] + part]))
				assert_true(gap >= 60.0, "t=%f %s%s %s: %f도" % [t, pair[0], part, pair[1], gap])


func test_같은_색_계열이고_채도와_깊이만_오름() -> void:
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	for key in ["block", "low", "high", "rail"]:
		var limit := 30.0 if key == "rail" else 10.0  # 난간은 보라빛 파랑 안에서 움직인다 (사용자 표)
		assert_true(_hue_gap(at0[key], at1[key]) < limit, "%s 색상 유지 %f도" % [key, _hue_gap(at0[key], at1[key])])
		assert_true(at1[key].s > at0[key].s, "%s 채도가 오름" % key)


## 민트는 주인공 전용 (ART_BIBLE.md 색 규칙). 테두리는 HDR 값과, 화면에서 잘린 값 둘 다 본다
func test_주인공과_다른_모든_요소의_색상_차이는_30도_이상() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for key: String in c:
			if key == "rail_energy":
				continue
			for color: Color in [c[key], _screen(c[key])]:
				assert_true(_hue_gap(HERO, color) >= 30.0, "t=%f %s: %f도" % [t, key, _hue_gap(HERO, color)])
	for fixed in ["8c80ff", "060817"]:  # 빛 결, 바닥 바탕: 셰이더에 고정된 색
		assert_true(_hue_gap(HERO, Color(fixed)) >= 30.0, fixed)


func test_장애물_테두리와_바닥_대비는_3대1_이상() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for kind in KINDS:
			var ratio := _contrast(_screen(c[kind + "_edge"]), c["floor"])
			assert_true(ratio >= 3.0, "t=%f %s %f" % [t, kind, ratio])


func test_주인공과_바닥_대비는_3대1_이상() -> void:
	for t in TS:
		var ratio := _contrast(HERO, SpeedPalette.at(t)["floor"])
		assert_true(ratio >= 3.0, "t=%f %f" % [t, ratio])


## 흑백·색약에서도 테두리가 바닥과 구분되면 형태(키 큰 기둥 / 낮은 턱 / 떠 있는 막대)로 읽힌다
func test_흑백과_적록색약에서도_테두리가_바닥에서_보임() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for kind in KINDS:
			for view: Callable in [_gray, _deutan]:
				var ratio := _contrast(view.call(_screen(c[kind + "_edge"])), view.call(c["floor"]))
				assert_true(ratio >= 3.0, "t=%f %s %f" % [t, kind, ratio])


func test_밝기_순서는_진해져도_유지() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		var rail: Color = c["rail"]
		var road_peak: float = maxf(rail.r, maxf(rail.g, rail.b)) * c["rail_energy"]
		for kind in KINDS:
			var edge: Color = c[kind + "_edge"]
			var peak: float = maxf(edge.r, maxf(edge.g, edge.b))
			assert_true(peak < HERO_PEAK, "t=%f %s 테두리 %f < 주인공" % [t, kind, peak])
			assert_true(peak > 1.6, "t=%f %s 테두리 %f: 빛나는 난간 상한(1.6)보다 밝음" % [t, kind, peak])
			assert_true(road_peak < peak, "t=%f 난간 %f < %s 테두리 %f" % [t, road_peak, kind, peak])
