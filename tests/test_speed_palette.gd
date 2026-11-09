extends TestCase
## 속도에 따른 색 진하기: 데이터 파일 값, 선형 섞기, 색상 차이·대비·색약 시뮬레이션 자동 검사 (t = 0, 0.5, 1).

const TS := [0.0, 0.5, 1.0]
const KINDS := ["block", "low", "high"]
const HERO := Color("86e3e6")  # 주인공 몸 (ART_BIBLE.md 2-3). 팔레트에 없다: 주인공 색은 바뀌지 않는다
const HERO_PEAK := 2.4 * 1.0   # 주인공 가장자리 최대 밝기 (jelly.gdshader rim_color #C8FFFA × rim_energy 2.4)
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
	var want0 := {"sky_top": "05040d", "horizon": "241650", "floor": "0c0a1c", "rail": "7b5cff", "body": "120e24", "block": "2fb8ff", "low": "ff9a1f", "high": "ff2fa8"}
	var want1 := {"sky_top": "05040d", "horizon": "3d1880", "floor": "0e0a24", "rail": "7b5cff", "body": "120e24", "block": "0faeff", "low": "ff9405", "high": "ff0c9c"}
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	for key in want0:
		assert_eq(at0[key].to_html(false), want0[key], key)
		assert_eq(at1[key].to_html(false), want1[key], key)
	assert_eq(at0["laser_count"], 4.0, "레이저 t=0 4줄")
	assert_eq(at1["laser_count"], 6.0, "레이저 t=1 6줄")
	assert_true(at1["laser_energy"] > at0["laser_energy"], "레이저가 강해짐")
	assert_true(at1["streak_count"] > at0["streak_count"] and at1["streak_length"] > at0["streak_length"], "빛 줄기가 많고 길어짐")


func test_사이_값은_선형으로_섞임() -> void:
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	var mid := SpeedPalette.at(0.25)
	for key in at0:
		if at0[key] is float:
			assert_true(is_equal_approx(mid[key], lerpf(at0[key], at1[key], 0.25)), key)
		else:
			assert_true(mid[key].is_equal_approx(at0[key].lerp(at1[key], 0.25)), key)


func test_장애물_세_색의_색상_차이는_60도_이상() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for part in ["", "_edge", "_mark"]:
			for pair in [["block", "low"], ["low", "high"], ["high", "block"]]:
				var gap := _hue_gap(_screen(c[pair[0] + part]), _screen(c[pair[1] + part]))
				assert_true(gap >= 60.0, "t=%f %s%s %s: %f도" % [t, pair[0], part, pair[1], gap])


func test_장애물_색은_같은_계열이고_채도만_오름() -> void:
	var at0 := SpeedPalette.at(0.0)
	var at1 := SpeedPalette.at(1.0)
	for key in KINDS:
		assert_true(_hue_gap(at0[key], at1[key]) < 10.0, "%s 색상 유지 %f도" % [key, _hue_gap(at0[key], at1[key])])
		assert_true(at1[key].s > at0[key].s, "%s 채도가 오름" % key)


## 민트는 주인공 전용 (ART_BIBLE.md 색 규칙). HDR 값과 화면에서 잘린 값 둘 다 본다.
## 옆 장애물 파랑은 사용자 표의 색(200도)이라 예외: 색상 15도 이상 + 주인공보다 채도가 높아 구분된다
func test_주인공과_다른_모든_요소의_색상_차이() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for key: String in c:
			if c[key] is float:
				continue
			for color: Color in [c[key], _screen(c[key])]:
				var gap := _hue_gap(HERO, color)
				if key.begins_with("block"):
					assert_true(gap >= 15.0 and color.s > HERO.s, "t=%f %s: %f도, 채도 %f" % [t, key, gap, color.s])
				else:
					assert_true(gap >= 30.0, "t=%f %s: %f도" % [t, key, gap])
	assert_true(_hue_gap(HERO, Color("060817")) >= 30.0, "길 밖 바닥: 셰이더에 고정된 색")


## 레이저는 장애물 색과 헷갈리지 않게 채도를 한 단계 낮춘다
func test_레이저는_장애물보다_채도가_낮음() -> void:
	for t in TS:
		var c := SpeedPalette.at(t)
		for laser in ["laser_blue", "laser_pink"]:
			for kind in KINDS:
				assert_true(c[laser].s < c[kind].s, "t=%f %s < %s" % [t, laser, kind])


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


## 주인공 > 장애물 기호 > 테두리 > 레이저·난간 > 빛 줄기 > 바닥·하늘 (HDR 가장 센 채널, 번쩍임이 가장 셀 때 기준)
func test_밝기_순서는_진해져도_번쩍여도_유지() -> void:
	for t in TS:
		var row := BrightnessOrder.table(t, HERO_PEAK)
		assert_true(row["hero"] > row["mark"], "t=%f 주인공 > 기호: %s" % [t, row])
		assert_true(row["mark"] > row["edge"], "t=%f 기호 > 테두리: %s" % [t, row])
		assert_true(row["edge"] > row["stage"], "t=%f 테두리 > 레이저·난간: %s" % [t, row])
		assert_true(row["laser_rest"] > row["streak"], "t=%f 평소 레이저 > 빛 줄기: %s" % [t, row])
		assert_true(row["streak"] > row["ground"], "t=%f 빛 줄기 > 바닥·하늘: %s" % [t, row])
