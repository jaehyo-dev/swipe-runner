class_name DailyRecord
extends BestRecord
## 오늘의 판(DAILY) 규칙과 기록 (화면과 분리, 자동 테스트 대상).
## 날짜는 UTC(한국 시간 오전 9시에 새 판). 같은 날짜면 기기와 관계없이 같은 씨앗 → 같은 장애물·방울 배치.
## 기록은 일반 최고 점수(BestRecord.PATH)와 다른 파일: 날짜별 최고 점수·도전 횟수, 연속 참여(STREAK)와 마지막으로 한 날.
## 판은 시작한 날짜의 기록이다: 플레이 중에 날짜가 바뀌어도 다음 start()까지 day는 그대로다.

const DAILY_PATH := "user://daily.cfg"
const DAY := 86400
const FIRST_DAY := 20769  # 2026-11-12 (UTC, 1970-01-01부터 센 날) = DAILY #1
const MOD := 1 << 31
const KEEP_DAYS := 30     # 날짜별 기록은 최근 이만큼만 남긴다 (파일이 끝없이 커지지 않게)

## 지금 기록하는(보이는) 날짜. best·tries는 이 날짜의 값
var day := -1
var tries := 0
var streak := 0      # last_day까지 이어진 연속 참여 일수
var last_day := -1   # 마지막으로 판을 시작한 날짜
var _file := ConfigFile.new()


func _init(path := DAILY_PATH, today := 0) -> void:
	super(path, 0)
	_file.load(path)  # 없거나 깨진 파일은 빈 기록으로 본다
	streak = _read("streak", "count", 0)
	last_day = _read("streak", "last_day", -1)
	view(today)


## 기록에서 0 이상의 정수를 읽는다. 숫자가 아니면 fallback
func _read(section: String, key: String, fallback: int) -> int:
	var value: Variant = _file.get_value(section, key, fallback)
	return value if value is int and value >= 0 else fallback


## 보일 날짜를 고른다 (오늘의 판 시작 화면). 앞 판의 아직 안 쓴 기록은 먼저 저장한다
func view(today: int) -> void:
	save()
	day = today
	best = _read("best", str(today), 0)
	tries = _read("tries", str(today), 0)
	_saved = best
	previous = best


## 한 판을 시작한다: 오늘 도전 횟수 +1, 연속 참여는 어제 했으면 +1·오늘 이미 했으면 그대로·빠졌으면 1
func start(today: int) -> void:
	if today != day:
		view(today)
	tries += 1
	if last_day != today:
		streak = streak + 1 if last_day == today - 1 else 1
		last_day = today
	_file.set_value("tries", str(day), tries)
	for section in ["best", "tries"]:
		if _file.has_section(section):
			for key in _file.get_section_keys(section):
				if key.to_int() < today - KEEP_DAYS:
					_file.erase_section_key(section, key)
	_file.set_value("streak", "count", streak)
	_file.set_value("streak", "last_day", last_day)
	_file.save(_path)  # 저장소가 막힌 브라우저에서도 게임은 계속된다
	begin_run()


## 최고 점수는 이번 판을 시작한 날짜(day)에 쓴다
func _write() -> bool:
	_file.set_value("best", str(day), best)
	return _file.save(_path) == OK


## 화면의 연속 참여: 어제나 오늘 했으면 이어지고, 하루 넘게 빠졌으면 0
func streak_on(today: int) -> int:
	return streak if last_day >= today - 1 else 0


func played(today: int) -> bool:
	return last_day == today


## 유닉스 시각(초, UTC)의 날짜 번호
static func day_of(unix: float) -> int:
	return floori(unix / DAY)


## "DAILY #n"의 n
static func number(of_day: int) -> int:
	return of_day - FIRST_DAY + 1


## 날짜의 씨앗. 31비트 안에서만 곱해 곱이 2^62를 넘지 않는다 (네이티브·웹 모두 같은 정수 계산). 0은 "무작위"라 피한다
static func seed_of(of_day: int) -> int:
	var x := posmod(of_day, MOD)
	for i in 3:
		x = (x * 1103515245 + 12345) % MOD
		x ^= x >> 13
	return x | 1


## 다음 판까지 남은 시간 "3H 12M" (분은 올림)
static func countdown(unix: float) -> String:
	var minutes := ceili(((day_of(unix) + 1) * DAY - unix) / 60.0)
	return "%dH %dM" % [minutes / 60, minutes % 60]


## 앞 bars마디의 배치 지문(기기 비교·변화 감지용). 장애물 {박, 레인, 종류, 줄}과 계획된 방울 줄 {박, 레인, x, y}.
## 방울 x·y는 cos 등 수학 라이브러리의 마지막 자리 차이를 피해 1e-4로 반올림한다.
## 시작 단계는 0 (오늘의 판은 개발용 ?bpm과 관계없이 같은 판을 기준으로 한다). dt: 화면 프레임 간격 (결과에 영향이 없어야 한다)
static func layout_hash(seed_value: int, bars := 150, dt := 1.0 / 60.0) -> String:
	var last := float(bars * BeatClock.BEATS_PER_BAR)
	var parts := PackedStringArray()
	var pattern := BeatPattern.new(seed_value, ObstacleField.FIRST_BEAT)
	var item := pattern.next()
	while item["beat"] < last:
		parts.append("%s %d %d %s" % [item["beat"], item["lane"], item["kind"], item["shape"]])
		item = pattern.next()
	var ladder := MusicLadder.new()
	var field := ObstacleField.new(seed_value, ladder)
	field.keep_trails = true
	var t := 0.0
	while field.trails.is_empty() or field.trails[-1]["orbs"][-1]["beat"] < last:
		t += dt
		ladder.plan(t, AudioManager.SCHEDULE_LEAD, AudioManager.SCHEDULE_MIN, true)
		field.step(ladder.distance_at(t), ladder.spawn_distance_at(t))
	for trail in field.trails:
		for orb: Dictionary in trail["orbs"]:
			if orb["beat"] < last:
				parts.append("%s %d %.4f %.4f" % [orb["beat"], orb["lane"], orb["x"], orb["y"]])
	return "\n".join(parts).sha256_text().left(16)


## 출시일부터 날짜 days개의 지문 표 ("#1 2026-11-12 seed hash" 한 줄씩) + 전체 지문. 기기 비교용 (tools/daily_hash.gd, 웹 ?dailyhash=1)
static func hash_report(days: int) -> String:
	var lines := PackedStringArray()
	for i in days:
		var d := FIRST_DAY + i
		lines.append("#%d %s %d %s" % [number(d), Time.get_date_string_from_unix_time(d * DAY), seed_of(d), layout_hash(seed_of(d))])
	lines.append("ALL " + "\n".join(lines).sha256_text().left(16))
	return "\n".join(lines)
