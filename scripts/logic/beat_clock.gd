class_name BeatClock
extends RefCounted
## 음악 재생 위치를 끊기지 않는 시간으로 바꾼다. 프레임 시간을 쌓지 않아 음악과 점점 어긋나지 않는다 (자동 테스트 대상).
## 재생 위치는 판이 시작한 뒤로 곡이 바뀌어도 계속 늘어나는 값이다.

const BEATS_PER_BAR := 4
const LOOP_BARS := 16
## 재생 위치가 이만큼 멈춰 있으면 오디오가 막힌 것으로 보고 프레임 시간으로 이어 간다 (소리가 안 나도 게임은 멈추지 않게)
const STALL_TIME := 0.25
## 첫 소리를 기다릴 때는 더 오래 기다린다: 기기가 오디오를 켜는 시간을 멈춤으로 보면, 돌아올 때 세상이 한 박 순간 이동한다
const START_STALL_TIME := 1.0
## 멈춘 뒤 재생 위치가 멈춘 자리보다 이만큼 늘지 않으면 읽기 오차로 보고 오디오가 돌아온 것으로 치지 않는다
const READ_NOISE := 0.005

## 재생 위치는 오디오 블록 단위로 계단처럼 오른다. 그대로 쓰면 프레임마다 세상이 가는 거리가 들쭉날쭉하므로(120Hz에서 특히) 화면에는 프레임 시간으로 잇고 차이만 조금씩 메운 값을 쓴다.
## v0.11.1: 아이폰 WebKit은 계단이 크고(수십 ms) 지연 값이 바뀌며 위치가 뒤로 가기도 한다. 전에는 계단마다 차이를 빨리 메워 이동량이 20%씩 흔들렸고,
## 30ms 넘게 뒤처지면 세상을 멈췄다가 한 번에 맞췄다(멈춤 → 점프). 이제 천천히 메우고, 한 프레임에 메우는 양을 프레임 시간의 MAX_CATCH배로 묶는다
## (뒤처져도 멈추지 않고 조금 느리게 간다). 크게 벌어질 때만 바로 맞춘다. 표: review/v0.11.1/clock_before.md → clock_after.md
const SMOOTH_TIME := 0.5   # 차이를 메우는 시간 상수(초)
const SNAP := 0.1          # 이보다 앞서 벌어지면 메우지 않고 바로 맞춘다 (긴 프레임, 탭 전환)
const MAX_CATCH := 0.08    # 한 프레임에 메우는 양의 상한 (프레임 시간 대비)

## 판 처음부터 흐른 음악 시간
var time := 0.0
## 화면에 쓰는 부드러운 음악 시간. 되돌아가지 않는다
var smooth := 0.0
## 오디오가 멈췄다 돌아온 뒤 재생 위치에 더하는 값 (박의 배수). 다음 곡 예약 때 재생 위치로 되돌리는 데 쓴다.
var offset := 0.0

var _last := 0.0
var _held := 0.0
var _free_run := false
var _heard := false  # 재생 위치가 한 번이라도 흘렀는가


## raw: 이번 프레임에 읽은 재생 위치, delta: 프레임 시간, beat: 지금 한 박의 길이(초)
func update(raw: float, delta: float, beat := 0.6) -> float:
	var t := raw + offset
	if _free_run and t > _last + READ_NOISE and t < time:  # 오디오가 돌아왔다: 시간은 되돌리지 않고 다음 박 격자에 맞춘다
		var catch_up := ceilf((time - t) / beat) * beat
		offset += catch_up
		t += catch_up
	if not (_free_run and t < _last + READ_NOISE):  # 멈춘 동안은 멈춘 자리를 기억한다 (프레임마다 조금씩 늘어도 복귀를 알아채게)
		_last = t
	if t > time:
		time = t
		_held = 0.0
		_free_run = false
		_heard = true
	else:  # 읽은 값이 살짝 뒤로 가도 시간은 되돌리지 않는다
		_held += delta
		if _held >= (STALL_TIME if _heard else START_STALL_TIME):
			_free_run = true
			time += delta
	return time


## 일시정지를 풀 때: 첫 소리를 기다릴 때처럼 다룬다. 소리가 다시 흐를 때까지 화면 시간이 프레임 시간으로 앞서 나가지 않는다
## (오디오는 다시 켠 뒤 몇 ms~수십 ms 늦게 흐른다. 앞서 나가면 장애물이 박보다 먼저 온다)
func rehear() -> void:
	_heard = false
	_held = 0.0


## update 뒤에 부른다. 프레임 시간 delta로 잇고 time과의 차이를 조금씩 메운 시간을 돌려준다.
func smoothed(delta: float) -> float:
	var ahead := smooth + delta
	var gap := time - ahead
	if not _heard or gap > SNAP:
		smooth = maxf(smooth, time)
	else:  # 뒤처졌으면(gap < 0) 조금 느리게, 앞섰으면 조금 빠르게. 멈추지 않는다
		var catch_up := clampf(gap * (1.0 - exp(-delta / SMOOTH_TIME)), -delta * MAX_CATCH, delta * MAX_CATCH)
		smooth = maxf(smooth, ahead + catch_up)
	return smooth
