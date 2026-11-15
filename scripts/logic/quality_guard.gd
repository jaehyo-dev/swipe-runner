class_name QualityGuard
extends RefCounted
## 렉 줄이기 계산 (자동 테스트 대상). 3D를 그리는 해상도 상한과, 프레임이 밀릴 때 효과를 한 단계씩 낮추는 판단을 맡는다.
## 낮춘 효과 단계는 다시 올리지 않는다: 오르내리면 화면이 깜빡인다.
## v0.12.1: 3D 배율(dpr_cap)은 여유가 있으면 2.0 → 2.5 → 3.0으로 올린다. 밀리면 효과보다 배율을 먼저 내리고, 내린 배율과 효과를 낮춘 뒤에는 이번 실행에서 다시 올리지 않는다
## (요청은 "30초 동안 올리지 않음"이었지만 30초 뒤 다시 올렸다 내리면 그 반복이 끊김으로 보인다).
## 판단 기준은 화면 갱신 간격(interval)에 맞춘다: 아이폰 저전력 모드(30Hz)에서 모든 프레임을 '느림'으로 보고 끝까지 낮추지 않게.

const MAX_HEIGHT := 1920.0    # 세로 1280 × 기기 화소 1.5배
const MAX_PIXELS := 2880.0 * 1620.0  # 맥북 전체 화면처럼 가로로 넓은 창은 세로 상한만으로 부족하다 (review/v0.5.1/perf_mac.md)
const WINDOW := 1.0           # 이만큼(초)의 프레임을 모아 한 번 판단한다
const LIMIT := 1.2            # 한 구간의 99% 프레임이 화면 갱신 간격의 이 배(60Hz 20ms, 30Hz 40ms)보다 길면 느린 구간
const SLOW_WINDOWS := 3       # 느린 구간이 이만큼 연속(3초)일 때만 한 단계 낮춘다
const GRACE := 5.0            # 페이지를 연 뒤, 탭이 가려졌다 돌아온 뒤, 화면 전환·단계를 낮춘 뒤 이 시간(초)은 판단하지 않는다
const IGNORE_OVER := 0.25     # 이보다 긴 멈춤은 탭 전환 같은 것이라 렉이 아니다 (돌아온 뒤 GRACE만큼 쉰다)
## v0.11.1 순서 (젤리 투명감·장애물 테두리 빛·글자는 어느 단계에서도 그대로): 1 반사 끄기, 2 빛 줄기 줄이기, 3 넓게 퍼지는 빛 번짐 층 끄기, 4 MSAA 4x → 2x (휴대폰은 처음부터 2x). MSAA는 2x 아래로 내리지 않는다
const LEVELS := 4
const MAX_DPR := 2.0          # 3D 기본 배율 상한 (아이폰 배율 3: 1179x2556 → 786x1704). 글자는 원래 해상도
const DPR_STEP := 0.5         # AUTO가 여유 있을 때 올리는 배율 한 칸: 2.0 → 2.5 → 3.0
const DPR_TOP := 3.0          # 배율 상한 (HIGH)
const ROOM := 0.7             # 3초 동안 99% 프레임의 일하는 시간이 갱신 간격의 이 비율 이하면 여유
const HZ30 := Vector2(0.030, 0.037)  # 한 구간의 25%·75% 프레임 간격이 모두 이 안이면 30Hz 화면(저전력 모드)
const SETTINGS := ["auto", "high", "low"]  # 설정 GRAPHICS: AUTO(밀리면 낮춤) / HIGH(0단계 고정) / LOW(가장 낮은 단계 고정)
const STREAK_LOW := 0.35      # 1단계부터 빛 줄기를 이 비율로

var level := 0
## AUTO가 정한 3D 배율 상한 (render_scale의 cap)
var dpr_cap := MAX_DPR
## 올려 볼 수 있는 가장 높은 배율. main.gd가 기기 배율(top_for)로 줄이고, 밀려서 내린 배율은 여기서 빠진다
var top_cap := DPR_TOP
## 지금 화면 갱신 간격(초). 120Hz 화면도 60Hz 기준으로 판단한다 (기준이 빡빡해지지 않게)
var interval := 1.0 / 60.0
## 마지막으로 바꾼 이유 (콘솔 기록용)
var reason := ""

var _frames: Array[float] = []
var _sum := 0.0
var _grace := GRACE
var _slow: Array[float] = []  # 연속된 느린 구간의 99% 프레임(초)
var _work: Array[float] = []  # 이번 구간 프레임마다 일한 시간(초). 모르면 비어 있다
var _room := 0                # 연속 여유 구간 수
var _hz30_done := false       # 30Hz 때 한 단계 낮추기는 한 번만


## 창 크기(실제 화소)에서 3D를 그릴 배율. 글자는 이 배율과 상관없이 원래 해상도로 그려진다.
## dpr: 기기 배율(devicePixelRatio). cap: 3D 배율 상한. 세로·화소 상한도 cap에 비례해 넓어진다 (2.0이면 예전 그대로)
static func render_scale(size: Vector2i, dpr := 1.0, cap := MAX_DPR) -> float:
	if size.x <= 0 or size.y <= 0:
		return 1.0
	var k := cap / MAX_DPR
	return minf(minf(minf(1.0, MAX_HEIGHT * k / size.y), k * sqrt(MAX_PIXELS / (size.x * size.y))), cap / maxf(dpr, cap))


## 설정과 AUTO 배율로 정한 실제 3D 배율 상한
static func cap_for(setting: String, auto_cap: float) -> float:
	match setting:
		"high":
			return DPR_TOP
		"low":
			return MAX_DPR
	return auto_cap


## 기기 배율로 올려 볼 수 있는 가장 높은 배율 (배율 2 이하 화면은 올릴 것이 없다)
static func top_for(dpr: float) -> float:
	return clampf(floorf(dpr / DPR_STEP) * DPR_STEP, MAX_DPR, DPR_TOP)


## 설정과 자동 단계로 정한 실제 효과 단계
static func level_for(setting: String, auto_level: int) -> int:
	match setting:
		"high":
			return 0
		"low":
			return LEVELS
	return auto_level


## 품질 단계 level에서 그릴 빛 줄기 수
static func streaks(count: float, at_level: int) -> int:
	return int(count * (STREAK_LOW if at_level >= 2 else 1.0))


## seconds초 동안 판단하지 않는다. 모으던 구간과 연속 기록도 버린다
func hold(seconds := GRACE) -> void:
	_grace = maxf(_grace, seconds)
	_frames.clear()
	_work.clear()
	_sum = 0.0
	_slow.clear()
	_room = 0


static func _pick(sorted: Array[float], q: float) -> float:
	return sorted[int((sorted.size() - 1) * q)]


## 프레임 간격(초)과 그 프레임에 일한 시간(초, 모르면 음수)을 넣는다.
## 이번에 효과 단계·배율을 바꿨으면 true (이유는 reason, 바뀐 값은 level·dpr_cap)
func push(frame: float, work := -1.0) -> bool:
	if frame > IGNORE_OVER:
		hold()
		return false
	if _grace > 0.0:
		_grace -= frame
		return false
	_frames.append(frame)
	if work >= 0.0:
		_work.append(work)
	_sum += frame
	if _sum < WINDOW:
		return false
	_frames.sort()
	_work.sort()
	var p99 := _pick(_frames, 0.99)
	var hz30 := _pick(_frames, 0.25) >= HZ30.x and _pick(_frames, 0.75) <= HZ30.y
	var work99 := _pick(_work, 0.99) if _work.size() * 2 >= _frames.size() else INF  # 일한 시간을 절반 넘게 못 받았으면 여유를 모른다
	_frames.clear()
	_work.clear()
	_sum = 0.0
	if hz30 != (interval > 0.025):
		interval = 1.0 / (30.0 if hz30 else 60.0)
		if hz30 and not _hz30_done:  # 저전력 모드: CPU 여유를 위해 효과 한 단계, 배율은 기본으로
			_hz30_done = true
			if level < LEVELS or dpr_cap > MAX_DPR:
				level = mini(level + 1, LEVELS)
				dpr_cap = MAX_DPR
				reason = "30Hz 화면: 효과 %d단계, 배율 %.1f" % [level, dpr_cap]
				hold()
				return true
		hold(1.0)
		return false
	var limit := interval * LIMIT
	if p99 > limit:
		_room = 0
		if level >= LEVELS and dpr_cap <= MAX_DPR:  # 더 낮출 것이 없다
			return false
		_slow.append(p99)
		if _slow.size() < SLOW_WINDOWS:
			return false
		var times := ", ".join(_slow.map(func(x: float) -> String: return "%.1f" % (x * 1000.0)))
		if dpr_cap > MAX_DPR:  # 올렸던 배율부터 되돌린다. 그 배율은 이번 실행에서 다시 올리지 않는다
			top_cap = dpr_cap - DPR_STEP
			dpr_cap = top_cap
		else:
			level += 1
		reason = "99%% 프레임 %s ms가 %d초 연속 %.0fms 초과 → 효과 %d단계, 배율 %.1f" % [times, SLOW_WINDOWS, limit * 1000.0, level, dpr_cap]
		hold()  # 낮춘 직후의 셰이더 준비 끊김으로 연달아 낮추지 않게
		return true
	_slow.clear()
	# 여유: 밀린 프레임이 없고 일하는 시간이 간격의 ROOM배 이하. 효과를 낮춘 적이 있거나 30Hz면 올리지 않는다
	if work99 > interval * ROOM or level > 0 or interval > 0.025 or dpr_cap >= top_cap:
		_room = 0
		return false
	_room += 1
	if _room < SLOW_WINDOWS:
		return false
	dpr_cap = minf(dpr_cap + DPR_STEP, top_cap)
	reason = "%d초 동안 99%% 일하는 시간 %.1fms ≤ %.1fms → 배율 %.1f" % [SLOW_WINDOWS, work99 * 1000.0, interval * ROOM * 1000.0, dpr_cap]
	hold()  # 해상도를 바꾼 직후 끊김으로 바로 내리지 않게
	return true
