class_name BestRecord
extends RefCounted
## 최고 거리 기록: user://에 저장 (웹은 파일을 닫으면 엔진이 IndexedDB로 동기화한다). 자동 테스트 대상.

const PATH := "user://best.txt"
## 새 기록을 넘은 뒤에는 거리가 계속 오르므로 이만큼 늘 때마다 저장한다 (약 1초). 첫 순간과 충돌 때는 바로 저장.
const SAVE_STEP := 10

var best := 0
## 이번 판 시작 전의 기록. 0이면 첫 판이라 "최고" 줄을 숨긴다.
var previous := 0
## 이번 판이 예전 기록을 넘었는가
var broken := false

var _path: String
var _saved := 0


func _init(path := PATH) -> void:
	_path = path
	# 깨진 파일은 기록 없음으로 본다
	best = maxi(FileAccess.get_file_as_string(path).strip_edges().to_int(), 0)
	_saved = best
	previous = best


func begin_run() -> void:
	previous = best
	broken = false


## 이번 판 거리를 알린다. 예전 기록을 넘은 바로 그 순간에만 true
func update(distance: int) -> bool:
	if distance <= best:
		return false
	var first := best == previous
	best = distance
	if first or best >= _saved + SAVE_STEP:
		save()
	if first and previous > 0:
		broken = true
		return true
	return false


func save() -> void:
	if best == _saved:
		return
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:  # 저장소가 막힌 브라우저(시크릿 창 등)에서도 게임은 계속된다
		return
	file.store_string(str(best))
	file.close()
	_saved = best
