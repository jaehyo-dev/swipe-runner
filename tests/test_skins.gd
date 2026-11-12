extends TestCase
## 젤리 스킨: 해금 조건·진행도·기존 기록 반영·저장 형식, 셰이더 값, 장애물·방울과 색 겹침 (v0.11.0).

const PATH := "user://test_skins.cfg"
## 주인공과 비교하는 색: 장애물 색·테두리(진하기 0·1), 난간, 방울 테. 장애물 앞면 기호는 어두운 면 안의 작은 그림이라 넣지 않는다 (review/v0.11.0/colors.md)
const OTHERS := ["block", "low", "high", "block_edge", "low_edge", "high_edge", "rail"]
const ORB_RIM := Color("c9b8ff")


func _fresh() -> SkinBook:
	DirAccess.remove_absolute(PATH)
	return SkinBook.new(PATH)


func test_스킨_8종_순서와_처음엔_민트만() -> void:
	var names := SkinBook.list().map(func(s: Dictionary) -> String: return s["name"])
	assert_eq(names, ["MINT", "STRAWBERRY", "LEMON", "GRAPE", "SODA", "NIGHT", "AURORA", "GOLD"])
	var book := _fresh()
	assert_eq(book.unlocked, ["mint"] as Array[String])
	assert_eq(book.selected, "mint")


func test_조건마다_목표에_닿으면_열림() -> void:
	var book := _fresh()
	assert_eq(book.finish_run(4999, 29, 499, 7, 2), [] as Array[String], "모두 목표 바로 아래")
	assert_eq(book.finish_run(5000, 1, 1, 8, 3), ["strawberry", "lemon", "grape", "soda", "aurora"] as Array[String])
	assert_eq(book.finish_run(10000, 0, 0, 1, 0), ["night", "gold"] as Array[String], "10000점 한 판이면 8000점 스킨도")
	assert_eq(book.finish_run(20000, 0, 0, 1, 0), [] as Array[String], "이미 열린 스킨은 다시 알리지 않음")


func test_PERFECT와_방울은_판을_넘어_누적되고_점수와_배수는_한_판() -> void:
	var book := _fresh()
	for i in 3:
		book.finish_run(3000, 10, 200, 5, 1)
	assert_eq(book.stats["perfects"], 30)
	assert_eq(book.stats["orbs"], 600)
	assert_eq(book.stats["score"], 3000, "점수는 합치지 않는다")
	assert_eq(book.stats["multiplier"], 5)
	assert_true(book.is_unlocked("strawberry") and book.is_unlocked("grape"))
	assert_false(book.is_unlocked("lemon"))


func test_조건_진행도_글자() -> void:
	var book := _fresh()
	book.finish_run(1200, 18, 212, 3, 1)
	assert_eq(book.condition_text("strawberry"), "PERFECTS 18/30")
	assert_eq(book.condition_text("lemon"), "SCORE 5000")
	assert_eq(book.condition_text("grape"), "ORBS 212/500")
	assert_eq(book.condition_text("soda"), "DAILY STREAK 1/3")
	assert_eq(book.condition_text("aurora"), "×8 IN ONE RUN")
	assert_eq(book.condition_text("gold"), "SCORE 10000")


func test_기존_기록으로_바로_열리고_여러_번_불러도_같음() -> void:
	var book := _fresh()
	assert_eq(book.absorb_records(8200, 3), ["lemon", "soda", "night"] as Array[String])
	assert_eq(book.absorb_records(8200, 3), [] as Array[String])
	assert_eq(book.absorb_records(100, 0), [] as Array[String], "더 낮은 값은 무시")
	var again := SkinBook.new(PATH)
	assert_true(again.is_unlocked("night"), "absorb가 열면 바로 저장")
	assert_eq(again.stats["score"], 8200)


func test_오늘의_판_최고는_남은_날짜_중_가장_높은_점수() -> void:
	var path := "user://test_skins_daily.cfg"
	DirAccess.remove_absolute(path)
	var daily := DailyRecord.new(path, DailyRecord.FIRST_DAY)
	daily.start(DailyRecord.FIRST_DAY)
	daily.update(6000, 0.0)
	daily.save()
	daily.start(DailyRecord.FIRST_DAY + 1)
	daily.update(300, 0.0)
	daily.save()
	assert_eq(DailyRecord.new(path, DailyRecord.FIRST_DAY + 1).best_ever(), 6000)
	assert_eq(daily.streak, 2)
	DirAccess.remove_absolute(path)


func test_고른_스킨_저장_잠긴_스킨은_못_고름() -> void:
	var book := _fresh()
	assert_false(book.select("gold"))
	book.finish_run(5000, 0, 0, 1, 0)
	assert_true(book.select("lemon"))
	var again := SkinBook.new(PATH)
	assert_eq(again.selected, "lemon")
	assert_eq(again.unlocked, ["mint", "lemon"] as Array[String])


func test_깨진_값은_처음_상태로_열린_목록은_줄지_않음() -> void:
	var file := ConfigFile.new()
	file.set_value("meta", "version", 1)
	file.set_value("stats", "perfects", "많이")
	file.set_value("stats", "orbs", -4)
	file.set_value("skins", "unlocked", ["gold", "없는스킨", 7])
	file.set_value("skins", "selected", "night")
	file.save(PATH)
	var book := SkinBook.new(PATH)
	assert_eq(book.stats["perfects"], 0)
	assert_eq(book.stats["orbs"], 0)
	assert_true(book.is_unlocked("gold"), "저장된 열린 스킨은 점수가 0이어도 그대로")
	assert_false(book.is_unlocked("night"))
	assert_eq(book.selected, "mint", "잠긴 스킨이 골라져 있으면 처음 스킨")
	var text := FileAccess.open(PATH, FileAccess.WRITE)
	text.store_string("")  # 반쯤 쓰다 끊긴 파일 (문법 오류 파일은 엔진이 오류를 찍어 테스트에서 뺀다. 그때도 load가 실패해 같은 길)
	text.close()
	assert_eq(SkinBook.new(PATH).unlocked, ["mint"] as Array[String])


func test_저장_형식_버전과_더_새_형식은_덮어쓰지_않음() -> void:
	var book := _fresh()
	book.finish_run(10, 1, 1, 1, 0)
	var file := ConfigFile.new()
	file.load(PATH)
	assert_eq(file.get_value("meta", "version"), SkinBook.FORMAT)
	file.set_value("meta", "version", SkinBook.FORMAT + 1)
	file.set_value("stats", "orbs", 999)
	file.save(PATH)
	SkinBook.new(PATH).finish_run(10, 1, 1, 1, 0)
	file.load(PATH)
	assert_eq(file.get_value("stats", "orbs"), 999, "다음 버전 파일은 읽기만")


func test_셰이더_값_몸_색은_글로우_기준_아래_민트는_v0_10_그대로() -> void:
	for item: Dictionary in SkinBook.list():
		var p := SkinBook.shader_params(item)
		var lin: Color = p["mint"].srgb_to_linear()
		assert_true(maxf(lin.r, maxf(lin.g, lin.b)) <= SkinBook.BODY_MAX + 0.001, item["name"])
		assert_true(p["pattern"] >= 0, "%s 무늬 이름" % item["name"])
		assert_true(absf(p["mint"].h - Color(item["body"]).h) < 0.01, "%s 색조 유지" % item["name"])
	var mint := SkinBook.shader_params(SkinBook.list()[0])
	assert_eq(mint["mint"], Color("86e3e6"))
	assert_eq(mint["rim_color"], Color("c8fffa"))
	assert_eq(mint["band_color"], Color("2f97a8"))
	assert_eq(mint["pattern"], 0)
	var locked := SkinBook.shader_params(SkinBook.list()[5], true)
	assert_eq(locked["pattern"], 0)
	assert_eq(locked["core_strength"], 0.0)


## 밝기 순서: 어두운 NIGHT도 테두리 빛(가장 센 채널 × 2.4)이 장애물 기호보다 밝다
func test_어두운_스킨도_주인공이_가장_밝음() -> void:
	for item: Dictionary in SkinBook.list():
		var p := SkinBook.shader_params(item)
		var hero: float = BrightnessOrder.peak(p["rim_color"]) * p["rim_energy"]
		for t in [0.0, 0.5, 1.0]:
			var row := BrightnessOrder.table(t, hero)
			assert_true(row["hero"] > row["mark"], "%s t=%f %s" % [item["name"], t, row])


## 주인공과 장애물·난간·방울: 색상 30도 이상, 또는 밝기 대비 1.5 이상, 또는 (색상 15도 이상 + 상대가 더 진함: ART_BIBLE 파랑 예외)
func test_스킨과_장애물_방울_색_겹침() -> void:
	for item: Dictionary in SkinBook.list():
		var hero := Color(item["body"])
		for t in [0.0, 1.0]:
			var c := SpeedPalette.at(t)
			var others := {"orb_rim": ORB_RIM}
			for key: String in OTHERS:
				others[key] = c[key]
			for key: String in others:
				var gap := BrightnessOrder.skin_gap(hero, others[key])
				assert_true(gap["ok"], "%s ↔ %s t=%f: %s" % [item["name"], key, t, gap])


## 메인 화면 글자 자리: 휴대폰·9:16·PC·거의 정사각형 창에서 줄끼리, 젤리와 겹치지 않고 화면 안 (젤리 자리는 _fit_camera와 같은 카메라 계산)
func test_메인_화면_글자_자리가_겹치지_않음() -> void:
	# 크기별 {화면(720 기준 좌표), 웅덩이 앞 끝, 젤리 사각형}: 카메라 계산 값 (review/v0.11.0/README.md 레이아웃 표)
	var cases := [
		[Vector2(720, 1558), 0.71, Rect2(0, 0.58, 0, 0.09)],   # 390x844
		[Vector2(720, 1280), 0.75, Rect2(0, 0.60, 0, 0.11)],   # 9:16
		[Vector2(2276, 1280), 0.70, Rect2(0, 0.59, 0, 0.09)],  # PC 1280x720
		[Vector2(1138, 1280), 0.68, Rect2(0, 0.58, 0, 0.08)],  # 800x900
	]
	var line := TitleScreen.LINE_SIZE * 1.6
	for c: Array in cases:
		var size: Vector2 = c[0]
		var r: Rect2 = c[2]
		var half := 85.0 if size.x < 1000.0 else 70.0  # 젤리 반폭(px): 세로 화면 약 166px 폭 (390x844 캡처 90px)
		var jelly := Rect2(size.x * 0.5 - half, r.position.y * size.y, half * 2.0, r.size.y * size.y)
		var at := TitleScreen.layout(c[1] * size.y, jelly, size)
		var label := str(size)
		assert_true(at["name"] >= jelly.end.y, "%s 이름은 젤리 아래 %s" % [label, at])
		assert_true(at["dots"] + TitleScreen.DOTS_ROW <= at["start"], "%s 점 < 시작" % label)
		assert_true(at["start"] + line <= at["daily"], "%s 시작 < DAILY" % label)
		assert_true(at["daily"] + TitleScreen.DAILY_ROW <= size.y - TitleScreen.START_FLOOR + 0.5, "%s 화면 안" % label)
		var guide := Rect2(at["guide_right"] - TitleScreen.ICON_COLUMN - TitleScreen.TEXT_COLUMN if at["guide_side"] else size.x * 0.5 - (TitleScreen.ICON_COLUMN + TitleScreen.TEXT_COLUMN) * 0.5, at["guide_top"], TitleScreen.ICON_COLUMN + TitleScreen.TEXT_COLUMN, TitleScreen.GUIDE_ROW * 3.0)
		assert_false(guide.intersects(jelly), "%s 안내와 젤리 %s %s" % [label, guide, jelly])
		assert_true(guide.position.x >= 0.0, "%s 안내가 화면 안" % label)
		assert_true(guide.position.y >= TitleScreen.BEST_TOP + line or at["guide_side"], "%s 안내는 BEST 아래" % label)
