class_name MusicLadder
extends RefCounted
## 음악 사다리: 한 바퀴(16마디)마다 5BPM씩 오르고, 편곡 단계가 바뀌며, 음악 시간을 박·이동 거리로 바꾼다 (자동 테스트 대상).
## 속도 = 9 × BPM ÷ 100이고 한 박 = 60 ÷ BPM초라서 어느 BPM이든 한 박에 5.4만큼 간다. 그래서 이동 거리는 지나간 박 수로 정해지고,
## 경계 전에 생긴 장애물도 경계 뒤에 정확히 자기 박에 도착한다.

## 곡 파일은 tools/make_ladder_music.py가 만든다. stage: 0 원본, 1 A Drive, 2 B Drive+
const STEPS: Array[Dictionary] = [
	{"bpm": 100, "stage": 0, "file": "bgm_100_orig"},
	{"bpm": 105, "stage": 0, "file": "bgm_105_orig"},
	{"bpm": 110, "stage": 1, "file": "bgm_110_a"},
	{"bpm": 115, "stage": 1, "file": "bgm_115_a"},
	{"bpm": 120, "stage": 2, "file": "bgm_120_b"},
	{"bpm": 125, "stage": 2, "file": "bgm_125_b"},
	{"bpm": 130, "stage": 2, "file": "bgm_130_b"},
]
const LAP_BEATS := BeatClock.BEATS_PER_BAR * BeatClock.LOOP_BARS
const BEAT_DISTANCE := RunLogic.SPEED * 60.0 / 100.0

## 오른 구간들 {start: 음악 시간, beat: 시작 박, step}. 마지막 구간은 곡이 반복되는 동안 그대로 이어진다.
var segments: Array[Dictionary] = []


func _init(start_step := 0) -> void:
	segments.append({"start": 0.0, "beat": 0, "step": start_step})


## ?bpm=115 같은 값의 단계. 사다리에 없는 값이면 -1
static func step_of_bpm(bpm: int) -> int:
	return STEPS.map(func(s): return s["bpm"]).find(bpm)


static func beat_time(step: int) -> float:
	return 60.0 / STEPS[step]["bpm"]


static func lap_time(step: int) -> float:
	return beat_time(step) * LAP_BEATS


func segment_at(t: float) -> Dictionary:
	for i in range(segments.size() - 1, 0, -1):
		if t >= segments[i]["start"]:
			return segments[i]
	return segments[0]


## 음악 시간 t의 박 (연속값). 음수 시간(소리가 나기 전)은 음수 박.
func beat_at(t: float) -> float:
	var seg := segment_at(t)
	return seg["beat"] + (t - seg["start"]) / beat_time(seg["step"])


func distance_at(t: float) -> float:
	return beat_at(t) * BEAT_DISTANCE


func speed_at(t: float) -> float:
	return RunLogic.SPEED * STEPS[segment_at(t)["step"]]["bpm"] / 100.0


## 박 번호의 음악 시간 (도착 시각 측정용)
func time_of_beat(beat: int) -> float:
	for i in range(segments.size() - 1, 0, -1):
		if beat >= segments[i]["beat"]:
			return segments[i]["start"] + (beat - segments[i]["beat"]) * beat_time(segments[i]["step"])
	return segments[0]["start"] + (beat - segments[0]["beat"]) * beat_time(segments[0]["step"])


## 편곡 단계가 오른 순간부터 흐른 시간. 단계가 오르지 않은 구간이면 -1
func stage_up_age(t: float) -> float:
	var i := segments.find(segment_at(t))
	if i == 0 or STEPS[segments[i]["step"]]["stage"] == STEPS[segments[i - 1]["step"]]["stage"]:
		return -1.0
	return t - segments[i]["start"]


## 다음 단계로 올릴 차례면 경계를 구간에 더하고 {at, step}을 돌려준다. 아니면 빈 값.
## lead: 경계가 이만큼 안으로 들어와야 예약한다, min_lead: 이보다 가까운 경계는 늦었으니 한 바퀴 더 돈다 (탭 전환·긴 멈춤).
## next_ready: 다음 곡이 준비됐는가. 안 됐으면 지금 곡이 그대로 한 바퀴 더 돌아 박이 어긋나지 않는다.
func plan(now: float, lead: float, min_lead: float, next_ready: bool) -> Dictionary:
	var last: Dictionary = segments[-1]
	if last["step"] >= STEPS.size() - 1 or not next_ready or now < last["start"]:
		return {}
	var lap := lap_time(last["step"])
	var laps := maxi(ceili((now + min_lead - last["start"]) / lap), 1)
	var at: float = last["start"] + laps * lap
	if at - now > lead:
		return {}
	var step: int = last["step"] + 1
	segments.append({"start": at, "beat": last["beat"] + laps * LAP_BEATS, "step": step})
	return {"at": at, "step": step}
