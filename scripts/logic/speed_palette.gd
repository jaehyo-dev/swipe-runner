class_name SpeedPalette
extends RefCounted
## 속도에 따른 색 진하기 (ART_BIBLE.md 11장, 자동 테스트 대상). 값은 data/speed_palette.json 한 곳에만 있다.

const PATH := "res://data/speed_palette.json"
## 숫자 값 (섞을 때 색이 아니라 수로 다룬다)
const NUMBERS := ["rail_energy"]

static var _sets := {}


## 진하기 t(0~1)의 값들을 선형으로 섞어 돌려준다. 색은 Color, *_edge도 HDR Color.
static func at(t: float) -> Dictionary:
	if _sets.is_empty():
		_sets = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var from: Dictionary = _sets["t0"]
	var to: Dictionary = _sets["t1"]
	var mixed := {}
	for key: String in from:
		if key in NUMBERS:
			mixed[key] = lerpf(from[key], to[key], t)
		else:
			mixed[key] = _color(from[key]).lerp(_color(to[key]), t)
	return mixed


static func _color(value: Variant) -> Color:
	if value is String:
		return Color(value)
	return Color(value[0], value[1], value[2])
