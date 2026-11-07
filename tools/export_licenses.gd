extends SceneTree
## Godot 엔진과 엔진에 포함된 서드파티 라이브러리의 라이선스 문구를 파일로 저장한다.
## Godot(MIT)으로 만든 게임을 배포할 때는 이 문구를 함께 제공해야 한다.
## 실행: godot --headless --path . -s res://tools/export_licenses.gd -- <출력 파일>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("사용법: godot --headless --path . -s res://tools/export_licenses.gd -- <출력 파일>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("파일을 열 수 없습니다: " + args[0])
		quit(1)
		return
	file.store_string(license_text())
	file.close()
	quit(0)


## 엔진 라이선스 + 구성 요소별 저작권 + 라이선스 전문
static func license_text() -> String:
	var lines: PackedStringArray = []
	lines.append("이 게임은 Godot Engine으로 만들었습니다. (https://godotengine.org/license)")
	lines.append("")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("== 엔진에 포함된 구성 요소 ==")
	for component in Engine.get_copyright_info():
		lines.append("")
		lines.append("- " + str(component["name"]))
		for part in component["parts"]:
			for holder in part["copyright"]:
				lines.append("  Copyright " + str(holder))
			lines.append("  License: " + str(part["license"]))
	lines.append("")
	lines.append("== 라이선스 전문 ==")
	var licenses: Dictionary = Engine.get_license_info()
	for license_name in licenses:
		lines.append("")
		lines.append("--- " + str(license_name) + " ---")
		lines.append(str(licenses[license_name]))
	return "\n".join(lines) + "\n"
