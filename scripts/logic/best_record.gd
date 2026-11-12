class_name BestRecord
extends RefCounted
## 최고 점수 기록: user://에 저장 (웹은 파일을 닫으면 엔진이 IndexedDB로 동기화한다). 자동 테스트 대상.
## v0.8.0부터 점수 기록. v0.7.0까지의 최고 거리(user://best.txt)는 지우지 않고 그대로 두며 화면에는 쓰지 않는다.

const PATH := "user://best_score.txt"
## 새 기록을 넘은 뒤에는 점수가 계속 오르므로 이 시간(초)마다 한 번만 저장한다. 첫 순간과 충돌 때는 바로 저장.
## 웹은 저장마다 IndexedDB 동기화를 해, 방울마다 저장하면 방울 줄을 먹는 동안 프레임이 밀렸다 (v0.8.0).
## v0.8.0은 50점 간격이었지만 v0.8.1에서 방울이 65점 × 배수가 되어 다시 방울마다 저장하게 되므로 시간 간격으로 바꿨다
const SAVE_EVERY := 2.0

var best := 0
## 이번 판 시작 전의 기록. 0이면 첫 판이라 "최고" 줄을 숨긴다.
var previous := 0
## 이번 판이 예전 기록을 넘었는가
var broken := false

var _path: String
var _saved := 0
var _saved_at := -INF


## start: 0 이상이면 파일을 읽지 않고 이 값에서 시작한다 (오늘의 판 DailyRecord)
func _init(path := PATH, start := -1) -> void:
	_path = path
	# 깨진 파일은 기록 없음으로 본다
	best = start if start >= 0 else maxi(FileAccess.get_file_as_string(path).strip_edges().to_int(), 0)
	_saved = best
	previous = best


func begin_run() -> void:
	previous = best
	broken = false


## 이번 판 점수를 알린다. 예전 기록을 넘은 바로 그 순간에만 true. now: 지금 시각(초, 테스트에서 넣는다)
func update(distance: int, now := Time.get_ticks_msec() / 1000.0) -> bool:
	if distance <= best:
		return false
	var first := best == previous
	best = distance
	if first or now - _saved_at >= SAVE_EVERY:
		save()
		_saved_at = now
	if first and previous > 0:
		broken = true
		return true
	return false


func save() -> void:
	if best == _saved:
		return
	if _write():
		_saved = best


## 파일에 쓴다. 못 쓰면 false (저장소가 막힌 브라우저(시크릿 창 등)에서도 게임은 계속된다)
func _write() -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(best))
	file.close()
	return true
