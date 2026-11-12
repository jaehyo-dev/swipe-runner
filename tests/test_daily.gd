extends TestCase
## 오늘의 판(DAILY) 규칙·기록·배치 테스트. 시각은 직접 넣는다 (테스트용 시간 덮어쓰기).

const PATH := "user://test_daily.cfg"
const BEST_PATH := "user://test_daily_best.txt"
const D1 := DailyRecord.FIRST_DAY  # 2026-11-12
## 2026-11-12 00:00 UTC (= 한국 시간 오전 9시)
const LAUNCH := 20769 * 86400


func _fresh(today := D1) -> DailyRecord:
	DirAccess.remove_absolute(PATH)
	return DailyRecord.new(PATH, today)


func test_날짜는_UTC_자정에_바뀜() -> void:
	assert_eq(DailyRecord.day_of(LAUNCH), D1)
	assert_eq(DailyRecord.day_of(LAUNCH - 1), D1 - 1, "한국 시간 오전 8:59:59는 전날")
	assert_eq(DailyRecord.day_of(LAUNCH + 86399), D1)
	assert_eq(DailyRecord.number(D1), 1, "출시일이 #1")
	assert_eq(DailyRecord.number(D1 + 11), 12)


func test_씨앗은_날짜로_정해지고_날마다_다름() -> void:
	var seen := {}
	for d in range(D1, D1 + 365):
		var s := DailyRecord.seed_of(d)
		assert_eq(s, DailyRecord.seed_of(d), "같은 날 같은 씨앗")
		assert_true(s > 0 and s < (1 << 31), "0이 아닌 31비트")
		seen[s] = true
	assert_eq(seen.size(), 365, "1년 동안 겹치지 않음")


func test_남은_시간() -> void:
	assert_eq(DailyRecord.countdown(LAUNCH), "24H 0M")
	assert_eq(DailyRecord.countdown(LAUNCH + 86400 - (3 * 3600 + 12 * 60)), "3H 12M")
	assert_eq(DailyRecord.countdown(LAUNCH + 86399), "0H 1M", "1초 남아도 0분으로 보이지 않음")


func test_첫날_도전_횟수와_연속_참여() -> void:
	var r := _fresh()
	assert_eq(r.streak_on(D1), 0)
	assert_false(r.played(D1))
	r.start(D1)
	r.start(D1)
	assert_eq(r.tries, 2)
	assert_eq(r.streak_on(D1), 1, "하루에 여러 판도 +1")
	assert_true(r.played(D1))
	var again := DailyRecord.new(PATH, D1)
	assert_eq(again.tries, 2, "다시 열어도 남음")
	assert_eq(again.streak_on(D1), 1)


func test_이어지는_날과_빠진_날() -> void:
	var r := _fresh()
	r.start(D1)
	r.start(D1 + 1)
	r.start(D1 + 2)
	assert_eq(r.streak_on(D1 + 2), 3)
	assert_eq(r.streak_on(D1 + 3), 3, "다음 날 아직 안 했어도 이어질 수 있음")
	assert_eq(r.streak_on(D1 + 4), 0, "하루 빠지면 0")
	r.start(D1 + 4)
	assert_eq(r.streak_on(D1 + 4), 1, "0부터 다시 +1")
	assert_eq(r.tries, 1, "새 날은 도전 횟수도 새로")


func test_오늘_최고_점수만_남고_날짜별로_따로() -> void:
	var r := _fresh()
	r.start(D1)
	r.update(500)
	r.save()
	r.start(D1)
	r.update(300)
	r.save()
	assert_eq(r.best, 500, "낮은 점수는 남기지 않음")
	r.start(D1 + 1)
	assert_eq(r.best, 0, "새 날은 기록 없음")
	assert_eq(r.previous, 0)
	r.update(200)
	r.save()
	assert_eq(DailyRecord.new(PATH, D1).best, 500)
	assert_eq(DailyRecord.new(PATH, D1 + 1).best, 200)


func test_자정을_넘긴_판은_시작한_날짜의_기록() -> void:
	var r := _fresh()
	r.start(D1)  # 23:59에 시작
	r.update(100)
	# 자정이 지나도 판은 계속된다: 점수는 시작한 날(D1)에
	r.update(900, 10.0)
	r.save()
	assert_eq(DailyRecord.new(PATH, D1).best, 900)
	assert_eq(DailyRecord.new(PATH, D1 + 1).best, 0)
	r.start(D1 + 1)  # 다음 판은 새 날
	assert_eq(r.day, D1 + 1)
	assert_eq(r.best, 0)


func test_오래된_날짜_기록은_정리() -> void:
	var r := _fresh()
	r.start(D1)
	r.update(50)
	r.save()
	r.start(D1 + DailyRecord.KEEP_DAYS + 1)
	var file := ConfigFile.new()
	file.load(PATH)
	assert_false(file.has_section_key("best", str(D1)), "30일 넘은 기록은 지움")
	assert_true(file.has_section_key("tries", str(D1 + DailyRecord.KEEP_DAYS + 1)))


func test_일반_최고_점수와_섞이지_않음() -> void:
	DirAccess.remove_absolute(BEST_PATH)
	var normal := BestRecord.new(BEST_PATH)
	normal.update(1000)
	normal.save()
	var r := _fresh()
	assert_eq(r.best, 0, "일반 기록이 오늘의 판에 보이지 않음")
	r.start(D1)
	r.update(5000)
	r.save()
	assert_eq(BestRecord.new(BEST_PATH).best, 1000, "오늘의 판 점수가 일반 기록을 바꾸지 않음")
	assert_eq(FileAccess.get_file_as_string(BEST_PATH), "1000")


func test_깨진_파일은_빈_기록() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("[best]\n20769=\"abc\"\n[streak]\ncount=-3\nlast_day=1.5\n")
	file.close()
	var r := DailyRecord.new(PATH, D1)
	assert_eq(r.best, 0)
	assert_eq(r.streak, 0)
	assert_eq(r.last_day, -1)


func test_배치는_프레임_간격과_전역_난수에_영향받지_않음() -> void:
	var s := DailyRecord.seed_of(D1)
	seed(1)
	var a := DailyRecord.layout_hash(s, 40, 1.0 / 60.0)
	seed(999)
	randi()
	var b := DailyRecord.layout_hash(s, 40, 1.0 / 144.0)
	var c := DailyRecord.layout_hash(s, 40, 1.0 / 24.0)
	assert_eq(a, b, "60Hz와 144Hz")
	assert_eq(a, c, "느린 기기 24Hz")
	assert_true(a != DailyRecord.layout_hash(DailyRecord.seed_of(D1 + 1), 40), "다른 날은 다른 배치")


## 고정 지문: 패턴·방울 규칙이나 값(data/difficulty.json, data/score.json)이 바뀌면 그날 판이 바뀐다.
## 의도한 변경이면 값을 고치고 CHANGELOG에 "오늘의 판 배치 바뀜"이라고 적는다.
func test_고정_지문() -> void:
	assert_eq(DailyRecord.layout_hash(DailyRecord.seed_of(D1)), "99e7039b5e52de92")
