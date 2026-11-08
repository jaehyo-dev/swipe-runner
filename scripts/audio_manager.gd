extends Node
## 오토로드: 배경 음악과 효과음 재생, 음악 시간(박자 기준)을 맡는다. 버스는 default_bus_layout.tres.

const SFX := {
	&"lane": preload("res://assets/audio/sfx/lane.wav"),
	&"jump": preload("res://assets/audio/sfx/jump.wav"),
	&"slide": preload("res://assets/audio/sfx/slide.wav"),
	&"land": preload("res://assets/audio/sfx/land.wav"),
	&"crash": preload("res://assets/audio/sfx/crash.wav"),
}
const BGM := preload("res://assets/audio/music/bgm.ogg")
const POOL_SIZE := 6
## 소리 균형은 여기서만 바꾼다 (dB). 음악의 A 가중 크기가 효과음(lane·jump·slide 평균)보다 2~3dB 작게.
## 음악 파일은 저음이 많아 A 가중으로 효과음보다 16dB 작다. 음악만 올리면 피크가 넘치므로(웹 샘플 재생엔 리미터도 없다) 효과음을 함께 내렸다.
## 음악 피크 -3.9dBFS + 충돌 피크 -10.7dBFS = 합 0.93 (실측은 review/v0.3.1/loudness.md)
const MUSIC_DB := 4.0
const SFX_DB := -10.0
const LANE_SEMITONES := 1.0     # 왼쪽 -1반음, 오른쪽 +1반음 (ART_BIBLE 9)
const JITTER_SEMITONES := 0.5   # 반복해도 기계적으로 들리지 않게
const DUCK_DB := -8.0
const DUCK_TIME := 1.0          # 음악을 낮춘 뒤 원래대로 돌아올 때까지
const DUCK_FADE := 0.1          # 내려가고 올라오는 데 쓰는 시간 (뚝 끊겨 들리지 않게)

## 소리를 낸 순간 알림 (이름, 재생 속도). 화면 확인 기록과 테스트에서 쓴다.
signal played(sound: StringName, pitch: float)

## 음악 처음부터 흐른 시간. 음악을 시작한 뒤 프레임마다 재생 위치에서 다시 계산한다.
var music_time := 0.0
var music: AudioStreamPlayer

var _clock := BeatClock.new()
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _blocked := false
var _rng := RandomNumberGenerator.new()
var _music_bus := AudioServer.get_bus_index(&"Music")
var _duck: Tween


## 웹의 끊김 없는 반복: Godot 웹 샘플 재생은 소리가 끝난 뒤 새로 시작해 반복 지점에 5~27ms 틈이 생긴다.
## 그래서 export_presets.cfg의 html/head_include에서 30초 넘는 버퍼에 Web Audio의 loop를 켠다. 재생 위치는 BeatClock이 어느 쪽이든 이어 준다.
## 웹의 재생 위치: 엔진 값은 시작 뒤 1초 동안 0에 멈췄다가 그 뒤로 실제보다 1초 늦다(위치 워클릿의 reset). 그래서 head_include가 AudioContext 시간으로 만든 window.musicPosition을 쓴다 (출력 지연까지 뺀 값).
func _ready() -> void:
	AudioServer.set_bus_volume_db(_music_bus, MUSIC_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), SFX_DB)
	music = AudioStreamPlayer.new()
	music.stream = BGM
	music.bus = &"Music"
	add_child(music)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
	# 웹은 소리를 처음 재생할 때 디코딩해 첫 입력 프레임이 막힌다. 로딩 중에 미리 해 둔다
	if OS.has_feature("web"):
		AudioServer.register_stream_as_sample(BGM)
		for sound in SFX:
			AudioServer.register_stream_as_sample(SFX[sound])


func _process(delta: float) -> void:
	if music.playing:
		music_time = _clock.update(_raw_position(), delta)


## 지금 귀에 들리는 음악 위치
func _raw_position() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("window.musicPosition ? window.musicPosition() : 0"))
	var position := music.get_playback_position()
	var latency := AudioServer.get_output_latency()
	if position <= 0.0:  # 아직 소리가 나기 전: 오래된 믹스 시각을 더하면 시간이 앞서 나갔다가 멈춘다
		return -latency
	# 녹화(Movie Maker)는 실제 시간과 무관하게 프레임 단위로 섞으므로 믹스 뒤 흐른 실제 시간을 더하면 안 된다
	var since_mix := 0.0 if Engine.get_write_movie_path() else AudioServer.get_time_since_last_mix()
	return position + since_mix - latency


## 첫 입력 때 부른다 (브라우저는 첫 입력 전에는 소리를 막는다). 이미 재생 중이면 그대로 둔다.
func start_music() -> void:
	if not music.playing:
		music.play()
		_clock = BeatClock.new()
		_clock.time = minf(_raw_position(), 0.0)
		music_time = _clock.time


func play_lane(direction: int) -> void:
	_play(&"lane", direction * LANE_SEMITONES + _jitter())


## "jump", "slide", "land"
func play_action(sound: StringName) -> void:
	_play(sound, _jitter())


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


func unblock() -> void:
	_blocked = false


func _set_music_db(db: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, db)


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
