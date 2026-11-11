class_name Haptics
extends RefCounted
## 진동 (자동 테스트 대상). 웹 Vibration API(안드로이드 크롬). 아이폰 사파리는 navigator.vibrate가 없어 조용히 건너뛴다.
## 레인 이동·점프·슬라이드에는 진동이 없다 (과하지 않게). 부를 때마다 sent에 남겨 테스트·화면 확인에서 언제 불렸는지 본다.

enum Event { CRASH, PERFECT, NEW_BEST }

## 진동 모양: [울림, 쉼, 울림, ...] (ms). Vibration API의 패턴 형식 그대로
const PATTERNS := {
	Event.CRASH: [30, 50, 40, 50, 60],  # 짧게 세 번, 점점 길게
	Event.PERFECT: [12],                # 아주 짧게 한 번
	Event.NEW_BEST: [25, 70, 25],       # 짧게 두 번
}

## 설정의 VIBRATION
var enabled := true
## 기기가 진동을 지원하는가. 지원하지 않으면 설정에서 항목을 숨긴다
var supported := false
## 실제로 진동을 보낸 기록: {event, pattern}
var sent: Array[Dictionary] = []


func _init(is_supported := false) -> void:
	supported = is_supported


## 웹이면 브라우저에 물어 본다. 데스크톱(개발용)은 진동이 없다
## shortcut: 설치형 앱(안드로이드·iOS)은 아직 진동 없음, 앱 빌드를 만들 때 Input.vibrate_handheld로 잇는다
static func detect() -> Haptics:
	var ok := OS.has_feature("web") and bool(JavaScriptBridge.eval("typeof navigator.vibrate === 'function'"))
	return Haptics.new(ok)


## 진동을 보냈으면 그 패턴, 아니면 빈 배열
func fire(event: Event) -> Array:
	if not (enabled and supported):
		return []
	var pattern: Array = PATTERNS[event]
	sent.append({"event": event, "pattern": pattern})
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.vibrate(%s)" % JSON.stringify(pattern))
	return pattern
