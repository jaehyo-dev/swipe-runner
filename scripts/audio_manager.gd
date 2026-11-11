extends Node
## 오토로드: 배경 음악과 효과음 재생, 음악 시간(박자 기준)을 맡는다. 버스는 default_bus_layout.tres.

const SFX := {
	&"lane": preload("res://assets/audio/sfx/lane.wav"),
	&"jump": preload("res://assets/audio/sfx/jump.wav"),
	&"slide": preload("res://assets/audio/sfx/slide.wav"),
	&"land": preload("res://assets/audio/sfx/land.wav"),
	&"crash": preload("res://assets/audio/sfx/crash.wav"),
	&"orb": preload("res://assets/audio/sfx/orb.wav"),
	&"combo_break": preload("res://assets/audio/sfx/combo_break.wav"),
	&"close": preload("res://assets/audio/sfx/close.wav"),
}
## MusicLadder.STEPS와 같은 순서 (맨 위 곡 뒤의 단계는 MusicLadder.track으로 마지막 곡)
const TRACKS: Array[AudioStreamOggVorbis] = [
	preload("res://assets/audio/music/bgm_100_orig.ogg"),
	preload("res://assets/audio/music/bgm_105_orig.ogg"),
	preload("res://assets/audio/music/bgm_110_a.ogg"),
	preload("res://assets/audio/music/bgm_115_a.ogg"),
	preload("res://assets/audio/music/bgm_120_b.ogg"),
	preload("res://assets/audio/music/bgm_125_b.ogg"),
	preload("res://assets/audio/music/bgm_130_b.ogg"),
	preload("res://assets/audio/music/bgm_135_b.ogg"),
	preload("res://assets/audio/music/bgm_140_b.ogg"),
	preload("res://assets/audio/music/bgm_145_b.ogg"),
	preload("res://assets/audio/music/bgm_150_b.ogg"),
	preload("res://assets/audio/music/bgm_155_b.ogg"),
	preload("res://assets/audio/music/bgm_160_b.ogg"),
]
const POOL_SIZE := 6
## 소리 균형은 여기서만 바꾼다 (dB). 음악의 A 가중 크기가 효과음(lane·jump·slide 평균)보다 2~3dB 작게.
## 음악 파일은 저음이 많아 A 가중으로 효과음보다 16dB 작다. 음악만 올리면 피크가 넘치므로(웹 샘플 재생엔 리미터도 없다) 효과음을 함께 내렸다.
## 음악 피크 -3.9dBFS + 충돌 피크 -10.7dBFS = 합 0.93 (실측은 review/v0.3.1/loudness.md)
const MUSIC_DB := 4.0
const SFX_DB := -10.0
const LANE_SEMITONES := 1.0     # 왼쪽 -1반음, 오른쪽 +1반음 (ART_BIBLE 9)
const JITTER_SEMITONES := 0.5   # 반복해도 기계적으로 들리지 않게
## 방울 소리가 시끄러워지지 않게 (2026-11-10 사용자): 같은 소리는 동시에 ORB_VOICES개까지, ORB_MERGE초 안에 연달아 먹으면 소리 하나,
## 압박 단계 ORB_FAST_PRESSURE 이상에서는 ORB_FAST_DB만큼 더 작게. 방울 파일 자체가 lane보다 6dB 작다 (review/v0.8.0/sounds)
const ORB_VOICES := 3
const CLOSE_VOICES := 2        # PERFECT "슉"도 같은 소리는 동시에 2개까지 (v0.8.1)
const ORB_MERGE := 0.06
const ORB_FAST_PRESSURE := 6
const ORB_FAST_DB := -3.0
const PENTATONIC: Array[int] = [0, 3, 5, 7, 10]  # 마단조 5음 E G A B D (방울 파일이 E4)
const DUCK_DB := -8.0
const DUCK_TIME := 1.0          # 음악을 낮춘 뒤 원래대로 돌아올 때까지
const DUCK_FADE := 0.1          # 내려가고 올라오는 데 쓰는 시간 (뚝 끊겨 들리지 않게)
const RESTART_FADE := 0.3       # 재시작 때 지금 곡에서 첫 곡으로 겹치며 넘어가는 시간
const MENU_DB := -6.0           # 메인 화면 음악은 게임보다 이만큼 작게
## 경계가 이만큼 안으로 들어오면 다음 곡을 예약한다. 장애물은 z -85(속도 15에서 5.67초 앞)에 나오며 박 → 거리는 경계를 알아야 정해지므로, 첫 장애물보다 먼저 정한다.
const SCHEDULE_LEAD := 7.0
## 이보다 가까운 경계는 4마디 뒤로 미룬다. 위와 같은 이유로 6초보다 길어야 한다 (데스크톱 제너레이터 버퍼 0.5초보다도 길다)
const SCHEDULE_MIN := 6.2
const GENERATOR_BUFFER := 0.5   # RESTART_FADE보다 길어야 겹치는 동안 이전 곡이 끊기지 않는다
const FADE_FLOOR_DB := -60.0
const SWITCH_BLEND := 0.005     # 곡 경계에서 파형이 튀어 딸깍거리지 않게 겹치는 시간. 틈은 없다
const RESAMPLE_HEAD := 2        # mix_audio가 맨 앞에 내놓는 빈 표본 수. 버리지 않으면 곡 이음매마다 틈이 생긴다

## 소리를 낸 순간 알림 (이름, 재생 속도). 화면 확인 기록과 테스트에서 쓴다.
signal played(sound: StringName, pitch: float)

## 판 처음부터 흐른 음악 시간. 음악을 시작한 뒤 프레임마다 재생 위치에서 다시 계산한다.
var music_time := 0.0
## 이번 판의 템포 구간. 곡 경계를 예약할 때 구간이 늘어난다.
var ladder := MusicLadder.new()
## 시작 단계. 평소 0, 개발용 주소 ?bpm=115 또는 녹화 도구가 바꾼다. 재시작도 이 단계로 돌아온다.
var start_step := 0
## 데스크톱 음악 플레이어 (제너레이터). 웹에서는 재생에 쓰지 않는다.
var music: AudioStreamPlayer
## 소리 끔 (메인 화면 버튼): 음악·효과음 모두
var muted := false

var _web: WebMusic
var _web_playing := false
var _players: Array[AudioStreamPlayer] = []
var _gen: AudioStreamGeneratorPlayback
var _feed: AudioStreamPlayback
var _pushed := 0          # 이번 판에 제너레이터에 넣은 표본 수
var _switch_frame := -1   # 이 표본에서 다음 곡으로 바꾼다
var _switch_step := 0
var _switch_from := 0.0   # 다음 곡을 시작할 곡 안 위치(초)
var _waiting_switches: Array[Dictionary] = []  # 빠른 단계는 앞 전환이 일어나기 전에 다음 경계가 정해진다
var _clock := BeatClock.new()
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _orb_pool: Array[AudioStreamPlayer] = []  # 방울 전용: 이 수만큼만 겹친다
var _orb_next := 0
var _close_pool: Array[AudioStreamPlayer] = []  # PERFECT 전용
var _close_next := 0
var _last_orb := -INF  # 마지막 방울 소리 시각(초)
var _blocked := false
var _rng := RandomNumberGenerator.new()
var _music_bus := AudioServer.get_bus_index(&"Music")
var _duck: Tween
var _fades := {}  # 음악 플레이어 -> 볼륨 트윈 (플레이어마다 하나만)


func _ready() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), SFX_DB)
	for track in TRACKS:
		track.loop = true
	for i in 2:  # 재시작 때 두 곡이 겹치므로 두 개
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		add_child(player)
		_players.append(player)
	music = _players[0]
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
	_orb_pool = _voices(&"orb", ORB_VOICES)
	_close_pool = _voices(&"close", CLOSE_VOICES)
	# 웹은 소리를 처음 재생할 때 디코딩해 첫 입력 프레임이 막힌다. 로딩 중에 미리 해 둔다
	if OS.has_feature("web"):
		var bpm := int(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('bpm') || 0")))
		start_step = maxi(MusicLadder.step_of_bpm(bpm), 0)
		ladder = MusicLadder.new(start_step)
		_web = WebMusic.new(start_step)
		for sound in SFX:
			AudioServer.register_stream_as_sample(SFX[sound])
	_set_music_db(MUSIC_DB)


func _process(delta: float) -> void:
	if _web:
		if not _blocked:  # 게임 오버 화면에서는 경계가 계속 밀리므로 곡을 다시 풀지 않는다
			_want_next_track()
		_web.decode_slice()
	if not is_music_on():
		return
	if not _web:
		_pump_generator()
	var beat := MusicLadder.beat_time(ladder.segment_at(music_time)["step"])
	_clock.update(_raw_position(), delta, beat)
	music_time = _clock.smoothed(delta)
	if not _blocked:  # 부딪힌 뒤에는 지금 곡을 그대로 둔다
		_plan_next_track()


func is_music_on() -> bool:
	return _web_playing if _web else music.playing


## 경계가 가까워지면 다음 곡을 예약한다. 재생 위치 기준으로 알려 주므로 시계 보정값을 뺀다.
## shortcut: 오디오가 멈췄다 돌아오면(전화 등) 곡 경계가 반복 끝과 어긋날 수 있다. 박은 맞고 재시작하면 풀린다, 실기기에서 거슬리면 곡을 시계에 맞춰 다시 시작한다.
func _plan_next_track() -> void:
	var plan := ladder.plan(music_time, SCHEDULE_LEAD, SCHEDULE_MIN, _web == null or _next_track_ready())
	if plan.is_empty() or not plan["switch"]:  # 160BPM 뒤 경계는 속도만 오르고 곡은 그대로 돈다
		return
	var at: float = plan["at"] - _clock.offset
	if _web:
		_web.schedule(plan["step"], at, plan["from"])
	else:
		_waiting_switches.append({"frame": roundi(at * AudioServer.get_mix_rate()), "step": plan["step"], "from": plan["from"]})
		_next_switch()


## 데스크톱: 지금 기다리는 전환이 없으면 다음 전환을 꺼낸다
func _next_switch() -> void:
	if _switch_frame >= 0 or _waiting_switches.is_empty():
		return
	var next: Dictionary = _waiting_switches.pop_front()
	_switch_frame = maxi(next["frame"], _pushed)  # 지연이 커서 이미 넣은 표본을 지났으면 바로 다음 표본에서
	_switch_step = next["step"]
	_switch_from = next["from"]


## 웹: 다음 경계에서 필요한 곡 구간을 미리 풀어 둔다
func _want_next_track() -> void:
	var edge := ladder.next_edge(music_time, SCHEDULE_MIN)
	if edge["switch"]:
		_web.want(edge["step"], edge["from"])


func _next_track_ready() -> bool:
	var edge := ladder.next_edge(music_time, SCHEDULE_MIN)
	return not edge["switch"] or _web.is_ready(edge["step"], edge["from"])


## 지금 귀에 들리는 음악 위치 (판 시작 기준)
func _raw_position() -> float:
	if _web:
		return _web.position()
	var position := music.get_playback_position()
	var latency := AudioServer.get_output_latency()
	if position <= 0.0:  # 아직 소리가 나기 전: 오래된 믹스 시각을 더하면 시간이 앞서 나갔다가 멈춘다
		return -latency
	# 녹화(Movie Maker)는 실제 시간과 무관하게 프레임 단위로 섞으므로 믹스 뒤 흐른 실제 시간을 더하면 안 된다
	var since_mix := 0.0 if Engine.get_write_movie_path() else AudioServer.get_time_since_last_mix()
	return position + since_mix - latency


## 곡을 from초 위치부터 표본 단위로 읽는 재생기. 곡 끝에서 곡 처음으로 이어진다 (track.loop)
func open_track(track: AudioStream, from := 0.0) -> AudioStreamPlayback:
	var playback := track.instantiate_playback()
	playback.start(from)
	playback.mix_audio(1.0, RESAMPLE_HEAD)
	return playback


## 데스크톱: 곡 표본을 제너레이터에 넣는다. 경계 표본에서 곡을 바꾸므로 틈이 없다.
func _pump_generator() -> void:
	var room := _gen.get_frames_available()
	while room > 0:
		var n := room if _switch_frame < 0 else mini(room, _switch_frame - _pushed)
		if n > 0:
			_gen.push_buffer(_feed.mix_audio(1.0, n))
			_pushed += n
			room -= n
		if _pushed == _switch_frame:
			var blend := roundi(SWITCH_BLEND * AudioServer.get_mix_rate())
			if room < blend:
				return
			var next := open_track(TRACKS[_switch_step], _switch_from)
			var old_part := _feed.mix_audio(1.0, blend)
			var new_part := next.mix_audio(1.0, blend)
			for i in blend:
				old_part[i] = old_part[i].lerp(new_part[i], float(i) / blend)
			_gen.push_buffer(old_part)
			_pushed += blend
			room -= blend
			_feed = next
			_switch_frame = -1
			_next_switch()


## 새 판의 음악을 첫 곡 0초부터 튼다. fade초 동안 지금 곡과 겹친다.
func _begin_music(fade: float) -> void:
	ladder = MusicLadder.new(start_step)
	_clock = BeatClock.new()
	if _web:
		_web.play(start_step, fade)
		_web_playing = true
	else:
		var old := music
		music = _players[1 - _players.find(old)]
		_stop_fade(music)  # 이 플레이어가 아직 앞 판에서 사라지는 중이면(메인 화면에 오자마자 시작) 그 페이드와 정지를 취소한다
		if old.playing:
			_fade_out(old, fade)
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = AudioServer.get_mix_rate()
		stream.buffer_length = GENERATOR_BUFFER
		music.stream = stream
		music.volume_db = 0.0
		music.play()
		if fade > 0.0:
			music.volume_db = FADE_FLOOR_DB
			_volume_tween(music).tween_property(music, "volume_db", 0.0, fade)
		_gen = music.get_stream_playback()
		_feed = open_track(TRACKS[start_step])
		_pushed = 0
		_switch_frame = -1
		_waiting_switches.clear()
		_pump_generator()
	_clock.time = minf(_raw_position(), 0.0)
	_clock.smooth = _clock.time
	music_time = _clock.time


func _stop_fade(player: AudioStreamPlayer) -> void:
	if _fades.has(player):
		_fades[player].kill()


## 플레이어의 앞 볼륨 트윈을 멈추고 새 트윈을 준다
func _volume_tween(player: AudioStreamPlayer) -> Tween:
	_stop_fade(player)
	_fades[player] = create_tween()
	return _fades[player]


func _fade_out(player: AudioStreamPlayer, fade: float) -> void:
	var tween := _volume_tween(player)
	tween.tween_property(player, "volume_db", FADE_FLOOR_DB, fade)
	tween.tween_callback(player.stop)


## 첫 입력 때 부른다 (브라우저는 첫 입력 전에는 소리를 막는다). 이미 재생 중이면 그대로 둔다.
func start_music() -> void:
	if not is_music_on():
		_begin_music(0.0)


## 재시작: 지금 곡에서 첫 곡 0초로 겹치며 넘어가고, 박 계산은 이 순간을 0초로 다시 센다.
func restart_music() -> void:
	_begin_music(RESTART_FADE if is_music_on() else 0.0)


func play_lane(direction: int) -> void:
	_play(&"lane", direction * LANE_SEMITONES + _jitter())


## "jump", "slide", "land"
func play_action(sound: StringName) -> void:
	_play(sound, _jitter())


## 방울 줄 안에서 streak번째(1부터)로 먹은 방울의 높이: 5음을 따라 오르고 다섯 개마다 한 옥타브 위
static func orb_semitones(streak: int) -> int:
	var i := maxi(streak - 1, 0)
	return PENTATONIC[i % PENTATONIC.size()] + 12 * (i / PENTATONIC.size())


## 방울 "톡". now: 지금 시각(초, 테스트에서 넣는다). 소리를 냈으면 true
func play_orb(streak: int, pressure: int, now := Time.get_ticks_usec() / 1000000.0) -> bool:
	if _blocked or now - _last_orb < ORB_MERGE:
		return false
	_last_orb = now
	var player := _orb_pool[_orb_next]
	_orb_next = (_orb_next + 1) % ORB_VOICES
	player.pitch_scale = pow(2.0, orb_semitones(streak) / 12.0)
	player.volume_db = ORB_FAST_DB if pressure >= ORB_FAST_PRESSURE else 0.0
	player.play()
	played.emit(&"orb", player.pitch_scale)
	return true


func play_combo_break() -> void:
	_play(&"combo_break", 0.0)


## PERFECT "슉": 매번 ±0.5반음 흔들림, 동시에 CLOSE_VOICES개까지 (가장 오래된 것을 다시 쓴다)
func play_close() -> void:
	if _blocked:
		return
	var player := _close_pool[_close_next]
	_close_next = (_close_next + 1) % CLOSE_VOICES
	player.pitch_scale = pow(2.0, _jitter() / 12.0)
	player.play()
	played.emit(&"close", player.pitch_scale)


## 한 소리 전용 재생기 count개 (이 수만큼만 겹친다)
func _voices(sound: StringName, count: int) -> Array[AudioStreamPlayer]:
	var pool: Array[AudioStreamPlayer] = []
	for i in count:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.stream = SFX[sound]
		add_child(player)
		pool.append(player)
	return pool


## 충돌: 음악을 잠깐 낮추고, 다시 시작할 때까지 다른 효과음을 막는다.
func play_crash() -> void:
	_play(&"crash", 0.0)
	_blocked = true
	if _duck:
		_duck.kill()
	_duck = create_tween()
	_duck.tween_method(_set_music_db, AudioServer.get_bus_volume_db(_music_bus), MUSIC_DB + DUCK_DB, DUCK_FADE)
	_duck.tween_interval(DUCK_TIME - DUCK_FADE * 2.0)
	_duck.tween_method(_set_music_db, MUSIC_DB + DUCK_DB, MUSIC_DB, DUCK_FADE)


## 새 판: 효과음을 다시 내고 음악을 원래 크기로 (충돌 때 낮춘 것, 메인 화면에서 작게 둔 것)
func unblock() -> void:
	_blocked = false
	_music_level(MUSIC_DB)


## 메인 화면: 첫 곡을 처음부터 게임보다 MENU_DB 작게 튼다. 다음 곡으로 넘어가지 않고(첫 곡 구간이 돈다) 효과음도 내지 않는다
func play_menu_music() -> void:
	_begin_music(RESTART_FADE if is_music_on() else 0.0)
	_blocked = true
	_music_level(MUSIC_DB + MENU_DB)


func _music_level(db: float) -> void:
	if _duck:
		_duck.kill()
	_set_music_db(db)


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(0, on)
	_set_music_db(AudioServer.get_bus_volume_db(_music_bus))


func _set_music_db(db: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, db)
	if _web:  # 웹 음악은 엔진 버스를 거치지 않고 바로 나가므로 소리 끔도 여기서
		_web.set_db(-120.0 if muted else db)


func _jitter() -> float:
	return _rng.randf_range(-JITTER_SEMITONES, JITTER_SEMITONES)


func _play(sound: StringName, semitones: float) -> void:
	if _blocked:
		return
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = SFX[sound]
	player.pitch_scale = pow(2.0, semitones / 12.0)
	player.play()
	played.emit(sound, player.pitch_scale)
