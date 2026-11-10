extends TestCase
## 최고 거리 기록 테스트.

const PATH := "user://test_best_record.txt"


func _fresh() -> BestRecord:
	DirAccess.remove_absolute(PATH)
	return BestRecord.new(PATH)


func _on_disk() -> int:
	return FileAccess.get_file_as_string(PATH).to_int()


func test_파일이_없으면_기록_없음() -> void:
	assert_eq(_fresh().best, 0)


func test_깨진_파일은_기록_없음으로() -> void:
	for text in ["abc", "-5", ""]:
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		assert_eq(BestRecord.new(PATH).best, 0, text)


func test_새로_열어도_기록이_남음() -> void:
	var record := _fresh()
	record.update(42)
	record.save()
	assert_eq(BestRecord.new(PATH).best, 42)


func test_첫_판은_바로_저장하지만_새_기록_신호는_없음() -> void:
	var record := _fresh()
	assert_false(record.update(1))
	assert_eq(_on_disk(), 1, "바로 저장")
	assert_false(record.broken)


func test_예전_기록을_넘은_순간에만_신호하고_그_순간_저장() -> void:
	var record := _fresh()
	record.update(100)
	record.save()
	record.begin_run()
	assert_false(record.update(100), "같으면 아직")
	assert_eq(record.best, 100)
	assert_true(record.update(101), "넘은 순간")
	assert_true(record.broken)
	assert_eq(_on_disk(), 101)
	assert_false(record.update(102), "한 번만")
	assert_eq(_on_disk(), 101, "매번 쓰지 않음")
	record.update(101 + BestRecord.SAVE_STEP)
	assert_eq(_on_disk(), 101 + BestRecord.SAVE_STEP, "50점마다 저장")
	record.update(101 + BestRecord.SAVE_STEP + 3)
	record.save()
	assert_eq(_on_disk(), 101 + BestRecord.SAVE_STEP + 3, "충돌 때 저장")


func test_못_넘은_판은_기록을_바꾸지_않음() -> void:
	var record := _fresh()
	record.update(50)
	record.save()
	record.begin_run()
	record.update(20)
	record.save()
	assert_eq(_on_disk(), 50)
	assert_false(record.broken)
