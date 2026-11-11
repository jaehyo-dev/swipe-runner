extends TestCase
## 플레이 횟수·소리 설정 저장, 이름이 바뀐 뒤 옛 user:// 폴더에서 기록 옮겨 오기.

const PATH := "user://test_settings.cfg"
const OLD := "user://test_old_dir"
const NEW := "user://test_new_dir"


func _clean() -> void:
	DirAccess.remove_absolute(PATH)
	for dir in [OLD, NEW]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


func test_처음에는_0판_소리_켬이고_안내는_3판까지() -> void:
	_clean()
	var data := SaveData.new(PATH)
	assert_eq(data.plays, 0)
	assert_false(data.muted)
	for i in SaveData.GUIDE_RUNS:
		assert_true(data.shows_guide(), "%d판을 한 뒤" % i)
		data.count_play()
	assert_false(data.shows_guide(), "4판째부터 숨김")
	_clean()


func test_판_수와_소리_끔은_다시_열어도_그대로() -> void:
	_clean()
	var data := SaveData.new(PATH)
	data.count_play()
	data.count_play()
	data.set_muted(true)
	var again := SaveData.new(PATH)
	assert_eq(again.plays, 2)
	assert_true(again.muted)
	_clean()


func test_엉뚱한_값은_처음_상태() -> void:
	_clean()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("[play]\nplays=\"3\"\n[sound]\nmuted=\"yes\"\n")
	file.close()
	var data := SaveData.new(PATH)
	assert_eq(data.plays, 0)
	assert_false(data.muted)
	_clean()


func test_옛_폴더의_기록을_복사하고_새_폴더에_있던_파일은_덮어쓰지_않음() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(OLD)
	for pair in [["best_score.txt", "7157"], ["settings.cfg", "old"]]:
		var file := FileAccess.open(OLD.path_join(pair[0]), FileAccess.WRITE)
		file.store_string(pair[1])
		file.close()
	DirAccess.make_dir_recursive_absolute(NEW)
	var mine := FileAccess.open(NEW.path_join("settings.cfg"), FileAccess.WRITE)
	mine.store_string("new")
	mine.close()
	assert_eq(SaveData.migrate(OLD, NEW), 1, "기록 하나만 복사")
	assert_eq(BestRecord.new(NEW.path_join("best_score.txt")).best, 7157, "최고 점수가 그대로")
	assert_eq(FileAccess.get_file_as_string(NEW.path_join("settings.cfg")), "new", "새 폴더 파일은 그대로")
	assert_true(FileAccess.file_exists(OLD.path_join("best_score.txt")), "옛 폴더는 지우지 않음")
	assert_eq(SaveData.migrate(OLD, NEW), 0, "두 번째에는 할 일 없음")
	assert_eq(SaveData.migrate(OLD + "_none", NEW), 0, "옛 폴더가 없으면(새로 설치) 아무것도 안 함")
	_clean()


func test_옛_폴더는_같은_곳의_옛_이름() -> void:
	assert_eq(SaveData.old_user_dir().get_file(), "스와이프 러너")
	assert_eq(SaveData.old_user_dir().get_base_dir(), OS.get_user_data_dir().get_base_dir())
	assert_eq(ProjectSettings.get_setting("application/config/name"), "SWIPE PULSE")
