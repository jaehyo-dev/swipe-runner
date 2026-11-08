extends TestCase
## 프로젝트 설정(세로 화면, 렌더러, 웹 내보내기, 버전) 테스트.


func test_게임_버전은_메이저_마이너_패치_형식() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_not_null(RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$").search(version), "버전 '%s'" % version)


func test_웹에서_동작하는_렌더러를_사용() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")


func test_세로_720x1280_화면_기준() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 720)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1280)
	assert_eq(ProjectSettings.get_setting("display/window/handheld/orientation"), 1, "1 = 세로")


func test_터치_입력_기준() -> void:
	# 마우스 드래그도 터치 이벤트로 받아 PC에서 같은 코드로 테스트한다
	assert_eq(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse"), true)


func test_웹_내보내기는_스레드_없이_설정됨() -> void:
	# 스레드 지원을 켜면 GitHub Pages(COOP/COEP 헤더 없음)에서 실행되지 않는다.
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg 읽기")
	assert_eq(presets.get_value("preset.0", "platform", ""), "Web")
	assert_eq(presets.get_value("preset.0", "name", ""), "Web", "프리셋 이름 (배포 워크플로가 이 이름을 씀)")
	assert_eq(presets.get_value("preset.0.options", "variant/thread_support", true), false, "스레드 지원 끔")
	assert_eq(presets.get_value("preset.0", "export_path", ""), "build/web/index.html")
	var excluded := str(presets.get_value("preset.0", "exclude_filter", ""))
	for folder in ["tests/*", "tools/*", "build/*", "_site/*"]:
		assert_true(excluded.contains(folder), "내보내기 제외: " + folder)


func test_내보내기_결과물_폴더는_리소스로_가져오지_않음() -> void:
	assert_true(FileAccess.file_exists("res://build/.gdignore"), "build/.gdignore")


func test_화면_확인_기록과_소리_후보는_웹_빌드에_들어가지_않음() -> void:
	assert_true(FileAccess.file_exists("res://review/.gdignore"), "review/.gdignore")


func test_시작_씬이_존재함() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, "res://scenes/main.tscn")
	assert_true(ResourceLoader.exists(main_scene), "시작 씬 파일")
