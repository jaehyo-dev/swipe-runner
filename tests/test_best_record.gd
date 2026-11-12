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


func test_옛_기록은_새_파일로_한_번만_반으로() -> void:
	var old := "user://test_best_old.txt"
	DirAccess.remove_absolute(PATH)
	BestRecord.write_atomic(old, "17001")
	assert_true(BestRecord.convert_old(old, PATH), "옮김")
	assert_eq(BestRecord.new(PATH).best, 8500, "0.5배, 소수점 버림")
	assert_eq(FileAccess.get_file_as_string(old), "17001", "옛 파일은 그대로 (versions/의 옛 버전)")
	BestRecord.write_atomic(old, "30000")
	assert_false(BestRecord.convert_old(old, PATH), "새 파일이 있으면 다시 옮기지 않음")
	assert_eq(BestRecord.new(PATH).best, 8500)
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(old)
	assert_false(BestRecord.convert_old(old, PATH), "옛 파일이 없으면 아무것도 안 함")
	assert_false(FileAccess.file_exists(PATH))


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
	assert_true(record.update(101, 10.0), "넘은 순간")
	assert_true(record.broken)
	assert_eq(_on_disk(), 101)
	assert_false(record.update(102, 10.1), "한 번만")
	assert_eq(_on_disk(), 101, "매번 쓰지 않음")
	record.update(5000, 11.9)
	assert_eq(_on_disk(), 101, "점수가 크게 올라도 2초 안에는 저장하지 않음 (웹 IndexedDB 동기화 몰림)")
	record.update(5001, 12.0)
	assert_eq(_on_disk(), 5001, "2초마다 저장")
	record.update(5004, 12.1)
	record.save()
	assert_eq(_on_disk(), 5004, "충돌 때 저장")


func test_못_넘은_판은_기록을_바꾸지_않음() -> void:
	var record := _fresh()
	record.update(50)
	record.save()
	record.begin_run()
	record.update(20)
	record.save()
	assert_eq(_on_disk(), 50)
	assert_false(record.broken)
