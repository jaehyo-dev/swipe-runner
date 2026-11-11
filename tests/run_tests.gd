extends SceneTree
## 자동 테스트 실행기.
## 실행: bash tests/run_tests.sh (리소스 가져오기 godot --headless --path . --import 를 먼저 실행)
## tests/ 폴더의 test_*.gd 파일을 모두 찾아 test_ 로 시작하는 함수를 실행하고,
## 하나라도 실패하면 종료 코드 1로 끝난다 (GitHub Actions가 실패로 처리).
## 이 파일 자체가 깨지면 Godot가 종료 코드 0으로 끝나므로, run_tests.sh가 "결과:" 줄이 있는지도 확인한다.
## 그래서 이 파일은 전역 클래스 이름(TestCase 등)을 쓰지 않는다: 클래스 캐시가 없어도 파싱되어야 오류를 알릴 수 있다.

const TEST_DIR := "res://tests"


## 테스트 중에 난 엔진·스크립트 오류를 모은다.
## GDScript는 실행 중 오류(null 접근 등)가 나면 그 함수만 멈추고 계속 진행하므로,
## 오류를 따로 잡지 않으면 실패한 테스트가 통과로 보일 수 있다.
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var message := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s:%d (%s) %s" % [file, line, function, message])
		_mutex.unlock()

	## 지금까지 모인 오류를 꺼내고 비운다.
	func take() -> PackedStringArray:
		_mutex.lock()
		var result := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return result

var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	var passed := 0
	var failed := 0
	# 리소스 가져오기를 안 하면 클래스 캐시가 없어 test_*.gd가 TestCase를 찾지 못한다.
	if not ProjectSettings.get_global_class_list().any(func(c): return c["class"] == "TestCase"):
		printerr("TestCase 클래스를 찾지 못했습니다. 리소스 가져오기를 먼저 실행하세요: godot --headless --path . --import")
		quit(1)
		return
	var files := _test_files()
	if files.is_empty():
		printerr("테스트 파일을 찾지 못했습니다: %s/test_*.gd" % TEST_DIR)
		quit(1)
		return

	for file in files:
		_catcher.take()
		var script: GDScript = load(file)
		var load_errors := _catcher.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			printerr("실패  %s - 스크립트를 불러올 수 없음 (문법 오류 확인)" % file)
			for error in load_errors:
				printerr("      - " + error)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			# 테스트 함수마다 새 인스턴스를 만들어 서로 영향을 주지 않게 한다.
			var test: Node = script.new()
			root.add_child(test)
			_catcher.take()
			await test.call(name)
			for error in _catcher.take():
				test.failures.append("실행 중 오류: " + error)
			if test.failures.is_empty():
				print("통과  %s :: %s" % [file.get_file(), name])
				passed += 1
			else:
				printerr("실패  %s :: %s" % [file.get_file(), name])
				for message in test.failures:
					printerr("      - " + message)
				failed += 1
			test.queue_free()
			await process_frame

	print("\n결과: 통과 %d, 실패 %d" % [passed, failed])
	# 소리를 멈추고 오디오 스레드가 재생 상태 객체를 치울 시간을 준다. 재생 중이거나 막 끝난 소리를 두고 바로 끝내면
	# "ObjectDB instances were leaked" 경고가 난다 (review/v0.9.0/leak.md)
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	quit(1 if failed > 0 or passed == 0 else 0)


## tests/ 폴더에서 test_*.gd 파일 목록 (이름순). 환경 변수 TEST_FILE=test_orbs 처럼 주면 이름에 그 글자가 든 파일만 (바뀐 부분만 돌릴 때)
func _test_files() -> PackedStringArray:
	var result: PackedStringArray = []
	var only := OS.get_environment("TEST_FILE")
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd" and (only.is_empty() or only in file):
			result.append(TEST_DIR.path_join(file))
	result.sort()
	return result
