class_name SkinBook
extends RefCounted
## 젤리 스킨 목록·해금 진행도·고른 스킨 (화면과 분리, 자동 테스트 대상). 스킨 값은 data/skins.json 한 곳.
## 진행도는 일반 모드·오늘의 판을 합산한다: PERFECT·방울은 누적, 점수·배수는 한 판의 가장 큰 값, 연속은 오늘의 판 연속 일수의 가장 큰 값.
## 해금은 진행도가 목표에 닿은 순간 정해지고 목록(unlocked)으로 따로 저장한다 (나중에 목표가 바뀌어도 열린 스킨은 그대로).
## 저장 파일 user://skins.cfg, [meta] version = FORMAT. 없거나 깨진 값은 처음 상태로 본다.

const PATH := "user://skins.cfg"
const DATA_PATH := "res://data/skins.json"
const FORMAT := 1
const STATS := ["perfects", "orbs", "score", "streak", "multiplier"]
const PATTERNS := ["none", "seeds", "slice", "soda", "stars", "aurora", "sheen"]  # jelly.gdshader pattern 번호
const BODY_MAX := 0.8  # 몸 색의 가장 센 채널(선형) 상한: 글로우 기준 0.9를 넘으면 몸 전체가 번져 뿌옇다 (ART_BIBLE 5장)
const LOCKED_BODY := Color("15132a")  # 잠긴 스킨: 어두운 실루엣
const LOCKED_RIM := Color("6a6390")

static var _list: Array = []

var stats := {}             # 진행도 이름 -> 값 (STATS)
var unlocked: Array[String] = []
var selected := "mint"      # 마지막으로 고른 열린 스킨 (시작하면 이 스킨)

var _path: String
var _read_only := false  # 더 새 버전(versions/의 다음 버전 등)이 쓴 파일: 읽기만 하고 덮어쓰지 않는다


## 스킨 목록 (json 순서 = 넘기는 순서)
static func list() -> Array:
	if _list.is_empty():
		_list = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))["skins"]
	return _list


static func index_of(id: String) -> int:
	for i in list().size():
		if list()[i]["id"] == id:
			return i
	return -1


static func skin(id: String) -> Dictionary:
	var i := index_of(id)
	return list()[i] if i >= 0 else list()[0]


## 젤리 셰이더에 넣을 값 (runner.apply_skin). locked: 잠긴 스킨의 어두운 실루엣 (같은 셰이더, 무늬·속 빛·반사광 끔)
static func shader_params(item: Dictionary, locked := false) -> Dictionary:
	if locked:
		return {"alpha_center": 0.8, "mint": LOCKED_BODY, "band_color": LOCKED_BODY.darkened(0.4), "rim_color": LOCKED_RIM, "rim_energy": 1.0, "core_color": LOCKED_RIM,
				"core_strength": 0.0, "pattern": 0, "pattern_strength": 0.0, "shine": 0.15, "bubble_strength": 0.0,
				"transmit_tint": Color(0.3, 0.28, 0.45), "line_tint": Color(0.35, 0.33, 0.5), "body_fix": Color(1, 1, 1)}
	var body := cap_body(Color(item["body"]))
	var h := body.h
	var s := body.s
	return {
		"mint": body,
		"band_color": Color(item["band"]) if item.has("band") else Color.from_hsv(h, minf(s * 1.6 + 0.25, 1.0), body.v * 0.62),
		"rim_color": Color(item["rim"]),
		"rim_energy": 2.4,
		"core_color": Color(item["core"]),
		"core_strength": float(item["core_strength"]),
		"pattern": PATTERNS.find(item["pattern"]),
		"pattern_strength": float(item["pattern_strength"]),
		"shine": 1.0,
		"alpha_center": float(item.get("opacity", 0.66)),  # 맑은 몸 가운데 불투명도: 밝은 색은 어두운 무대와 반씩 섞이면 탁해져(레몬이 올리브색) 조금 진하게
		"bubble_strength": 0.8,
		"transmit_tint": _rgb(item["transmit"]) if item.has("transmit") else Color.from_hsv(h, minf(s * 1.8 + 0.3, 0.85), 1.0),
		"line_tint": _rgb(item["line"]) if item.has("line") else Color.from_hsv(h, s * 0.9, 1.0),
		"body_fix": _rgb(item["body_fix"]) if item.has("body_fix") else Color(1, 1, 1),
	}


static func _rgb(v: Array) -> Color:
	return Color(v[0], v[1], v[2])


## 몸 색을 색조 그대로 BODY_MAX(선형) 아래로 낮춘다
static func cap_body(c: Color) -> Color:
	var lin := c.srgb_to_linear()
	var top := maxf(lin.r, maxf(lin.g, lin.b))
	return c if top <= BODY_MAX else (lin * (BODY_MAX / top)).linear_to_srgb()


func _init(path := PATH) -> void:
	_path = path
	var file := ConfigFile.new()
	var ok := file.load(path) == OK
	var version: Variant = file.get_value("meta", "version", FORMAT) if ok else FORMAT
	_read_only = version is int and version > FORMAT
	for key in STATS:
		var value: Variant = file.get_value("stats", key, 0) if ok else 0
		stats[key] = value if value is int and value >= 0 else 0
	var ids: Variant = file.get_value("skins", "unlocked", []) if ok else []
	if ids is Array or ids is PackedStringArray:
		for id: Variant in ids:
			if id is String and index_of(id) >= 0 and id not in unlocked:
				unlocked.append(id)
	_unlock_reached()
	var pick: Variant = file.get_value("skins", "selected", "mint") if ok else "mint"
	selected = pick if pick is String and is_unlocked(pick) else list()[0]["id"]


func is_unlocked(id: String) -> bool:
	return id in unlocked


## 진행도가 목표에 닿은 스킨을 연다. 새로 열린 스킨 id (목록 순서)
func _unlock_reached() -> Array[String]:
	var fresh: Array[String] = []
	for item: Dictionary in list():
		var unlock: Dictionary = item["unlock"]
		var reached: bool = unlock["kind"] == "start" or int(stats.get(unlock["kind"], 0)) >= int(unlock["goal"])
		if reached and not is_unlocked(item["id"]):
			unlocked.append(item["id"])
			fresh.append(item["id"])
	return fresh


## 이미 있는 기록(최고 점수·오늘의 판 최고·연속)을 진행도에 넣는다. 가장 큰 값만 남으므로 여러 번 불러도 같다. 새로 열린 스킨
func absorb_records(best_score: int, streak: int) -> Array[String]:
	_raise("score", best_score)
	_raise("streak", streak)
	var fresh := _unlock_reached()
	if not fresh.is_empty():
		save()
	return fresh


## 한 판이 끝났다 (게임 오버, 또는 판 중에 메인 화면으로). 새로 열린 스킨 id (목록 순서)
func finish_run(score: int, perfects: int, orbs: int, multiplier: int, streak: int) -> Array[String]:
	stats["perfects"] += maxi(perfects, 0)
	stats["orbs"] += maxi(orbs, 0)
	_raise("score", score)
	_raise("multiplier", multiplier)
	_raise("streak", streak)
	var fresh := _unlock_reached()
	save()
	return fresh


func _raise(key: String, value: int) -> void:
	stats[key] = maxi(stats[key], value)


## 열린 스킨만 고른다. 고르면 저장
func select(id: String) -> bool:
	if not is_unlocked(id):
		return false
	if id != selected:
		selected = id
		save()
	return true


## 잠긴 스킨의 조건·진행도 한 줄 ("PERFECTS 18/30", "SCORE 5000" 등)
func condition_text(id: String) -> String:
	var unlock: Dictionary = skin(id)["unlock"]
	var goal := int(unlock["goal"])
	var have := mini(int(stats.get(unlock["kind"], 0)), goal)
	match unlock["kind"]:
		"perfects":
			return "PERFECTS %d/%d" % [have, goal]
		"orbs":
			return "ORBS %d/%d" % [have, goal]
		"streak":
			return "DAILY STREAK %d/%d" % [have, goal]
		"multiplier":
			return "×%d IN ONE RUN" % goal
		"score":
			return "SCORE %d" % goal
	return ""


func save() -> void:
	if _read_only:
		return
	var file := ConfigFile.new()
	file.set_value("meta", "version", FORMAT)
	for key in STATS:
		file.set_value("stats", key, stats[key])
	file.set_value("skins", "unlocked", PackedStringArray(unlocked))
	file.set_value("skins", "selected", selected)
	# 임시 파일에 다 쓴 뒤 이름을 바꾼다: 쓰다가 끊겨도 앞의 진행도(누적 PERFECT·방울)가 남는다. 이름 바꾸기가 안 되는 곳은 바로 쓴다
	if file.save(_path + ".tmp") != OK or DirAccess.rename_absolute(_path + ".tmp", _path) != OK:
		file.save(_path)  # 저장소가 막힌 브라우저(시크릿 창 등)에서도 게임은 계속된다
