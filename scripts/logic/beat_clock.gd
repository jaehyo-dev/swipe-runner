class_name BeatClock
extends RefCounted
## 음악 재생 위치를 끊기지 않는 시간으로 바꾼다. 프레임 시간을 쌓지 않아 음악과 점점 어긋나지 않는다 (자동 테스트 대상).

const BPM := 100.0
const BEAT := 60.0 / BPM        # 한 박 0.6초
const BEATS_PER_BAR := 4
const BAR := BEAT * BEATS_PER_BAR  # 한 마디 2.4초
const LOOP_BARS := 16
const LOOP := BAR * LOOP_BARS   # 38.4초마다 반복
## 재생 위치가 이만큼 멈춰 있으면 오디오가 막힌 것으로 보고 프레임 시간으로 이어 간다 (소리가 안 나도 게임은 멈추지 않게)
const STALL_TIME := 0.25
## 재생 위치가 이만큼 뒤로 가면 반복 지점을 넘은 것 (읽기 오차는 이보다 훨씬 작다. 탭을 오래 가렸다 돌아와 건너뛴 경우도 잡는다)
const WRAP_DROP := 1.0

## 음악 처음부터 흐른 시간 (반복 지점을 넘어도 계속 늘어남)
var time := 0.0

var _loops := 0
var _offset := 0.0  # 오디오가 멈췄다 돌아온 뒤 재생 위치에 더하는 값 (박의 배수)
var _last := 0.0
var _held := 0.0
var _free_run := false


## raw: 이번 프레임에 읽은 재생 위치(0~LOOP, 지연 보정으로 조금 벗어날 수 있음), delta: 프레임 시간
func update(raw: float, delta: float) -> float:
	var t := raw + _loops * LOOP + _offset
	if t < _last - WRAP_DROP:
		_loops += 1
		t += LOOP
	if _free_run and t > _last and t < time:  # 오디오가 돌아왔다: 시간은 되돌리지 않고 다음 박 격자에 맞춘다
		var catch_up := ceilf((time - t) / BEAT) * BEAT
		_offset += catch_up
		t += catch_up
	_last = t
	if t > time:
		time = t
		_held = 0.0
		_free_run = false
	else:  # 읽은 값이 살짝 뒤로 가도 시간은 되돌리지 않는다
		_held += delta
		if _held >= STALL_TIME:
			_free_run = true
			time += delta
	return time
