class_name MusicLadder
extends RefCounted
## 음악 사다리: 4마디마다 5BPM씩 오르고, 음악 시간을 박·이동 거리·색 진하기로 바꾼다 (자동 테스트 대상).
## 속도는 BPM과 따로 정한다(STEPS). 한 박 거리가 단계마다 달라서 이동 거리는 구간별로 쌓아 계산한다.
## 경계는 장애물이 나오기 전에 정해지므로(plan의 lead), 경계 전에 생긴 장애물도 정확히 자기 박에 도착한다.

## 곡 파일은 tools/make_ladder_music.py가 만든다. stage: 0 원본, 1 A Drive, 2 B Drive+
const STEPS: Array[Dictionary] = [
	{"bpm": 100, "speed": 15.0, "stage": 0, "file": "bgm_100_orig"},
	{"bpm": 105, "speed": 16.5, "stage": 0, "file": "bgm_105_orig"},
	{"bpm": 110, "speed": 18.0, "stage": 1, "file": "bgm_110_a"},
	{"bpm": 115, "speed": 19.5, "stage": 1, "file": "bgm_115_a"},
	{"bpm": 120, "speed": 21.0, "stage": 2, "file": "bgm_120_b"},
	{"bpm": 125, "speed": 22.5, "stage": 2, "file": "bgm_125_b"},
	{"bpm": 130, "speed": 24.0, "stage": 2, "file": "bgm_130_b"},
	{"bpm": 135, "speed": 25.5, "stage": 2, "file": "bgm_135_b"},
	{"bpm": 140, "speed": 27.0, "stage": 2, "file": "bgm_140_b"},
	{"bpm": 145, "speed": 28.5, "stage": 2, "file": "bgm_145_b"},
	{"bpm": 150, "speed": 30.0, "stage": 2, "file": "bgm_150_b"},
	{"bpm": 155, "speed": 31.5, "stage": 2, "file": "bgm_155_b"},
	{"bpm": 160, "speed": 33.0, "stage": 2, "file": "bgm_160_b"},
]
const LAP_BEATS := BeatClock.BEATS_PER_BAR * BeatClock.LOOP_BARS  # 곡 파일 한 바퀴 (16마디)
const STEP_BARS := 4    # 이만큼마다 템포가 오른다
const STEP_BEATS := BeatClock.BEATS_PER_BAR * STEP_BARS
const TINT_BARS := 2    # 속도가 오른 뒤 색 진하기가 따라가는 시간
const TINT_BPM_FROM := 100.0  # 진하기 t = (BPM - 100) ÷ 60
const TINT_BPM_RANGE := 60.0

## 오른 구간들 {start: 음악 시간, beat: 시작 박, step, distance: 시작 이동 거리}. 마지막 구간은 곡이 반복되는 동안 그대로 이어진다.
var segments: Array[Dictionary] = []


func _init(start_step := 0) -> void:
	segments.append({"start": 0.0, "beat": 0, "step": start_step, "distance": 0.0})


## ?bpm=115 같은 값의 단계. 사다리에 없는 값이면 -1
static func step_of_bpm(bpm: int) -> int:
	return STEPS.map(func(s): return s["bpm"]).find(bpm)


static func beat_time(step: int) -> float:
	return 60.0 / STEPS[step]["bpm"]


static func lap_time(step: int) -> float:
	return beat_time(step) * LAP_BEATS


## 4마디 구간의 길이(초)
static func span_time(step: int) -> float:
	return beat_time(step) * STEP_BEATS


static func beat_distance(step: int) -> float:
	return STEPS[step]["speed"] * beat_time(step)


## 단계의 색 진하기 목표
static func step_tint(step: int) -> float:
	return clampf((STEPS[step]["bpm"] - TINT_BPM_FROM) / TINT_BPM_RANGE, 0.0, 1.0)


## 경계를 놓치지 않으면 이 박이 속할 단계 (패턴 난이도 예고용).
## shortcut: 곡 준비가 늦어 경계가 밀리면 패턴이 실제 템포보다 앞선다. 실제 템포가 느린 쪽이라 더 쉬워질 뿐이라 둔다.
static func scheduled_step(start_step: int, beat: float) -> int:
	return mini(start_step + maxi(floori(beat / STEP_BEATS), 0), STEPS.size() - 1)


func segment_at(t: float) -> Dictionary:
	for i in range(segments.size() - 1, 0, -1):
		if t >= segments[i]["start"]:
			return segments[i]
	return segments[0]


func _segment_of_beat(beat: float) -> Dictionary:
	for i in range(segments.size() - 1, 0, -1):
		if beat >= segments[i]["beat"]:
			return segments[i]
	return segments[0]


## 음악 시간 t의 박 (연속값). 음수 시간(소리가 나기 전)은 음수 박.
func beat_at(t: float) -> float:
	var seg := segment_at(t)
	return seg["beat"] + (t - seg["start"]) / beat_time(seg["step"])


func distance_at(t: float) -> float:
	var seg := segment_at(t)
	return seg["distance"] + (t - seg["start"]) * STEPS[seg["step"]]["speed"]


## 박(반 박 포함)에 닿을 때의 이동 거리. 정해진 구간까지만 안다: 그 뒤는 마지막 구간이 이어진다고 본다.
func distance_of_beat(beat: float) -> float:
	var seg := _segment_of_beat(beat)
	return seg["distance"] + (beat - seg["beat"]) * beat_distance(seg["step"])


func speed_at(t: float) -> float:
	return STEPS[segment_at(t)["step"]]["speed"]


## 박 번호의 음악 시간 (도착 시각 측정용)
func time_of_beat(beat: float) -> float:
	var seg := _segment_of_beat(beat)
	return seg["start"] + (beat - seg["beat"]) * beat_time(seg["step"])


## 편곡 단계가 오른 순간부터 흐른 시간. 단계가 오르지 않은 구간이면 -1
func stage_up_age(t: float) -> float:
	var i := segments.find(segment_at(t))
	if i == 0 or STEPS[segments[i]["step"]]["stage"] == STEPS[segments[i - 1]["step"]]["stage"]:
		return -1.0
	return t - segments[i]["start"]


## 음악 시간 t의 색 진하기: 속도가 오른 순간부터 2마디 동안 끊김 없이 새 값으로 따라간다.
func tint_at(t: float) -> float:
	var seg := segment_at(t)
	var i := segments.find(seg)
	var to := step_tint(seg["step"])
	if i == 0:
		return to
	var hold: float = beat_time(seg["step"]) * BeatClock.BEATS_PER_BAR * TINT_BARS
	return lerpf(step_tint(segments[i - 1]["step"]), to, smoothstep(0.0, hold, t - seg["start"]))


## 구간을 잇는다. 시작 거리는 앞 구간에서 이어 계산한다.
func add_segment(start: float, beat: int, step: int) -> void:
	segments.append({"start": start, "beat": beat, "step": step, "distance": distance_of_beat(beat)})


## 아직 정하지 않은 다음 경계 {at, step, beat, from}. 사다리 끝이면 빈 값. from: 새 곡을 시작할 곡 안 위치(초).
## min_lead: 이보다 가까운 경계는 늦었으니 4마디 더 돈다 (탭 전환·긴 멈춤).
func next_edge(now: float, min_lead: float) -> Dictionary:
	var last: Dictionary = segments[-1]
	if last["step"] >= STEPS.size() - 1:
		return {}
	var span := span_time(last["step"])
	var spans := maxi(ceili((now + min_lead - last["start"]) / span), 1)
	var step: int = last["step"] + 1
	var beat: int = last["beat"] + spans * STEP_BEATS
	return {"at": last["start"] + spans * span, "step": step, "beat": beat, "from": posmod(beat, LAP_BEATS) * beat_time(step)}


## 다음 단계로 올릴 차례면 경계를 구간에 더하고 {at, step, from}을 돌려준다. 아니면 빈 값.
## lead: 경계가 이만큼 안으로 들어와야 예약한다. 빠른 단계는 4마디가 lead보다 짧아 앞 구간이 시작하기 전에 다음 경계를 정하기도 한다.
## next_ready: 다음 곡이 준비됐는가. 안 됐으면 지금 곡이 4마디 더 돌아 박이 어긋나지 않는다.
func plan(now: float, lead: float, min_lead: float, next_ready: bool) -> Dictionary:
	var edge := next_edge(now, min_lead)
	if edge.is_empty() or not next_ready or edge["at"] - now > lead:
		return {}
	add_segment(edge["at"], edge["beat"], edge["step"])
	return {"at": edge["at"], "step": edge["step"], "from": edge["from"]}
