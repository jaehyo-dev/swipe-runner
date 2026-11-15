class_name PwaState
## 홈 화면 앱(PWA) 상태를 화면이 쓸 값으로 바꾼다 (v0.12.0). JS 쪽은 web/shell.html의 window.pwa.
## state(): "update,ios" 처럼 쉼표로 이은 표시 (update = 새 버전 받음, ios = 아이폰 브라우저 안내, install = 안드로이드 설치 가능)
## insets(): "위,오른쪽,아래,왼쪽,창 너비,창 높이" (CSS px, 안전 영역)


## → {update: 새 버전 UPDATE를 보일까, hint: "ios" | "install" | ""}. 아이폰 안내가 설치 버튼보다 먼저
static func parse(state: String) -> Dictionary:
	var flags := state.split(",", false)
	var hint := "ios" if "ios" in flags else ("install" if "install" in flags else "")
	return {"update": "update" in flags, "hint": hint}


## 안전 영역(CSS px)을 화면 단위(view = 보이는 화면 크기)로: Vector2(위, 아래). 값이 없거나 틀리면 0
static func insets(text: String, view: Vector2) -> Vector2:
	var v := text.split_floats(",", false)
	if v.size() < 6 or v[5] <= 0.0:
		return Vector2.ZERO
	var k := view.y / v[5]
	return Vector2(maxf(v[0], 0.0) * k, maxf(v[2], 0.0) * k)
