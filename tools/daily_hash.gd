extends SceneTree
## 오늘의 판 배치 지문: 출시일(#1)부터 날짜 30개의 앞 150마디 해시를 찍는다. 맥·윈도우(WSL)·웹(?dailyhash=1의 콘솔)에서 같아야 한다.
##   godot --headless --path . -s tools/daily_hash.gd

const DAYS := 30


func _initialize() -> void:
	process_frame.connect(_report, CONNECT_ONE_SHOT)  # 오토로드(AudioManager)가 준비된 뒤에 시작한다


func _report() -> void:
	var record: GDScript = load("res://scripts/logic/daily_record.gd")  # 오토로드에 기대는 클래스는 실행 중에 불러온다
	print(record.hash_report(DAYS))
	quit()
