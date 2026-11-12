class_name SaveData
extends RefCounted
## 플레이 횟수·소리 켜기/끄기·설정(음악·효과음 크기, 진동, 안내 다시 보기) 저장 (자동 테스트 대상). 최고 점수는 BestRecord가 따로 저장한다.
## v0.9.0에서 이름이 "스와이프 러너" → "SWIPE PULSE"로 바뀌며 user:// 폴더도 바뀐다(데스크톱·웹 모두 이름을 따른다). 옛 폴더의 파일을 복사해 온다 (migrate).

const PATH := "user://settings.cfg"
const OLD_NAME := "스와이프 러너"  # v0.8.2까지의 application/config/name
const GUIDE_RUNS := 3              # 조작 안내는 처음 이만큼의 판에만 보인다

var plays := 0
var muted := false
var music := 1.0       # 음악 크기 0~1 (설정 슬라이더)
var sfx := 1.0         # 효과음 크기 0~1
var vibration := true  # 진동 (기본 켬)
var guide_left := 0    # 설정의 SHOW GUIDE: 앞으로 이만큼의 판에 조작 안내를 다시 보인다
var graphics := "auto" # 설정의 GRAPHICS: QualityGuard.SETTINGS
var performance := false  # 설정의 PERFORMANCE: 왼쪽 위 성능 표시 (v0.11.2)

var _path: String


func _init(path := PATH) -> void:
	_path = path
	var file := ConfigFile.new()
	if file.load(path) != OK:  # 없거나 깨진 파일은 처음 상태로 본다
		return
	var count: Variant = file.get_value("play", "plays", 0)
	plays = maxi(count, 0) if count is int else 0
	var mute: Variant = file.get_value("sound", "muted", false)
	muted = mute is bool and mute
	music = _unit(file.get_value("sound", "music", 1.0))
	sfx = _unit(file.get_value("sound", "sfx", 1.0))
	var buzz: Variant = file.get_value("play", "vibration", true)
	vibration = buzz if buzz is bool else true
	var left: Variant = file.get_value("play", "guide_left", 0)
	guide_left = clampi(left, 0, GUIDE_RUNS) if left is int else 0
	var look: Variant = file.get_value("play", "graphics", "auto")
	graphics = look if look in QualityGuard.SETTINGS else "auto"
	var meter: Variant = file.get_value("play", "performance", false)
	performance = meter is bool and meter


## 0~1 크기 값. 숫자가 아니면 처음 값(1)
static func _unit(value: Variant) -> float:
	return clampf(float(value), 0.0, 1.0) if (value is float or value is int) else 1.0


## 다음 판 전에 조작 안내를 보일까
func shows_guide() -> bool:
	return plays < GUIDE_RUNS or guide_left > 0


## 설정의 SHOW GUIDE: 다음 GUIDE_RUNS판 동안 안내를 다시 보인다
func replay_guide() -> void:
	guide_left = GUIDE_RUNS
	save()


## 한 판을 시작했다
func count_play() -> void:
	plays += 1
	guide_left = maxi(guide_left - 1, 0)
	save()


func set_muted(on: bool) -> void:
	muted = on
	save()


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("play", "plays", plays)
	file.set_value("sound", "muted", muted)
	file.set_value("sound", "music", music)
	file.set_value("sound", "sfx", sfx)
	file.set_value("play", "vibration", vibration)
	file.set_value("play", "guide_left", guide_left)
	file.set_value("play", "graphics", graphics)
	file.set_value("play", "performance", performance)
	file.save(_path)  # 저장소가 막힌 브라우저(시크릿 창 등)에서도 게임은 계속된다


## 옛 이름의 user:// 폴더 (새 폴더 옆. 웹은 /userfs/godot/app_userdata/스와이프 러너)
static func old_user_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(OLD_NAME)


## old_dir의 파일을 new_dir로 복사한다. 새 폴더에 이미 있는 파일은 건드리지 않고, 옛 폴더도 지우지 않는다. 복사한 파일 수
static func migrate(old_dir: String, new_dir: String) -> int:
	if old_dir == new_dir or not DirAccess.dir_exists_absolute(old_dir):
		return 0
	DirAccess.make_dir_recursive_absolute(new_dir)
	var copied := 0
	for file in DirAccess.get_files_at(old_dir):
		var to := new_dir.path_join(file)
		# 임시 파일에 다 쓴 뒤 이름을 바꾼다: 복사가 중간에 끊겨 반쯤 쓴 기록이 남으면 다음에 다시 옮기지 못한다
		if not FileAccess.file_exists(to) and DirAccess.copy_absolute(old_dir.path_join(file), to + ".tmp") == OK and DirAccess.rename_absolute(to + ".tmp", to) == OK:
			copied += 1
	return copied
