extends Node3D
## 게임 화면. 환경(하늘·안개·글로우), 길, 주인공, 장애물, 거리 표시를 만들고 입력을 받는다.
## 계산은 scripts/logic/ 의 클래스가 맡고, 여기서는 그 결과를 화면에 옮기기만 한다.

const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const BLOCK_SHADER := preload("res://shaders/block.gdshader")
const PILLAR_SHADER := preload("res://shaders/pillar.gdshader")
const NEON_SHADER := preload("res://shaders/neon.gdshader")
const MIRROR_SHADER := preload("res://shaders/mirror.gdshader")
const DASH_SHADER := preload("res://shaders/dash.gdshader")
const STREAK_SHADER := preload("res://shaders/streak.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const ORB_SHADER := preload("res://shaders/orb.gdshader")
const ORB_HALO_SHADER := preload("res://shaders/orb_halo.gdshader")
const ORB_LINK_SHADER := preload("res://shaders/orb_link.gdshader")
const ORB_RING_SHADER := preload("res://shaders/orb_ring.gdshader")
const FONT := preload("res://assets/fonts/Poppins-ExtraLight.ttf")
## 장애물 종류별 팔레트 이름 (색은 data/speed_palette.json). 파랑 = 옆으로, 주황 = 위로, 분홍 = 아래로.
const KINDS := {
	ObstacleField.Kind.BLOCK: "block",
	ObstacleField.Kind.LOW: "low",
	ObstacleField.Kind.HIGH: "high",
}
const MAX_PIECES := 96       # 종류마다 동시에 그릴 수 있는 장애물 수. z -85~+6에 들어오는 수보다 넉넉하다
const FOLLOW_GAP := 22.0     # 같은 레인의 앞 블록이 이만큼 안이면 연속 블록으로 본다 (2박 + 조금)
const FOLLOW_HAZE := 0.3     # 연속 블록의 뒤쪽 것이 안개 색으로 흐려지는 양
const FLOOR_HAZE_FROM := 0.4  # 바닥 안개 띠는 안개 거리의 이 비율에서 시작한다
const FOG_DENSITY := 0.025   # 안개 거리 약 30~45에서 하늘 아래 먼 세상을 덮는 값. 세상 전체의 안개. 장애물만 안개를 끄고 직접 섞는다 (block.gdshader)
const GLOW_INTENSITY := 1.3  # 얇은 관에서도 바깥으로 빛이 번지게
const GLOW_WIDE := 0.6       # 넓게 퍼지는 번짐 층

const RESTART_DELAY := 0.5
const OBSTACLE_FADE := 0.15  # 다시 시작할 때 앞 판 장애물이 작아져 사라지는 시간(초): 한 프레임에 툭 없어지지 않게
const POP_TIME := 0.25       # 다시 시작할 때 대시 격자가 '퐁' 나타나는 시간(초). 장애물은 안개에서 나온다
const PREWARM_FRAMES := 3    # 가림막 뒤에서 이만큼 연달아 빠른 프레임이 나오면 준비 끝 (셰이더는 그래픽 쪽에서 늦게 끝날 수 있다)
const PREWARM_FAST_MS := 50
const PREWARM_MAX_FRAMES := 120  # 아주 느린 기기도 언젠가는 화면을 연다
const WARM_MAX_FRAMES := 20      # 2단계 한 묶음에 쓰는 최대 프레임: 셰이더는 첫 프레임에 만들어지고, 느린 기기도 시작을 오래 기다리지 않게
const PREWARM_TINY := 0.002     # 메인 화면 뒤에서 미리 그릴 때의 크기: 그리기는 하지만 한 화소도 안 된다
const DRIFT_TIME := 3.0
const GAME_URL := "https://jaehyo-dev.github.io/swipe-runner/"
const COPIED_TIME := 0.8
## 휴대폰(누르는 화면)에 공유 창이 있으면 그걸 쓰고 "share", 아니면 클립보드에 복사하고 "copy". 클립보드 권한이 거부되면 옛 복사(execCommand)로 한 번 더
## shortcut: COPIED는 복사 결과를 기다리지 않고 보인다. 둘 다 실패하는 브라우저가 보고되면 결과를 엔진에 돌려받는다
const SHARE_JS := """(() => { const t = %s, u = %s;
if (navigator.share && matchMedia('(pointer: coarse)').matches) { navigator.share({text: t, url: u}).catch(() => {}); return 'share'; }
const all = t + ' ' + u;
const old = () => { const area = document.createElement('textarea'); area.value = all; document.body.appendChild(area); area.select(); document.execCommand('copy'); area.remove(); };
if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(all).catch(old); return 'copy'; }
old(); return 'copy'; })()"""
const RESUME_WAIT_FRAMES := 20   # 이어 할 때 소리가 다시 돌기를 기다리는 최대 프레임 (못 돌아도 게임은 이어진다)
const STAGE_GLOW_TIME := 0.3  # 음악 단계가 오를 때 난간과 빛 대시가 밝아지는 시간(초)
## 무대 (ART_BIBLE.md 10). 밝기 순서: 주인공 > 장애물 기호 > 테두리·파란 기둥 > 난간 > 빛 줄기 > 바닥·하늘
const ROAD_PEAK_MAX := StageLight.ROAD_PEAK  # 평소 대시의 가장 센 채널이 이보다 밝아지지 않는다
const TINT_RESTART_TIME := 0.5  # 재시작 때 색이 돌아가는 시간(초)
const SKY_RADIUS := 1500.0
const RAIL_X := 2.38            # 난간 관 위치: 슬라이드로 퍼진 몸(1.5 + 0.775)이 닿지 않는 바깥
const RAIL_Y := 0.1
const RAIL_RADIUS := 0.1
const DASH_SIZE := Vector3(0.07, 0.02, 1.0)  # 레인 경계 빛 대시. 길이는 속도에 맞춰 셰이더가 늘린다 (dash_length)
const STREAK_MAX := 64          # 빛 줄기 풀 (data/speed_palette.json의 t = 1 값)
const STREAK_SEED := 606        # 줄기 자리를 고정하는 시드
const STREAK_X := Vector2(2.9, 8.0)  # 길 바깥 좌우 거리
const STREAK_Y := Vector2(2.6, 7.0)  # 방울(높이 2.0까지)과 겹쳐 보이지 않게 길 위쪽 공간 위주로
const FOV_SLOW := 62.0       # 시야각: 색 진하기와 함께 속도가 오른 뒤 2마디 동안 넓어진다
const FOV_FAST := 68.0
const POP_SCALE := 1.22      # 새 기록 순간 거리 숫자가 커지는 배율 (말랑)
const POP_UP := 0.08
const POP_DOWN := 0.32
## 10000점 (ScoreBoard.MILESTONE)을 넘는 순간: 더 크게 말랑 + 연보라 빛이 확 번졌다가 옅게 남고, 숫자는 그 판 동안 연보라
const MILESTONE_POP := 1.32
const MILESTONE_GLOW_TIME := 0.6
const MILESTONE_COLOR := Color("e4dbff")   # 숫자 색: 흰색에 가까운 연보라 (방울 테 c9b8ff보다 밝게, 읽기 쉽게)
const MILESTONE_HALO := Color("c9b8ff")    # 숫자 둘레 빛 = 방울 테 색
## 빛 방울과 점수 연출 (ART_BIBLE.md 13)
const ORB_MAX := 48            # 방울 풀: z -85~+6에 들어오는 방울 수보다 넉넉하다 (반 박 간격 줄, 줄 사이 빈 박)
const ORB_RADIUS := 0.21       # 지름 0.42 (보이는 크기만, 먹기 범위는 OrbTrail 그대로)
const ORB_ENERGY := 1.62       # 밝기 순서: 장애물 테두리(1.7 이상) > 방울(+ 박 빛 0.06) > 난간(단계 빛남 때도 1.6 이하). tools/brightness_order.gd가 검사
const ORB_PULSE_ENERGY := 0.06
const ORB_HALO_SIZE := 1.1     # 빛 번짐 판의 폭 (연보라 바깥 테)
const ORB_LINK_WIDTH := 0.035  # 한 줄의 방울을 잇는 빛 실선 굵기
const RING_TIME := 0.15        # 먹을 때 주인공 둘레에 퍼지는 빛 고리 시간
const ABSORB_TIME := 0.12      # 먹은 방울이 주인공 쪽으로 빨려 들어가며 사라지는 시간
const MISS_FADE := 0.1         # 놓친 방울이 작아지며 사라지는 시간
const MISS_GONE_Z := 1.5       # 놓친 방울은 이 z 전에 완전히 없어진다
const MULT_POP := 1.35         # 배수가 오를 때 커지는 배율
const MULT_DROP := 60.0        # 콤보가 끊기면 배수 글자가 떨어지는 거리(px)
const MULT_DROP_TIME := 0.35
const MULT_TOP := 262.0        # 글자 위치(px, 720x1280 기준): 점수 아래 배수, 그 아래 BEST, 게임 오버 한 줄
const BEST_TOP := 330.0
const STATS_TOP := 384.0
## PERFECT (ART_BIBLE.md 13): BEST 바로 아래 한 줄 "PERFECT ×3  +300", BEST와 같은 글자. 살짝 '톡' 자리 잡고 머문 뒤 제자리에서 흐려진다
const PERFECT_TOP := BEST_TOP + (BEST_TOP - MULT_TOP)  # 줄 간격 = 배수와 BEST 사이
const PERFECT_POP := 1.1
const PERFECT_POP_TIME := 0.1
const PERFECT_HOLD := 0.6
const PERFECT_FADE := 0.25
const COUNT_TIME := 0.3        # PERFECT 점수만큼 점수 숫자가 세어 올라가는 시간
const SWISH_ALPHA := 0.35      # 주인공 옆을 스치는 흰 빛 줄기 세기. 0이면 끈다 (v0.8.1: 0.9 → 짧고 옅게)
const SWISH_TIME := 0.1
const SWISH_SIZE := Vector3(0.03, 0.03, 2.2)
const SWISH_FROM := -2.5
const SWISH_TO := 2.5
const SWISH_SIDE := 0.62       # 주인공 가운데에서 옆으로
const BOOT_COLOR := Color(0.02, 0.016, 0.051)  # project.godot boot_splash/bg_color와 같은 색: 로딩에서 가림막으로 이어져 보이게
## 메인 화면 (ART_BIBLE.md 14): 같은 무대에 젤리가 서서 박마다 숨 쉬고, 시작하면 카메라가 게임 자리로 들어간다
const GAME_CAM := Vector3(0.0, 3.3, 5.4)
const GAME_LOOK := Vector3(0.0, 0.7, -8.0)
const MENU_CAM := Vector3(0.0, 2.0, 4.6)    # 낮고 가깝게: 젤리가 크게, 위쪽 하늘에 제목 자리
const MENU_LOOK := Vector3(0.0, 1.5, -8.0)
## 짧은 창(세로/가로 MENU_SHORT 미만: PC, 거의 정사각형 창)은 젤리가 화면 아래를 채워 SWIPE TO START 자리가 없다: 조금 멀리서 본다
const MENU_SHORT := 1.75
## v0.11.0: 젤리 아래에 스킨 이름·점이 들어가 더 멀리, 시선은 낮게 (젤리가 화면 59~68%, 웅덩이 앞 끝 70%)
const MENU_CAM_SHORT := Vector3(0.0, 2.2, 8.5)
const MENU_LOOK_SHORT := Vector3(0.0, 1.2, -8.0)
const POOL_FRONT_Z := 1.25   # 젤리 빛 웅덩이·반사의 앞(화면 아래) 끝. SWIPE TO START는 이 아래에 둔다
const TITLE_FADE := 0.3      # 시작할 때 제목·안내가 흐려지는 시간 (점수 글자는 같은 시간에 나타난다)
const CAMERA_IN := 0.6       # 시작할 때 카메라가 게임 자리로 들어가는 시간
const HOME_FADE := 0.4       # 게임 오버 → 메인 화면 페이드 (반은 어두워지고 반은 밝아진다)
const MENU_FLOW := 3.0       # 메인 화면에서 빛 대시가 흐르는 속도 (게임 첫 속도 15의 1/5)
const MENU_STREAKS := 4      # 메인 화면의 빛 줄기 수 (아주 적게)
const FLIP_OUT := 0.12       # 스킨 넘기기: 젤리가 옆으로 밀려나며 작아지는 시간
const FLIP_IN := 0.13        # 다음 젤리가 반대쪽에서 들어오는 시간 (합 0.25초)
const FLIP_X := 1.2          # 밀려나는 거리(m). 가로 화면은 화면 끝이 멀어 날려 보내지 않고 거리 + 작아짐으로
const FLIP_SCALE := 0.6
const NEW_SKIN_TOP := 450.0  # 게임 오버 NEW SKIN 묶음 (세로: 한 줄 아래, 가로: 오른쪽 칸)
const PREVIEW_SIZE := Vector2(150.0, 130.0)
## 웹: 브라우저가 실제로 그린 프레임 간격(requestAnimationFrame)을 모은다. 엔진 _process 안에서 잰 간격은 화면이 멀쩡해도 크게 흔들려
## 자동 낮춤이 잘못 걸렸다 (review/v0.9.0/quality.md: rAF 16.8ms인 2초 동안 _process 간격 99% 25.8ms)
const FRAMES_JS := "window.gameFrames = []; { let last = 0; const tick = t => { if (last) window.gameFrames.push(t - last); last = t; requestAnimationFrame(tick); }; requestAnimationFrame(tick); }"
const FRAMES_POLL := 30      # 이 프레임마다 모인 간격을 한 번에 가져온다
const PERF_REFRESH := 0.25   # 성능 표시 글자를 바꾸는 간격(초)

## 0이면 실행할 때마다 무작위. 테스트에서는 0이 아닌 값을 줘서 장애물 레인을 고정한다.
@export var seed_value := 0
## 최고 기록 파일. 테스트는 임시 파일을 준다 (설정 파일도 그 옆의 임시 파일을 쓴다)
@export var best_path := BestRecord.PATH

var lane := RunLogic.START_LANE
## 이번 판에 이동한 거리. 화면 숫자는 이 값의 정수 부분.
var travel := 0.0
## 지금 세상이 다가오는 속도
var speed := RunLogic.SPEED
var record: BestRecord  # 이번 판의 기록: 일반 모드는 normal_record, 오늘의 판은 daily
var normal_record: BestRecord
var daily: DailyRecord     # 오늘의 판 기록 (일반 최고 점수와 다른 파일)
var daily_mode := false    # 오늘의 판 시작 화면이거나 오늘의 판을 하는 중
## 0 이상이면 지금 시각(유닉스 초, UTC) 대신 쓴다 (테스트용 시간 덮어쓰기)
var clock_override := -1.0
var save: SaveData  # 플레이 횟수(조작 안내)·소리 켜기/끄기
var score := ScoreBoard.new()
var field: ObstacleField
var runner: Runner
var player := PlayerAction.new()
var dead := false
## 첫 입력을 받았는가. 그 전에는 세상이 멈춰 있고 장애물만 미리 놓여 있다 (브라우저가 첫 입력 전엔 소리를 막으므로).
var started := false
## 셰이더 미리 준비가 끝났는가. 첫 화면은 이때 드러난다.
var prewarmed := false
## 메인 화면이 뜬 뒤 장애물·방울·효과 셰이더까지 다 준비했다
var warmed := false
## 일시정지 중 (숫자 세는 동안 포함)
var paused := false
var haptics := Haptics.new()

var _swipe := SwipeDetector.new()
var _obstacles := {}  # id -> Piece
var _leaving: Array[Piece] = []  # 재시작 때 작아지며 사라지는 앞 판 장애물
var _pieces_dirty := true        # 장애물이 생기거나 없어지거나 크기가 변해 MultiMesh를 다시 써야 한다
var _animating := 0              # 크기가 변하는 중인 트윈 수
var _pieces_root: Node3D         # 장애물 MultiMesh의 부모. 세상과 함께 움직여 장애물마다 값을 바꾸지 않는다
var _floor_material: ShaderMaterial
var _rail_material: ShaderMaterial
var _dashes: MultiMeshInstance3D
var _dash_material: ShaderMaterial
var _streak_material: ShaderMaterial
var _streaks: MultiMesh
var _kind_meshes := {}  # Kind -> {body, mirror: MultiMesh, block, reflect: ShaderMaterial}, 기둥은 pillar: ShaderMaterial (반투명 몸통)
var _sky_material: ShaderMaterial
var _env: Environment
var _rail_base := 1.0    # 지금 진하기의 난간 빛 세기
var _tint := -1.0        # 지금 화면의 색 진하기
var _stage_glow := 0.0   # 지금의 단계 빛남 (1 → 0)
var _fog := Vector2(-1.0, -1.0)  # 지금 안개 (진해지기 시작하는 거리, 사라지는 거리)
var _stretch := 1.0      # 160BPM 속도보다 빠를 때 대시·빛 줄기 길이 배율
var _dash_len := 1.2     # 지금 진하기의 대시·빛 줄기 길이 (배율 전)
var _streak_len := 1.9
var _tint_from := -1.0   # 재시작 순간의 진하기. 음수면 돌아가는 중이 아니다
var _tint_clock := 0.0   # 재시작 순간의 음악 시간
var _row_beats: Array[float] = []  # 칸마다 지금 담긴 박. 바뀐 칸만 다시 쓴다
var _row_segments := 0            # 대시 줄을 쓸 때의 사다리 구간 수. 구간이 늘면 앞으로 올 줄의 자리가 바뀐다
var _row_ladder: MusicLadder
var _quality := QualityGuard.new()
var _effect_level := 0  # 지금 적용된 효과 단계
var phone := false        # 누르는 화면(휴대폰·태블릿): MSAA를 처음부터 2x로
var dpr := 1.0            # 기기 배율 (devicePixelRatio)
var perf := PerfStats.new()  # 숨은 성능 표시의 프레임 통계
var _perf_label: Label
var _dev_points := 0.0
var _used_slots := {}         # _sync_pieces가 다시 쓰는 종류별 칸 수
var _far_first := _is_farther
var _perf_wait := 0.0
var _title: TitleScreen
var _hud: Control          # 게임 중 글자(점수·BEST·배수·PERFECT·게임 오버). 메인 화면에서는 숨는다
var _home: UiIcon          # 게임 오버 왼쪽 위 집 버튼
var _pause_btn: UiIcon     # 플레이 중 왼쪽 위 ‖ (게임 오버·메인 화면에서는 숨김)
var _pause_menu: PauseMenu
var _settings: SettingsPanel
var _begin_waiting := false  # 준비가 끝나기 전에 시작을 눌렀다: 남은 것을 그리고 시작한다
var _page_callback: JavaScriptObject  # 웹 탭 가림 알림 (붙들고 있어야 사라지지 않는다)
var _fade: ColorRect       # 게임 오버 → 메인 화면 페이드
var _going_home := false
var _menu_t := 0.0         # 메인 화면에서 흐른 시간 (음악이 없을 때의 박, 대시 흐름)
var _menu_beat := -1       # 숨쉬기를 한 마지막 박
var _menu_cam := MENU_CAM
var _menu_look := MENU_LOOK
var _view := 0.0           # 1 = 메인 화면 카메라, 0 = 게임 카메라. 메인 화면의 첫 프레임에 1로 간다
var _view_tween: Tween
var _dead_time := 0.0
var _restart_label: Label
var _camera: Camera3D
var _score_label: Label
var _best_label: Label
var _pop: Tween
var _over_milestone := false  # 이번 판이 10000점을 넘었나
var _milestone_tween: Tween
var _scroll := 0.0
var _music_t := 0.0  # 박자 기준 시간
var _orbs: MultiMesh
var _halos: MultiMesh
var _orb_material: ShaderMaterial
var _halo_material: ShaderMaterial
var _links: MultiMesh             # 한 줄의 이웃 방울을 잇는 빛 실선
var _link_material: ShaderMaterial
var _ring: MeshInstance3D          # 먹을 때 퍼지는 빛 고리
var _ring_material: ShaderMaterial
var _ring_from := -INF            # 마지막으로 먹은 음악 시각 (고리는 음악 시간으로 돈다)
var _orb_prewarm := false  # 가림막 뒤에서 방울 재질을 한 번 그린다
var _mult_label: Label
var _mult_shown := 1       # 화면에 보이는 배수
var _mult_tween: Tween
var _perfect_label: Label       # "PERFECT ×3  +300" 한 줄
var _perfect_tween: Tween
var _perfect_chain := 0          # 앞 PERFECT가 사라지기 전에 이어진 수
var _count_lag := 0.0            # 아직 숫자에 안 올라간 PERFECT 점수
var _count_rate := 0.0           # 초당 올라가는 점수
var _stats_label: Label
var _swish: MeshInstance3D
var _swish_material: StandardMaterial3D
var _share: Label          # 오늘의 판 게임 오버의 SHARE
var shared_text := ""      # 마지막으로 공유·복사한 글 (테스트에서 확인)
var _share_tween: Tween
var _final_score := 0      # 게임 오버 점수 (SHARE 글)
var _menu_second := -1     # 오늘의 판 남은 시간을 고친 마지막 초
var skins: SkinBook        # 스킨 해금 진행도·고른 스킨
var skin_view := 0         # 메인 화면에서 보고 있는 스킨 번호 (잠긴 스킨일 수 있다)
var _flip: Tween
var _new_skin: Control     # 게임 오버 NEW SKIN 묶음 (글자·미리보기·EQUIP)
var _new_skin_preview: SkinPreview
var _equip: Label
var new_skin_id := ""      # 이번 게임 오버에 새로 열린 스킨 (EQUIP 대상)


## 장애물 하나의 화면 상태. 노드 대신 MultiMesh 한 칸에 옮겨 그린다.
class Piece:
	extends RefCounted
	var kind: int
	var position: Vector3
	var scale := Vector3.ONE
	var haze := 0.0
	var item: Dictionary       # 이 장애물의 판정 항목
	var wide := 0.0            # 1이면 이웃 레인까지 덮는 2칸 벽
	var hidden := false        # 2칸 벽의 짝: 판정 항목만 있고 그림은 벽 하나가 맡는다


## 오늘의 판은 그날의 씨앗. 시드를 고정했으면(주소의 ?seed, 테스트) 판마다 같은 배치, 아니면 판마다 새 배치
## shortcut: 개발용 ?bpm(시작 단계)으로 열면 오늘의 판도 배치가 달라진다. 일반 사용자는 쓰지 않는 주소라 막지 않는다
func _new_field() -> void:
	var s := DailyRecord.seed_of(daily.day) if daily_mode else (seed_value if seed_value != 0 else randi() | 1)
	field = ObstacleField.new(s, AudioManager.ladder)


## 지금 시각(유닉스 초, UTC)과 오늘 날짜
func now_unix() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_unix_time_from_system()


func today() -> int:
	return DailyRecord.day_of(now_unix())


func _ready() -> void:
	if seed_value == 0 and OS.has_feature("web"):
		# 화면 확인 기록(review/)을 같은 배치로 다시 찍을 수 있게 주소의 ?seed=숫자를 읽는다
		seed_value = int(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') || 0")))
	if best_path == BestRecord.PATH:  # 실제 게임만: 이름이 바뀌기 전 폴더의 기록을 옮겨 온다 (테스트·도구는 임시 파일)
		var copied := SaveData.migrate(SaveData.old_user_dir(), OS.get_user_data_dir())
		print("SAVE %s (옛 폴더에서 옮긴 파일 %d개)" % [OS.get_user_data_dir(), copied])  # 저장 위치 확인용 한 줄
		# v0.11.1: 점수가 0.5배 → 옛 기록을 새 파일로 한 번만 반으로 옮긴다 (스킨 진행도는 SkinBook이 형식 1 → 2로)
		print("SCORE V2 best %s daily %s" % [BestRecord.convert_old(), DailyRecord.convert_old()])
	normal_record = BestRecord.new(best_path)
	record = normal_record
	daily = DailyRecord.new(DailyRecord.DAILY_PATH if best_path == BestRecord.PATH else best_path.get_basename() + "_daily.cfg", today())
	if OS.has_feature("web") and str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('dailyhash') || ''")) == "1":
		print("DAILYHASH\n" + DailyRecord.hash_report(30))  # 기기 비교용 (tools/daily_hash.gd와 같은 표)
	save = SaveData.new(SaveData.PATH if best_path == BestRecord.PATH else best_path.get_basename() + "_settings.cfg")
	skins = SkinBook.new(SkinBook.PATH if best_path == BestRecord.PATH else best_path.get_basename() + "_skins.cfg")
	skins.absorb_records(maxi(normal_record.best, daily.best_ever()), daily.streak)  # 이미 넘은 기록의 스킨은 바로 열린다
	AudioManager.set_muted(save.muted)
	AudioManager.set_volumes(save.music, save.sfx)
	haptics = Haptics.detect()
	haptics.enabled = save.vibration
	_new_field()
	_build_environment()
	_build_camera()
	_build_floor()
	_build_obstacle_resources()
	_build_orbs()
	_apply_tint(AudioManager.ladder.tint_at(0.0))
	_apply_fog(AudioManager.ladder, 0.0)
	_place_rows()
	runner = Runner.new()
	runner.position = Vector3(RunLogic.lane_x(lane), 0.0, 0.0)
	add_child(runner)
	_build_ui()
	if OS.has_feature("web"):
		phone = int(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches ? 1 : 0")) == 1  # 웹은 JS 참·거짓을 정수로 돌려준다
	apply_graphics(save.graphics)
	if OS.has_feature("web"):
		_dev_view()
	skin_view = SkinBook.index_of(skins.selected)
	_apply_skin_view()
	get_viewport().size_changed.connect(_fit_camera)
	get_viewport().size_changed.connect(_fit_render_scale)
	_fit_camera()
	_fit_render_scale()
	_show_title()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FRAMES_JS, true)
		_watch_page()
	_prewarm()


func _process(delta: float) -> void:
	advance(delta, AudioManager.music_time)
	_sync_pieces()
	_sync_orbs()
	if OS.has_feature("web") and warmed:
		_watch_frames()
	elif not OS.has_feature("web"):
		perf.push(delta)
	if _perf_label.visible:
		_perf_wait -= delta
		if _perf_wait <= 0.0:
			_perf_wait = PERF_REFRESH
			_show_perf()


## 숨은 성능 표시: 왼쪽 위 빠른 세 번 탭(PC는 F3)으로 켜고 끈다
func toggle_perf() -> void:
	_perf_label.visible = not _perf_label.visible
	_perf_wait = 0.0
	if _perf_label.visible:
		_show_perf()


func _show_perf() -> void:
	var render := Vector2i(Vector2(DisplayServer.window_get_size()) * get_viewport().scaling_3d_scale)
	_perf_label.text = perf.text(render, _effect_level, save.graphics, dpr)


## 브라우저가 그린 프레임 간격으로 밀림을 판단해 효과를 한 단계 낮춘다 (기준은 QualityGuard)
func _watch_frames() -> void:
	if Engine.get_process_frames() % FRAMES_POLL != 0:
		return
	for ms in str(JavaScriptBridge.eval("window.gameFrames.splice(0).join()")).split(",", false):
		perf.push(ms.to_float() / 1000.0)
		if save.graphics == "auto" and _quality.push(ms.to_float() / 1000.0):
			apply_quality(_quality.level)
			print("QUALITY %d %.1f %s" % [_quality.level, Time.get_ticks_msec() / 1000.0, _quality.reason])  # 언제, 왜 낮췄는지


## 효과 단계 (QualityGuard.LEVELS): 1 반사 끄기, 2 빛 줄기 줄이기, 3 넓은 빛 번짐 층 끄기, 4 MSAA 2x. 이 단계까지 전부 적용하고 위 단계는 되돌린다 (설정으로 올릴 수 있다)
func apply_quality(level: int) -> void:
	_effect_level = level
	var t := _tint
	_tint = -1.0
	_apply_tint(t)  # 줄기 수는 진하기 값과 함께 정해진다
	for kind in _kind_meshes:
		_kind_meshes[kind]["reflect"].set_shader_parameter("reflect_on", 0.0 if level >= 1 else 1.0)
	runner.set_reflection(level < 1)
	_env.set_glow_level(3, 0.0 if level >= 3 else GLOW_WIDE)
	get_viewport().msaa_3d = Viewport.MSAA_2X if level >= 4 or phone else Viewport.MSAA_4X


## 설정 GRAPHICS를 적용한다. AUTO로 돌아오면 자동 단계를 처음부터 다시 판단한다
func apply_graphics(setting: String) -> void:
	if setting == "auto":
		_quality = QualityGuard.new()
	apply_quality(QualityGuard.level_for(setting, _quality.level))


## 3D만 낮은 해상도로 그리고 늘린다. 글자는 원래 해상도 그대로다.
func _fit_render_scale() -> void:
	if OS.has_feature("web"):  # 브라우저 확대·창 옮김으로 바뀔 수 있다
		dpr = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	get_viewport().scaling_3d_scale = QualityGuard.render_scale(DisplayServer.window_get_size(), dpr)


## 메인 화면의 시작 입력: 음악 0초와 함께 세상이 출발한다. 제목은 흐려지고 카메라가 게임 자리로 들어간다.
## 첫 실행은 이 입력이 오디오를 켠다(브라우저 정책). 메인 화면 음악이 흐르고 있었으면 첫 곡 0초로 겹치며 넘어간다
func begin() -> void:
	started = true
	_end_flip()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gameStarted = performance.now()")  # 첫 판 프레임 측정의 시작점
	_quality.hold()
	save.count_play()
	if daily_mode:  # 날짜는 시작하는 순간에 다시 센다: 시작 화면을 띄운 채 자정이 지났을 수 있다
		daily.start(today())
	if AudioManager.is_music_on():
		AudioManager.restart_music()
	else:
		AudioManager.start_music()
	AudioManager.unblock()
	_dash_material.set_shader_parameter("sparkle_on", 1.0)
	if daily_mode:
		_new_field()
	field.ladder = AudioManager.ladder  # 음악과 함께 시작한 사다리: 경계가 여기에 쌓인다
	_music_t = AudioManager.music_time
	runner.running = true
	_pause_btn.visible = true
	var t := _tint
	_tint = -1.0
	_apply_tint(t)  # 메인 화면에서 줄인 빛 줄기 수를 되돌린다
	record.begin_run()
	_show_best()
	_move_world()
	_pop_dashes()  # 대시가 메인 화면의 흐르던 자리에서 박 자리로 옮겨 가는 순간을 가린다
	var fade := create_tween().set_parallel()
	fade.tween_property(_title, "modulate:a", 0.0, TITLE_FADE)
	fade.tween_property(_hud, "modulate:a", 1.0, TITLE_FADE)
	fade.chain().tween_callback(_title.hide)
	if _view_tween:
		_view_tween.kill()
	_view_tween = create_tween()
	_view_tween.tween_method(_set_view, _view, 0.0, CAMERA_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 카메라를 메인 화면 자리(1)와 게임 자리(0) 사이에 둔다
func _set_view(k: float) -> void:
	_view = k
	_camera.position = GAME_CAM.lerp(_menu_cam, k)
	_camera.look_at(GAME_LOOK.lerp(_menu_look, k))


## 메인 화면: 젤리는 제자리에서 박마다 숨 쉬듯 부풀었다 튀고, 빛 대시와 몇 안 되는 빛 줄기가 천천히 흐른다. 장애물은 없다
func _advance_menu(delta: float) -> void:
	_menu_t += delta
	var music := AudioManager.is_music_on()
	var beat := AudioManager.ladder.beat_at(AudioManager.music_time) if music else _menu_t / MusicLadder.beat_time(AudioManager.start_step)
	_title.pulse(beat)
	if floori(_menu_t) != _menu_second:  # 오늘의 판 번호·남은 시간은 1초마다 (자정이 지나면 새 판)
		_menu_second = floori(_menu_t)
		_refresh_daily()
	runner.running = false
	if floori(beat) != _menu_beat:
		_menu_beat = floori(beat)
		runner.absorb()  # 방울을 먹을 때의 작은 부풂과 속빛을 박마다
	if _view != 1.0 and not _going_home:
		_set_view(1.0)
	_hud.modulate.a = 0.0
	var ladder := AudioManager.ladder
	_dashes.position.z = fposmod(_menu_t * MENU_FLOW, ladder.distance_of_beat(BeatRows.ROW_BEATS) - ladder.distance_of_beat(0.0))
	_dash_material.set_shader_parameter("pulse", BeatRows.pulse(fposmod(beat, 1.0) * MusicLadder.beat_time(AudioManager.start_step)))
	_scroll += MENU_FLOW * delta
	_streak_material.set_shader_parameter("scroll", _scroll)
	_streaks.visible_instance_count = mini(MENU_STREAKS, _streaks.visible_instance_count)


## delta초만큼 게임을 진행한다 (테스트에서도 직접 호출). music_t: 음악 시간. 안 주면(테스트) delta만큼 흐른 것으로 친다.
## 세상은 음악 시간에서 계산한 이동 거리만큼 움직이고, 주인공 동작은 프레임 시간으로 움직인다.
func advance(delta: float, music_t := NAN) -> void:
	_music_t = _music_t + delta if is_nan(music_t) else music_t
	if dead:
		_advance_dead(delta)
		return
	player.step(delta)
	_play_action_sounds()
	runner.lift = player.height()
	runner.crouch = player.crouch()
	if not started:
		_advance_menu(delta)
		return
	_move_world()
	for item in field.items:
		var dx := runner.position.x - RunLogic.lane_x(item["lane"])
		if not item.has("cleared") and PlayerAction.hits(item["kind"], dx, PlayerAction.swept_dz(item), player.height(), player.is_ducking()):
			_count_lag = 0.0  # 게임 오버 숫자는 바로 최종 점수
			_show_score()
			_game_over(item)
			return
	_on_watch(score.watch(field, runner.position.x, player.height(), player.crouch(), lane, _music_t, speed))
	_show_score(delta)


## 점수 숫자와 최고 기록. PERFECT 점수는 COUNT_TIME 동안 세어 올라간다 (기록은 바로 반영)
func _show_score(delta := 0.0) -> void:
	_count_lag = maxf(_count_lag - _count_rate * delta, 0.0)
	var total := score.total(travel)
	_score_label.text = str(total - ceili(_count_lag))
	if record.update(total):
		_on_new_record()
	if not _over_milestone and total >= ScoreBoard.MILESTONE:
		_on_milestone()


## 이번 프레임에 먹은 방울·끊긴 콤보·아슬아슬의 소리와 연출
func _on_watch(result: Dictionary) -> void:
	var pressure := BeatPattern.pressure(AudioManager.ladder.beat_at(_music_t))
	for orb: Dictionary in result["taken"]:
		AudioManager.play_orb(orb["streak"], pressure)
		runner.absorb()
	if not result["taken"].is_empty():
		_ring_from = _music_t
	if result["broke"]:
		AudioManager.play_combo_break()
	for close: Dictionary in result["close"]:
		AudioManager.play_close()
		_on_close(close["item"], close["points"])
	_show_multiplier(result["broke"])


## 배수 글자: ×2 이상일 때만. 오르면 말랑 커졌다 돌아오고, 끊기면 아래로 떨어지며 사라진다
func _show_multiplier(broke: bool) -> void:
	var now := ScoreBoard.multiplier(score.combo)
	if now == _mult_shown:
		return
	var was := _mult_shown
	_mult_shown = now
	if _mult_tween:
		_mult_tween.kill()
	_mult_label.pivot_offset = _mult_label.size * 0.5
	if broke or now < was:
		_mult_tween = create_tween().set_parallel()
		_mult_tween.tween_property(_mult_label, "position:y", _mult_label.position.y + MULT_DROP, MULT_DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_mult_tween.tween_property(_mult_label, "modulate:a", 0.0, MULT_DROP_TIME)
		_mult_tween.chain().tween_callback(_reset_multiplier)
		return
	_reset_multiplier()
	_mult_label.text = "×%d" % now
	_mult_label.visible = true
	_mult_tween = create_tween()
	_mult_tween.tween_property(_mult_label, "scale", Vector2.ONE * MULT_POP, POP_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_mult_tween.tween_property(_mult_label, "scale", Vector2.ONE, POP_DOWN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reset_multiplier() -> void:
	_mult_label.visible = false
	_mult_label.modulate.a = 1.0
	_mult_label.scale = Vector2.ONE
	_mult_label.position.y = MULT_TOP


## PERFECT(아슬아슬): 주인공 옆을 스치는 짧고 옅은 빛 줄기, 점수 아래 "PERFECT"와 더해진 점수.
## 앞 PERFECT가 사라지기 전에 또 나오면 "PERFECT ×2", "×3"… 숫자만 바뀌고 다시 '톡'
func _on_close(item: Dictionary, points: int) -> void:
	if SWISH_ALPHA > 0.0:
		var side := signf(RunLogic.lane_x(item["lane"]) - runner.position.x)
		_swish.position = Vector3(runner.position.x + (side if side != 0.0 else -1.0) * SWISH_SIDE, 0.45 + player.height(), SWISH_FROM)
		_swish.visible = true
		var swish := create_tween().set_parallel()
		swish.tween_property(_swish, "position:z", SWISH_TO, SWISH_TIME)
		swish.tween_property(_swish_material, "albedo_color:a", 0.0, SWISH_TIME).from(SWISH_ALPHA)
		swish.chain().tween_callback(_swish.hide)
	_count_lag += points
	_count_rate = _count_lag / COUNT_TIME
	haptics.fire(Haptics.Event.PERFECT)
	_perfect_chain = _perfect_chain + 1 if _perfect_label.visible else 1
	_perfect_label.text = ("PERFECT" if _perfect_chain == 1 else "PERFECT ×%d" % _perfect_chain) + "  +%d" % points
	if _perfect_tween:
		_perfect_tween.kill()
	_perfect_label.visible = true
	_perfect_label.modulate.a = 1.0
	_perfect_label.pivot_offset = _perfect_label.size * 0.5
	_perfect_label.scale = Vector2.ONE * PERFECT_POP
	_perfect_tween = create_tween()
	_perfect_tween.tween_property(_perfect_label, "scale", Vector2.ONE, PERFECT_POP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_perfect_tween.tween_interval(PERFECT_HOLD)
	_perfect_tween.tween_property(_perfect_label, "modulate:a", 0.0, PERFECT_FADE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_perfect_tween.tween_callback(_perfect_label.hide)


func _hide_perfect() -> void:
	if _perfect_tween:
		_perfect_tween.kill()
	_perfect_label.visible = false
	_count_lag = 0.0


## 방울 MultiMesh를 다시 쓴다 (많아야 수십 개). 먹은 방울은 ABSORB_TIME 동안 주인공 가운데로 빨려 들며 작아진다.
func _sync_orbs() -> void:
	var used := 0
	var center := runner.position + Vector3(0.0, player.height() + OrbTrail.body_height(player.crouch()) * 0.5, 0.0)
	if _orb_prewarm:
		_put_orb(0, Vector3(0.0, 0.6, -5.0), PREWARM_TINY)
		used = 1
	for orb: Dictionary in field.orbs:
		if used >= ORB_MAX:
			break
		var at := Vector3(orb["x"], orb["y"], orb["z"])
		var size := 1.0
		if orb.has("taken"):
			var k := clampf((_music_t - orb["taken"]) / ABSORB_TIME, 0.0, 1.0)
			if k >= 1.0:
				continue
			at = at.lerp(center, ease(k, 0.5))
			size = 1.0 - k
		elif orb.has("missed"):  # 놓친 방울: MISS_FADE초 안에, 늦어도 z MISS_GONE_Z 전에 작아져 없어진다 (카메라 앞에서 커지지 않게)
			var k := maxf((_music_t - orb["missed"]) / MISS_FADE, (orb["z"] - OrbTrail.PICK_Z) / (MISS_GONE_Z - OrbTrail.PICK_Z))
			if k >= 1.0:
				continue
			size = 1.0 - k
		_put_orb(used, at, size)
		used += 1
	_orbs.visible_instance_count = used
	_halos.visible_instance_count = used
	var links := 0
	var prev: Dictionary = {}
	for orb: Dictionary in field.orbs:
		if links >= ORB_MAX:
			break
		# 같은 줄의 바로 다음 방울끼리만, 둘 다 아직 안 먹었을 때 잇는다
		if not prev.is_empty() and prev["trail"] == orb["trail"] and orb["index"] == prev["index"] + 1 and not prev.has("taken") and not orb.has("taken") and orb["z"] < 0.0 and prev["z"] < 0.0:  # 지나친 방울로 이으면 카메라 쪽으로 큰 사선이 생긴다
			var a := Vector3(prev["x"], prev["y"], prev["z"])
			var b := Vector3(orb["x"], orb["y"], orb["z"])
			var basis := Basis.looking_at(b - a).scaled_local(Vector3(1.0, 1.0, a.distance_to(b)))
			_links.set_instance_transform(links, Transform3D(basis, (a + b) * 0.5))
			links += 1
		prev = orb
	if _orb_prewarm:  # 실선 셰이더도 가림막 뒤에서 한 번 그려 첫 줄에서 멈칫하지 않게
		_links.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * PREWARM_TINY), Vector3(0.0, 0.6, -5.5)))
		links = maxi(links, 1)
	_links.visible_instance_count = links
	# 먹은 순간 주인공 둘레에 작은 빛 고리가 퍼졌다 사라진다 (RING_TIME). 연달아 먹으면 처음부터 다시
	var age := (_music_t - _ring_from) / RING_TIME
	_ring.visible = _orb_prewarm or (age >= 0.0 and age < 1.0)
	_ring.scale = Vector3.ONE * (PREWARM_TINY if _orb_prewarm else 1.0)
	if _ring.visible:
		_ring.position = center
		_ring_material.set_shader_parameter("age", 0.0 if _orb_prewarm else age)


func _put_orb(slot: int, at: Vector3, size: float) -> void:
	_orbs.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
	_halos.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * size), at))


## 음악 시간에서 이동 거리·속도·대시 박자·단계 빛남을 구해 세상에 옮긴다.
func _move_world() -> void:
	var ladder := AudioManager.ladder
	var now := ladder.distance_at(_music_t)
	_scroll += now - travel
	travel = now
	speed = ladder.speed_at(_music_t)
	_streak_material.set_shader_parameter("scroll", _scroll)
	_place_rows()
	_apply_tint(_tint_now())
	_apply_fog(ladder, _music_t)
	_apply_stretch(maxf(speed / MusicLadder.STEPS[MusicLadder.TOP]["speed"], 1.0))
	var beat := ladder.beat_at(_music_t)
	var beat_time := MusicLadder.beat_time(ladder.segment_at(_music_t)["step"])
	var pulse := BeatRows.pulse(fposmod(beat, 1.0) * beat_time)
	_dash_material.set_shader_parameter("pulse", pulse)
	_orb_material.set_shader_parameter("pulse", pulse)
	_halo_material.set_shader_parameter("pulse", pulse)
	_link_material.set_shader_parameter("pulse", pulse)
	var age := ladder.stage_up_age(_music_t)
	var stage := 1.0 - age / STAGE_GLOW_TIME if age >= 0.0 and age < STAGE_GLOW_TIME else 0.0
	_set_stage_glow(maxf(stage, StageLight.wall_flash(ladder.wall_age(_music_t))))  # 고비: 0.4초 가장 세게 (밝기 순서 상한은 그대로)
	_apply_step(field.step(travel, ladder.spawn_distance_at(_music_t)))


## 대시 줄을 지금 박 자리에 놓는다. 음악 시간에서 바로 계산하므로 템포가 바뀌어도 박 줄은 박에 주인공 옆에 닿는다.
## 줄은 이동 거리 좌표로 고정해 두고 부모만 움직인다. 값을 쓰는 칸은 새로 들어온 박과, 구간이 늘어 자리가 바뀐 줄뿐이다.
func _place_rows() -> void:
	var ladder := AudioManager.ladder
	_dashes.position.z = ladder.distance_at(_music_t)
	var now_beat := ladder.beat_at(_music_t)
	var rewrite := ladder != _row_ladder or ladder.segments.size() != _row_segments
	_row_ladder = ladder
	_row_segments = ladder.segments.size()
	for i in BeatRows.COUNT:
		var beat := BeatRows.beat_of(i, now_beat)
		var slot := BeatRows.slot_of(beat)
		if not rewrite and _row_beats[slot] == beat:
			continue
		_row_beats[slot] = beat
		for side in 2:
			var origin := Vector3((side - 0.5) * RunLogic.LANE_WIDTH, DASH_SIZE.y * 0.5, -ladder.distance_of_beat(beat))
			_dashes.multimesh.set_instance_transform(slot * 2 + side, Transform3D(Basis.IDENTITY, origin))


## 지금의 색 진하기: 사다리 값. 재시작 뒤 0.5초는 그 순간의 진하기에서 부드럽게 돌아간다.
func _tint_now() -> float:
	var target := AudioManager.ladder.tint_at(_music_t)
	if _tint_from < 0.0:
		return target
	var back := (_music_t - _tint_clock) / TINT_RESTART_TIME
	if back >= 1.0:
		_tint_from = -1.0
		return target
	return lerpf(_tint_from, target, smoothstep(0.0, 1.0, maxf(back, 0.0)))


## 안개 거리(속도 × 보이는 시간)를 장애물·대시·난간·바닥에 똑같이 넣는다. 값이 그대로면 아무것도 하지 않는다.
func _apply_fog(ladder: MusicLadder, t: float) -> void:
	var fog := Vector2(ladder.fog_clear_at(t), ladder.fog_at(t))
	if fog == _fog:
		return
	_fog = fog
	var materials: Array[ShaderMaterial] = [_dash_material, _rail_material, _orb_material, _halo_material, _link_material]
	for shape: Dictionary in _kind_meshes.values():
		materials.append(shape["block"])
		materials.append(shape["reflect"])
		if shape.has("pillar"):
			materials.append(shape["pillar"])
	for material in materials:
		material.set_shader_parameter("fog_near", fog.x)
		material.set_shader_parameter("fog_far", fog.y)
	_floor_material.set_shader_parameter("haze_near", fog.y * FLOOR_HAZE_FROM)
	_floor_material.set_shader_parameter("haze_far", fog.y)


## 160BPM 뒤 속도가 계속 오르면 대시와 빛 줄기도 그만큼 길어진다 (시야각은 68°에서 멈춘다)
func _apply_stretch(stretch: float) -> void:
	if stretch == _stretch:
		return
	_stretch = stretch
	_streak_material.set_shader_parameter("streak_length", _streak_len * stretch)
	_dash_material.set_shader_parameter("dash_length", _dash_len * stretch)


## 진하기 t의 색을 재질 값으로만 옮긴다. 새 재질을 만들지 않아 셰이더를 다시 준비할 일이 없고, 값이 그대로면 아무것도 하지 않는다.
func _apply_tint(t: float) -> void:
	if t == _tint:
		return
	_tint = t
	var c := SpeedPalette.at(t)
	_sky_material.set_shader_parameter("top", c["sky_top"])
	_sky_material.set_shader_parameter("horizon", c["horizon"])
	_sky_material.set_shader_parameter("curve", c["sky_band"])
	_env.fog_light_color = c["horizon"]
	_floor_material.set_shader_parameter("road_color", c["floor"])
	_floor_material.set_shader_parameter("rail_color", c["rail"])
	_floor_material.set_shader_parameter("haze_color", c["horizon"])
	_rail_material.set_shader_parameter("color", c["rail"])
	_rail_base = c["rail_energy"]
	var rail: Color = c["rail"]
	_dash_material.set_shader_parameter("color", rail)
	_dash_material.set_shader_parameter("max_energy", ROAD_PEAK_MAX / maxf(rail.r, maxf(rail.g, rail.b)))
	_set_stage_glow(_stage_glow)
	_streaks.visible_instance_count = QualityGuard.streaks(c["streak_count"], _effect_level)
	_streak_len = c["streak_length"]
	_dash_len = c["dash_length"]
	_streak_material.set_shader_parameter("streak_length", _streak_len * _stretch)
	_streak_material.set_shader_parameter("level", c["streak_alpha"])
	_dash_material.set_shader_parameter("dash_length", _dash_len * _stretch)
	_rail_material.set_shader_parameter("fog_color", c["horizon"])
	_camera.fov = lerpf(FOV_SLOW, FOV_FAST, t)
	for kind: ObstacleField.Kind in KINDS:
		var name_: String = KINDS[kind]
		var shape: Dictionary = _kind_meshes[kind]
		var edge: Color = c[name_ + "_edge"]
		var body: Color = c.get(name_ + "_body", c["body"])  # 옆 장애물만 자기 몸통 색(파랑)이 있다
		shape["block"].set_shader_parameter("body_color", body)
		shape["block"].set_shader_parameter("tint", c[name_])
		shape["block"].set_shader_parameter("edge_color", edge)
		if c.has(name_ + "_mark"):  # 기둥에는 기호가 없다
			shape["block"].set_shader_parameter("mark_color", c[name_ + "_mark"])
		shape["block"].set_shader_parameter("fog_color", c["horizon"])
		if shape.has("pillar"):
			shape["pillar"].set_shader_parameter("body_color", body)
			shape["pillar"].set_shader_parameter("fog_color", c["horizon"])
		shape["reflect"].set_shader_parameter("body_color", body)
		shape["reflect"].set_shader_parameter("edge_color", Color(minf(edge.r, 1.0), minf(edge.g, 1.0), minf(edge.b, 1.0)))  # 화면 범위로 줄인 빛 색


## 단계가 오를 때의 빛남 (1 → 0)을 난간과 대시에 준다.
func _set_stage_glow(amount: float) -> void:
	_stage_glow = amount
	_rail_material.set_shader_parameter("energy", StageLight.energy(_rail_base, amount))
	_dash_material.set_shader_parameter("stage_add", amount * (StageLight.PEAK_MAX - StageLight.ROAD_PEAK))


## field.step() 결과를 장애물 노드에 옮긴다.
func _apply_step(result: Dictionary) -> void:
	for item in result["spawned"]:
		_spawn_node(item)
	for id in result["removed"]:
		_obstacles.erase(id)
		_pieces_dirty = true
	for item in field.items:
		_obstacles[item["id"]].position.z = item["z"]


func _animation_done() -> void:
	_animating -= 1
	_pieces_dirty = true  # 마지막 크기까지 옮긴다


## 바뀐 프레임에만 MultiMesh 값을 쓴다. 보통 프레임은 부모 위치만 움직인다.
func _sync_pieces() -> void:
	_pieces_root.position.z = _scroll
	if not _pieces_dirty and _animating == 0:
		return
	_pieces_dirty = false
	var used := _used_slots  # v0.11.1: 프레임마다 새 사전을 만들지 않는다
	for kind in _kind_meshes:
		used[kind] = 0
	for piece: Piece in _pieces_far_first():
		if piece.hidden:
			continue
		var slot: int = used[piece.kind]
		if slot >= MAX_PIECES:
			continue
		used[piece.kind] = slot + 1
		var at := Transform3D(Basis.from_scale(piece.scale), Vector3(piece.position.x, piece.position.y, piece.position.z - _scroll))
		var shape: Dictionary = _kind_meshes[piece.kind]
		shape["body"].set_instance_transform(slot, at)
		var custom := Color(piece.haze, piece.wide, 0.0, 0.0)
		shape["body"].set_instance_custom_data(slot, custom)
		shape["mirror"].set_instance_transform(slot, at)
		shape["mirror"].set_instance_custom_data(slot, custom)
	for kind in _kind_meshes:
		_kind_meshes[kind]["body"].visible_instance_count = used[kind]
		_kind_meshes[kind]["mirror"].visible_instance_count = used[kind]


## 반투명 기둥은 MultiMesh 안의 순서대로 쌓이므로 먼 것부터 쓴다
func _pieces_far_first() -> Array:
	var pieces: Array = _obstacles.values() + _leaving
	pieces.sort_custom(_far_first)  # 비교 함수는 한 번만 만든다 (장애물이 움직이는 동안 매 프레임)
	return pieces


static func _is_farther(a: Piece, b: Piece) -> bool:
	return a.position.z < b.position.z


## 부딪힌 뒤: 세상이 아주 잠깐 느려졌다 멈추고, 주인공은 충돌 모션을 이어 간다.
func _advance_dead(delta: float) -> void:
	var slow := CrashMotion.slow_delta(_dead_time, delta)
	_dead_time += delta
	_scroll += speed * slow
	_streak_material.set_shader_parameter("scroll", _scroll)
	_dashes.position.z += speed * slow
	for item in field.items:
		item["z"] += speed * slow
		_obstacles[item["id"]].position.z = item["z"]
	for orb in field.orbs:
		orb["z"] += speed * slow
	runner.crash_t = _dead_time
	var shake := CrashMotion.shake(_dead_time)
	_camera.h_offset = shake.x
	_camera.v_offset = shake.y
	_restart_label.visible = _dead_time >= RESTART_DELAY
	_home.visible = _restart_label.visible
	_new_skin.visible = _restart_label.visible and not new_skin_id.is_empty()
	_share.visible = _restart_label.visible and daily_mode


## 부딪혔다: 실수로 바로 넘기지 않게 잠깐 뒤부터 다시 시작할 수 있다.
func _game_over(item: Dictionary) -> void:
	dead = true
	_dead_time = 0.0
	_pause_btn.visible = false
	haptics.fire(Haptics.Event.CRASH)
	AudioManager.play_crash()
	_set_stage_glow(0.0)
	_dash_material.set_shader_parameter("pulse", 0.0)
	_dash_material.set_shader_parameter("sparkle_on", 0.0)
	record.save()
	_final_score = score.total(travel)
	_best_label.visible = true
	_best_label.text = ("NEW %sBEST %d" if record.broken else "%sBEST %d") % ["DAILY " if daily_mode else "", record.best]
	if daily_mode:  # 오늘의 판: 점수, DAILY BEST, 도전 횟수, SHARE
		_stats_label.text = "TRIES %d" % daily.tries
	else:
		_stats_label.text = "ORBS %d · PERFECT %d · %dm" % [score.orbs, score.close, int(travel)]
	_stats_label.visible = true
	_show_new_skin(_finish_run())
	if _mult_tween:  # 게임 오버 화면은 점수·BEST·한 줄만
		_mult_tween.kill()
	_reset_multiplier()
	_hide_perfect()
	_orb_material.set_shader_parameter("pulse", 0.0)
	_halo_material.set_shader_parameter("pulse", 0.0)
	# 느려지는 동안 장애물이 조금 더 다가오므로 그만큼 앞으로 간 면에 붙는다
	var z: float = item["z"] + speed * CrashMotion.SLOW_SCALE * CrashMotion.SLOW_TIME
	runner.crash(CrashMotion.contact(item["kind"], RunLogic.lane_x(item["lane"]), runner.position.x, z, player.height()))


## 장면을 다시 불러오지 않고 그 자리에서 상태만 초기화한다. 레인은 그대로, 세상은 바로 움직이고 입력도 바로 받는다.
func restart() -> void:
	dead = false
	_dead_time = 0.0
	_quality.hold()
	save.count_play()
	if daily_mode:  # 자정이 지났으면 이 판부터 새 날의 판 (앞 판은 시작한 날짜에 이미 저장했다)
		daily.start(today())
	_tint_from = _tint  # 부딪힌 순간의 색에서 돌아간다
	AudioManager.restart_music()
	_music_t = AudioManager.music_time
	_tint_clock = _music_t
	travel = AudioManager.ladder.distance_at(_music_t)  # 출력 지연만큼 음수에서 출발: 다음 프레임에 길이 뒤로 튀지 않게
	_reset_round()
	var old_pieces := _obstacles.values()
	_obstacles.clear()
	_new_field()
	AudioManager.unblock()
	_apply_fog(AudioManager.ladder, _music_t)
	for piece: Piece in old_pieces:
		_leaving.append(piece)
		_animating += 1
		var fade := create_tween().set_parallel()
		fade.tween_property(piece, "scale", Vector3.ONE * 0.01, OBSTACLE_FADE)
		fade.tween_property(piece, "position:z", piece.position.z + speed * OBSTACLE_FADE, OBSTACLE_FADE)
		fade.chain().tween_callback(func() -> void:
			_leaving.erase(piece)
			_animation_done())
	_dashes.position.z = 0.0  # 부딪힌 뒤 밀려 간 만큼 되돌린다
	_place_rows()
	_dash_material.set_shader_parameter("sparkle_on", 1.0)
	_pop_dashes()  # 박자가 0박으로 돌아가며 대시 격자가 옮겨 가는 순간을 가린다
	record.begin_run()
	_show_best()
	runner.reform(lane)
	_pause_btn.visible = true


## 대시 격자가 장애물과 같은 '퐁'으로 나타난다
func _pop_dashes() -> void:
	var appear := func(a: float) -> void: _dash_material.set_shader_parameter("appear", a)
	appear.call(0.0)
	create_tween().tween_method(appear, 0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 새 판(다시 시작·메인 화면)마다 처음으로 돌리는 입력·점수·게임 오버 글자
func _reset_round() -> void:
	player = PlayerAction.new()
	score = ScoreBoard.new()
	_swipe = SwipeDetector.new()
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_restart_label.visible = false
	_stats_label.visible = false
	_home.visible = false
	_share.visible = false
	_new_skin.visible = false
	new_skin_id = ""
	_mult_shown = 1
	if _mult_tween:
		_mult_tween.kill()
	_reset_multiplier()
	_hide_perfect()
	_score_label.text = "0"
	_set_milestone_look(false)
	score.points = _dev_points


## 게임 오버의 집 버튼: 0.4초 페이드로 메인 화면에 간다
func go_home() -> void:
	_going_home = true
	_fade.visible = true
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 일시정지 화면의 HOME: 멈춘 세상 위로 어두워진다
	fade.tween_property(_fade, "color:a", 1.0, HOME_FADE * 0.5)
	fade.tween_callback(_enter_menu)
	fade.tween_property(_fade, "color:a", 0.0, HOME_FADE * 0.5)
	fade.tween_callback(func() -> void:
		_fade.visible = false
		_going_home = false)


## 페이드로 가려진 사이에 메인 화면 상태로: 앞 판을 지우고, 젤리는 가운데 레인에 모이고, 첫 곡이 6dB 작게 흐른다
func _enter_menu() -> void:
	if paused:  # 일시정지에서 왔다: 화면이 가려진 지금 멈춘 것을 푼다
		_pause_menu.hide()
		_unpause()
	if started and not dead:  # 일시정지에서 집: 이 판의 진행도도 센다 (NEW SKIN 화면은 없이 열린다)
		_finish_run()
	dead = false
	started = false
	daily_mode = false  # 게임 오버·일시정지의 집은 언제나 메인 화면으로
	record = normal_record
	_dead_time = 0.0
	_quality.hold()
	AudioManager.play_menu_music()
	_reset_round()
	_obstacles.clear()
	_pieces_dirty = true
	_new_field()
	_music_t = 0.0
	travel = 0.0
	_tint_from = -1.0
	_apply_tint(AudioManager.ladder.tint_at(0.0))
	_apply_fog(AudioManager.ladder, 0.0)
	_apply_stretch(1.0)
	_set_stage_glow(0.0)
	_place_rows()
	_dash_material.set_shader_parameter("sparkle_on", 0.0)
	lane = RunLogic.START_LANE
	runner.reform(lane)
	runner.position.x = RunLogic.lane_x(lane)
	skin_view = SkinBook.index_of(skins.selected)
	_apply_skin_view()
	_menu_t = 0.0
	_menu_beat = -1
	_set_view(1.0)
	_hud.modulate.a = 0.0
	_pause_btn.visible = false
	_show_title()
	_sync_pieces()  # 페이드가 걷히기 전 프레임부터 앞 판 장애물이 보이지 않게
	_sync_orbs()


## 일시정지 (‖ 버튼, Esc·P, 탭 가림·창 포커스 잃음·앱이 뒤로 감). 플레이 중에만.
## 트리를 멈춰 세상·판정·트윈이 서고, 음악은 그 표본에서 선다. 숫자 세는 중에 다시 가려지면 일시정지 화면으로 돌아간다
func pause() -> void:
	if paused:  # 숫자 세는 중이거나 숫자가 끝나 소리가 다시 돌기를 기다리는 중: 일시정지 화면으로 되돌린다
		AudioManager.set_held(true)
		_pause_menu.open()
		return
	if not started or dead or not prewarmed or _going_home:
		return
	paused = true
	AudioManager.set_held(true)
	get_tree().paused = true
	_swipe = SwipeDetector.new()  # 누르던 손가락은 잊는다: 이어 한 뒤 반쯤 민 스와이프가 동작이 되지 않게
	_pause_btn.visible = false
	_pause_menu.open()


## RESUME: 지금 박 길이로 3·2·1을 센다. 멈춘 자리가 박 사이였으면 음악 박이 숫자 박에 이어지게 맞춘다
func _on_resume_pressed() -> void:
	var t := AudioManager.music_time
	var step: int = AudioManager.ladder.segment_at(t)["step"]
	_pause_menu.count(PauseCountdown.new(MusicLadder.beat_time(step), AudioManager.ladder.beat_at(t)))


## 숫자가 끝났다: 소리를 먼저 다시 돌리고(웹은 몇 ms 걸린다) 돌기 시작하면 세상을 푼다
func _on_resumed() -> void:
	AudioManager.set_held(false)
	_pause_menu.hide()
	for i in RESUME_WAIT_FRAMES:
		if AudioManager.is_running():
			break
		await get_tree().process_frame
	if paused and not _pause_menu.visible:  # 기다리는 사이 다시 일시정지되지 않았으면
		_unpause()
		_report_drift()


## 이어 한 뒤 DRIFT_TIME초 동안 화면의 음악 시간과 들리는 소리 위치의 차이(+면 화면이 앞섬)를 남긴다 (박자 오차 확인용 한 줄).
## 브라우저 오디오 시계는 블록 단위 계단으로 오르므로 프레임마다의 차이에는 계단 크기만큼 흔들림이 섞인다: 평균이 실제 어긋남이다
func _report_drift() -> void:
	var low := INF
	var high := -INF
	var sum := 0.0
	var n := 0
	var end := Time.get_ticks_msec() + DRIFT_TIME * 1000.0
	while Time.get_ticks_msec() < end and AudioManager.is_music_on() and not paused:
		var d := AudioManager.drift()
		low = minf(low, d)
		high = maxf(high, d)
		sum += d
		n += 1
		await get_tree().process_frame
	if n > 0:
		print("PAUSE 이어 한 뒤 %.0f초 박자 오차 평균 %+.1fms (%+.1f ~ %+.1f, %d프레임)" % [DRIFT_TIME, sum / n * 1000.0, low * 1000.0, high * 1000.0, n])


func _unpause() -> void:
	AudioManager.set_held(false)
	get_tree().paused = false
	paused = false
	_pause_btn.visible = started and not dead


func _on_pause_home() -> void:
	record.save()  # 이번 판에 넘은 기록은 남긴다
	go_home()


## 설정 (메인 화면 톱니, 일시정지의 SETTINGS)
func open_settings() -> void:
	_begin_waiting = false  # 준비 중에 눌러 둔 시작은 취소한다: 설정 뒤에서 게임이 시작되면 조작할 수 없다
	_pause_menu.blocked = true
	_settings.open(save, haptics)


func _on_settings_closed() -> void:
	_pause_menu.blocked = false


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		pause()


## 웹: 탭이 가려지거나 창이 포커스를 잃으면 바로 소리를 멈춘다 (가려진 탭은 프레임이 오지 않아 엔진 알림을 기다리면 음악만 흘러간다)
func _watch_page() -> void:
	_page_callback = JavaScriptBridge.create_callback(func(_args: Array) -> void: pause())
	JavaScriptBridge.get_interface("window").gamePause = _page_callback
	JavaScriptBridge.eval("""
		document.addEventListener('visibilitychange', () => { if (document.hidden) window.gamePause(); });
		window.addEventListener('blur', () => window.gamePause());
		window.addEventListener('pagehide', () => window.gamePause());
	""", true)


## 메인 화면 소리 버튼: 음악·효과음 모두. 상태는 저장한다
func toggle_sound() -> void:
	save.set_muted(not save.muted)
	AudioManager.set_muted(save.muted)
	_title.set_muted(save.muted)


## 기록이 있으면 숫자 아래에 작게. 첫 판에는 숨긴다.
func _show_best() -> void:
	_best_label.visible = record.previous > 0
	_best_label.text = ("DAILY BEST %d" if daily_mode else "BEST %d") % record.previous


## 메인 화면 글자 (오늘의 판 번호, 오늘 안 했으면 점)
func _show_title() -> void:
	var d := today()
	_title.show_menu(normal_record.best, save.shows_guide(), save.muted, DailyRecord.number(d), not daily.played(d))


## 메인 → 오늘의 판 시작 화면 (같은 무대 위 0.3초). 배치는 시작할 때 그날 씨앗으로 만든다
func open_daily() -> void:
	daily_mode = true
	if skin_view != SkinBook.index_of(skins.selected):  # 오늘의 판은 넘기기 없이 고른 스킨으로
		_end_flip()
		skin_view = SkinBook.index_of(skins.selected)
		_apply_skin_view()
	record = daily
	daily.view(today())
	_refresh_daily()
	_title.show_daily(true)


## 오늘의 판 시작 화면의 집 버튼 → 메인 화면
func close_daily() -> void:
	daily_mode = false
	record = normal_record
	_title.show_daily(false)


## 메인 화면의 DAILY 번호·점, 시작 화면의 기록·남은 시간. 시작 화면에서 날짜가 바뀌면 새 날을 보인다
func _refresh_daily() -> void:
	var d := today()
	if daily_mode and daily.day != d:
		daily.view(d)
	_title.set_daily_button(DailyRecord.number(d), not daily.played(d))
	_title.set_daily(DailyRecord.number(d), daily.best, daily.streak_on(d), DailyRecord.countdown(now_unix()))


## SHARE: 휴대폰은 공유 창(Web Share), 아니면 클립보드에 "SWIPE PULSE Daily #12 — 5320 주소"(10000점 이상은 " · 10K+")를 복사하고 COPIED를 0.8초
func share() -> void:
	var text := ScoreBoard.share_text(DailyRecord.number(daily.day), _final_score)
	shared_text = text + " " + GAME_URL
	var how := "copy"
	if OS.has_feature("web"):
		how = str(JavaScriptBridge.eval(SHARE_JS % [JSON.stringify(text), JSON.stringify(GAME_URL)]))
	elif DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):  # 헤드리스(테스트)에는 클립보드가 없다
		DisplayServer.clipboard_set(shared_text)
	if how != "copy":
		return
	if _share_tween:
		_share_tween.kill()
	_share.text = "COPIED"
	_share_tween = create_tween()
	_share_tween.tween_interval(COPIED_TIME)
	_share_tween.tween_callback(func() -> void: _share.text = "SHARE")


## 예전 기록을 넘은 순간: 숫자가 한 번 말랑하게 커졌다 돌아온다. 소리는 내지 않는다.
func _on_new_record() -> void:
	_best_label.text = "NEW BEST"
	haptics.fire(Haptics.Event.NEW_BEST)
	_score_label.pivot_offset = _score_label.size * 0.5
	_pop = create_tween()
	_pop.tween_property(_score_label, "scale", Vector2.ONE * POP_SCALE, POP_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_score_label, "scale", Vector2.ONE, POP_DOWN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 10000점을 넘은 순간: 숫자가 크게 말랑하고 둘레 빛이 확 번졌다 옅어진다. 그 뒤로 이 판은 연보라 숫자 + 옅은 빛
func _on_milestone() -> void:
	_set_milestone_look(true)
	var settings := _score_label.label_settings
	_score_label.pivot_offset = _score_label.size * 0.5
	if _pop:
		_pop.kill()
	_pop = create_tween()
	_pop.tween_property(_score_label, "scale", Vector2.ONE * MILESTONE_POP, POP_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_score_label, "scale", Vector2.ONE, POP_DOWN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_milestone_tween = create_tween()
	_milestone_tween.tween_property(settings, "shadow_color", Color(MILESTONE_HALO, 0.3), MILESTONE_GLOW_TIME).from(Color(MILESTONE_HALO, 1.0)).set_ease(Tween.EASE_OUT)


## 점수 숫자 모양: 보통(흰색) / 10000점을 넘은 판(연보라 + 둘레 빛). 둘레 빛은 글자 그림자를 크게 번지게 해 그린다
func _set_milestone_look(on: bool) -> void:
	_over_milestone = on
	if _milestone_tween:
		_milestone_tween.kill()
	var settings := _score_label.label_settings
	settings.font_color = MILESTONE_COLOR if on else Color.WHITE
	settings.shadow_size = 18 if on else 1
	settings.shadow_offset = Vector2.ZERO
	settings.shadow_color = Color(MILESTONE_HALO, 0.3) if on else Color(0, 0, 0, 0)


func _input(event: InputEvent) -> void:
	if (not started and not prewarmed) or _going_home or paused or _settings.visible:  # 가림막·페이드·일시정지·설정 뒤의 입력은 받지 않는다
		return
	var pressed: bool = (event is InputEventScreenTouch or event is InputEventKey) and event.pressed
	if event is InputEventScreenTouch and pressed and PerfStats.TAP_ZONE.has_point(event.position):  # 성능 표시 자리: 시작·다시 시작·스와이프로 쓰지 않는다
		if perf.tap(Time.get_ticks_msec() / 1000.0):
			toggle_perf()
		return
	if event is InputEventKey and pressed and event.keycode == KEY_F3 and not event.echo:
		toggle_perf()
		return
	if not started:
		_menu_input(event, pressed)
		return
	if dead:
		if pressed and _dead_time >= RESTART_DELAY:
			if event is InputEventScreenTouch and _home.hit(event.position):
				go_home()
				return
			if event is InputEventScreenTouch and _share.is_visible_in_tree() and _share.get_global_rect().has_point(event.position):
				share()
				return
			if event is InputEventScreenTouch and _equip.is_visible_in_tree() and _equip.get_global_rect().has_point(event.position):
				equip_new_skin()
				return
			restart()
			if event is InputEventScreenTouch:  # 다시 시작한 손가락 그대로 밀어도 스와이프가 된다
				_swipe.press(event.position, event.index)
		return
	if pressed and ((event is InputEventScreenTouch and _pause_btn.hit(event.position)) or (event is InputEventKey and event.keycode in [KEY_ESCAPE, KEY_P])):
		pause()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe.press(event.position, event.index)
		else:
			_swipe.release(event.index)
	elif event is InputEventScreenDrag:
		apply_swipe(_swipe.move(event.position, event.index))
	elif event.is_action_pressed("ui_left"):
		apply_swipe(SwipeDetector.Dir.LEFT)
	elif event.is_action_pressed("ui_right"):
		apply_swipe(SwipeDetector.Dir.RIGHT)
	elif event.is_action_pressed("ui_up"):
		apply_swipe(SwipeDetector.Dir.UP)
	elif event.is_action_pressed("ui_down"):
		apply_swipe(SwipeDetector.Dir.DOWN)


## 화면 확인 기록(review/)용 주소 값. 쓰면 이 창에서는 스킨 진행도를 저장하지 않는다.
## ?points=9990 은 판마다 그 점수에서 시작, ?skin=lemon 은 잠겨 있어도 그 스킨으로, ?skin=all 은 모두 열린 것처럼, ?orbs=499 는 방울 진행도를 그 값으로 (NEW SKIN 캡처), ?quality=4 는 효과 단계를 그만큼 낮춘다, ?slow=0.1 은 시간 배율
func _dev_view() -> void:
	var query := func(key: String) -> String: return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key))
	var dev_skin: String = query.call("skin")
	var orbs: String = query.call("orbs")
	if not (dev_skin.is_empty() and orbs.is_empty()):
		skins._read_only = true  # 더 새 형식 파일의 읽기 전용은 그대로 둔다
	if orbs.is_valid_int():
		skins.stats["orbs"] = int(orbs)
	for item: Dictionary in SkinBook.list():
		if (dev_skin == "all" or dev_skin == item["id"]) and not skins.is_unlocked(item["id"]):
			skins.unlocked.append(item["id"])
	if SkinBook.index_of(dev_skin) >= 0:
		skins.selected = dev_skin
	var level := int(query.call("quality"))
	var slow := float(query.call("slow"))
	_dev_points = float(query.call("points"))  # ?points=9990: 판마다 이 점수에서 시작 (10000점 연출 캡처). 기록은 저장되지만 이 창의 user://만
	if _dev_points > 0.0:  # 진짜 기록·스킨 진행도에 섞이지 않게 따로 쓰는 기록으로 (Codex 지적)
		skins._read_only = true
		normal_record = BestRecord.new("user://dev_points_best.txt", 0)
		daily = DailyRecord.new("user://dev_points_daily.cfg", today())
		record = normal_record
	if slow > 0.0:
		Engine.time_scale = slow  # GIF 프레임용: 헤드리스 캡처가 느려 게임을 그만큼 느리게 돌린다
	if level > 0:
		_quality.level = level  # 자동 낮춤이 이 단계 아래에서 다시 시작하지 않게
		apply_quality(level)


## 메인 화면(·오늘의 판 시작 화면) 입력. 버튼은 누르는 순간, 시작은 손을 뗄 때(탭) 또는 위 스와이프.
## 좌우 스와이프·방향키는 스킨 넘기기(메인 화면만). 키보드: D 오늘의 판, Esc 돌아가기, 아래는 아무것도 안 함, 나머지 키는 시작
func _menu_input(event: InputEvent, pressed: bool) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed:
			if _swipe.release(event.index):
				_menu_start()
		elif _title.sound.hit(event.position):
			toggle_sound()
		elif _title.gear.hit(event.position):
			open_settings()
		elif not daily_mode and _title.daily_hit(event.position):
			open_daily()
		elif daily_mode and _title.daily_home.hit(event.position):
			close_daily()
		else:
			_swipe.press(event.position, event.index)
		return
	if event is InputEventScreenDrag:
		match _swipe.move(event.position, event.index):
			SwipeDetector.Dir.LEFT:
				flip_skin(1)  # 손가락을 왼쪽으로: 젤리가 왼쪽으로 밀려나고 다음 스킨이 오른쪽에서
			SwipeDetector.Dir.RIGHT:
				flip_skin(-1)
			SwipeDetector.Dir.UP:
				_menu_start()
		return
	if not pressed or not event is InputEventKey:
		return
	match event.keycode:
		KEY_D when not daily_mode:
			open_daily()
		KEY_ESCAPE when daily_mode:
			close_daily()
		KEY_LEFT:
			flip_skin(-1)
		KEY_RIGHT:
			flip_skin(1)
		KEY_DOWN, KEY_D, KEY_ESCAPE:
			pass
		_:
			_menu_start()


## 시작 (탭·위 스와이프·키). 잠긴 스킨을 보고 있으면 젤리만 살짝 흔들린다
func _menu_start() -> void:
	if not skins.is_unlocked(SkinBook.list()[skin_view]["id"]):
		runner.nudge()
	elif not warmed:  # 장애물 셰이더를 아직 준비하는 중: 남은 것을 한꺼번에 그리고 시작한다
		_begin_waiting = true
	else:
		begin()  # 게임 동작으로는 처리하지 않는다


## 메인 화면 스킨 넘기기 (0.25초): 젤리가 옆으로 밀려나며 작아지고, 화면 밖 순간에 색을 바꿔 반대쪽에서 들어온다.
## 출렁임 스프링이 옆 이동을 받아 말랑하게 기운다. 넘기는 중의 입력은 무시한다. 열린 스킨이면 고른 스킨으로 저장
func flip_skin(step: int) -> void:
	if daily_mode or (_flip and _flip.is_running()):
		return
	_begin_waiting = false  # 준비 중에 눌러 둔 시작은 넘기면 취소 (잠긴 스킨을 보다가 저절로 시작하지 않게)
	var count := SkinBook.list().size()
	skin_view = posmod(skin_view + step, count)
	var id: String = SkinBook.list()[skin_view]["id"]
	skins.select(id)  # 잠긴 스킨은 고르지 않는다 (시작하면 마지막으로 고른 열린 스킨)
	var home := RunLogic.lane_x(lane)
	_flip = create_tween()
	_flip.set_parallel()
	_flip.tween_property(runner, "position:x", home - FLIP_X * step, FLIP_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip.tween_property(runner, "scale", Vector3.ONE * FLIP_SCALE, FLIP_OUT)
	_flip.chain().tween_callback(func() -> void:
		_apply_skin_view()
		runner.snap_x(home + FLIP_X * step))
	_flip.chain().tween_property(runner, "position:x", home, FLIP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flip.parallel().tween_property(runner, "scale", Vector3.ONE, FLIP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_title.set_skin(skin_view, count, _skin_text(skin_view), not skins.is_unlocked(id))


## 넘기기를 멈추고 젤리를 제자리·제 크기로 (시작·오늘의 판)
func _end_flip() -> void:
	if _flip:
		_flip.kill()
		_flip = null
	runner.scale = Vector3.ONE
	runner.snap_x(RunLogic.lane_x(lane))
	skin_view = SkinBook.index_of(skins.selected)
	_apply_skin_view()  # 넘기는 도중(색을 바꾸기 전)에 시작해도 고른 스킨으로


## 보고 있는 스킨을 젤리와 메인 화면 글자에 (잠긴 스킨은 어두운 실루엣과 조건·진행도)
func _apply_skin_view() -> void:
	var item: Dictionary = SkinBook.list()[skin_view]
	var locked := not skins.is_unlocked(item["id"])
	runner.apply_skin(SkinBook.shader_params(item, locked))
	_title.set_skin(skin_view, SkinBook.list().size(), _skin_text(skin_view), locked)


func _skin_text(index: int) -> String:
	var item: Dictionary = SkinBook.list()[index]
	return item["name"] if skins.is_unlocked(item["id"]) else skins.condition_text(item["id"])


## 한 판이 끝났다: 진행도를 더하고 새로 열린 스킨 id 목록 (일반·오늘의 판 합산)
func _finish_run() -> Array[String]:
	return skins.finish_run(score.total(travel), score.close, score.orbs, score.top_multiplier, daily.streak)


## 게임 오버: 새로 열린 스킨이 있으면 NEW SKIN + 미리보기 + EQUIP (여러 개면 앞의 것, 나머지는 메인 화면에서 고를 수 있다)
func _show_new_skin(fresh: Array[String]) -> void:
	new_skin_id = "" if fresh.is_empty() else fresh[0]
	if new_skin_id.is_empty():
		return
	var item := SkinBook.skin(new_skin_id)
	_new_skin_preview.params = SkinBook.shader_params(item)
	_new_skin_preview.queue_redraw()
	_equip.text = "EQUIP " + item["name"]


## EQUIP: 새 스킨을 고르고 젤리에 바로 입힌다
func equip_new_skin() -> void:
	skins.select(new_skin_id)
	skin_view = SkinBook.index_of(new_skin_id)
	_apply_skin_view()
	_equip.text = "EQUIPPED"


## 스와이프(또는 방향키) 방향을 게임 동작으로 옮긴다.
func apply_swipe(dir: SwipeDetector.Dir) -> void:
	match dir:
		SwipeDetector.Dir.LEFT:
			_change_lane(-1)
		SwipeDetector.Dir.RIGHT:
			_change_lane(1)
		SwipeDetector.Dir.UP:
			if player.jump():  # 저장만 된 입력은 아슬아슬 시각을 바꾸지 않는다
				score.note_jump(_music_t)
			_play_action_sounds()
		SwipeDetector.Dir.DOWN:
			_drop_clear_hurdles()
			if player.slide():
				score.note_slide(_music_t)
			_play_action_sounds()


## 동작이 일어난 그 프레임에 바로 재생한다
func _play_action_sounds() -> void:
	for sound in player.take_sounds():
		AudioManager.play_action(sound)


## 공중 아래 스와이프 순간 이미 넘고 있던 허들은 내려오다 닿아도 봐준다 (넘고 있었는데 죽으면 억울하다)
func _drop_clear_hurdles() -> void:
	if not player.is_jumping() or player.is_dropping():
		return
	for item in field.items:
		var dx := runner.position.x - RunLogic.lane_x(item["lane"])
		if PlayerAction.clears_on_drop(item["kind"], dx, item["z"], player.height()):
			item["cleared"] = true


func _change_lane(direction: int) -> void:
	var next := RunLogic.move_lane(lane, direction)
	if next == lane:
		return
	score.note_move(_music_t, lane)
	lane = next
	runner.move_to_lane(lane)
	AudioManager.play_lane(direction)


func _spawn_node(item: Dictionary) -> void:
	var piece := Piece.new()
	piece.kind = item["kind"]
	piece.position = Vector3(RunLogic.lane_x(item["lane"]), 0.0, item["z"])
	piece.item = item
	var twin := _wall_twin(item)
	if twin:
		piece.hidden = true
		twin.wide = 1.0
		twin.position.x = (twin.position.x + piece.position.x) * 0.5
		twin.haze = _haze_of(twin)
	else:
		piece.haze = _haze_of(piece)
	_obstacles[item["id"]] = piece
	_pieces_dirty = true


## 같은 줄 이웃 레인에 이미 놓인 기둥. 같은 줄은 같은 프레임에 차례로 생기므로 앞서 놓인 것을 넓힌다.
func _wall_twin(item: Dictionary) -> Piece:
	for other: Piece in _obstacles.values():
		if not other.hidden and ObstacleField.forms_wall(other.item, item):
			return other
	return null


## 같은 레인에 바로 앞서 오는 옆 블록이 있으면 뒤쪽 것을 조금 흐리게 한다: 연속 블록이 한 덩어리로 보이지 않게 하는 깊이 단서
func _haze_of(piece: Piece) -> float:
	if piece.kind != ObstacleField.Kind.BLOCK:
		return 0.0
	for other: Piece in _obstacles.values():
		var gap := other.position.z - piece.position.z
		var overlap := absf(other.position.x - piece.position.x) < RunLogic.LANE_WIDTH * 0.5 * (other.wide + piece.wide) + 0.1  # 벽과 기둥이 겹치는 레인도 연속으로 본다
		if other.kind == piece.kind and overlap and gap > 0.0 and gap < FOLLOW_GAP:
			return FOLLOW_HAZE
	return 0.0


## 장애물을 모두 지운다 (화면 확인 도구, 테스트)
func clear_pieces() -> void:
	_obstacles.clear()
	_pieces_dirty = true


## 웹은 재질이 처음 그려질 때 셰이더를 만들어 그 프레임이 막힌다. 같은 뷰포트에서 그려야 안개·글로우까지 같은 셰이더 조합이 준비된다.
## 1단계(가림막 뒤): 메인 화면에 보이는 젤리·길·하늘·제목만 그린 뒤 첫 화면을 연다.
## 2단계(메인 화면 뒤): 장애물·방울·효과·게임 글자를 아주 작게(PREWARM_TINY, 화면에 안 보임) 한 묶음씩 그린다.
## 시작을 누를 때까지 다 못 끝냈으면 남은 것을 한꺼번에 그리고 나서 시작한다 (첫 판에서 셰이더 때문에 멈칫하지 않게).
func _prewarm() -> void:
	var cover := CanvasLayer.new()
	cover.layer = 100
	add_child(cover)
	var curtain := ColorRect.new()
	curtain.color = BOOT_COLOR
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(curtain)
	_load_progress(0.0)
	while not AudioManager.first_ready():  # 개발용 ?bpm: 시작 곡을 받아 풀 때까지
		await get_tree().process_frame
	await _settle(0.0, 1.0)
	cover.queue_free()
	prewarmed = true
	if OS.has_feature("web"):
		# 가림막 뒤의 느린 프레임은 자동 낮춤 판단에 넣지 않는다. gameReady: 첫 화면이 드러난 시각 (프레임 측정의 시작점)
		JavaScriptBridge.eval("window.gameFrames.length = 0; window.gameReady = performance.now()")
	AudioManager.fetch_rest()
	await _warm_rest()


## 셰이더가 다 준비될 때까지 프레임을 돌린다: PREWARM_FRAMES번 연달아 빠른 프레임이 나오면 끝. 로딩 막대를 from → to로 채운다
func _settle(from: float, to: float, max_frames := PREWARM_MAX_FRAMES) -> void:
	var fast := 0
	var last := Time.get_ticks_msec()
	for i in max_frames:
		await get_tree().process_frame
		fast = fast + 1 if Time.get_ticks_msec() - last < PREWARM_FAST_MS else 0
		last = Time.get_ticks_msec()
		_load_progress(lerpf(from, to, 1.0 - pow(0.85, i + 1)))  # 끝을 모르므로 점점 느려지며 다가간다
		if fast >= PREWARM_FRAMES:
			break
	_load_progress(to)


## 웹 로딩 화면의 "준비 중" 막대 (index.html 셸이 읽는다)
func _load_progress(k: float) -> void:
	if OS.has_feature("web") and not prewarmed:
		JavaScriptBridge.eval("window.gamePrep = %.3f" % k)


## 2단계: 묶음마다 아주 작게 그리고 프레임이 빨라지면 다음 묶음
func _warm_rest() -> void:
	var groups: Array = _kind_meshes.keys().map(func(kind: int) -> Callable: return _warm_piece.bind(kind))
	groups.append_array([_warm_orbs, _warm_swish, _warm_drop, _warm_labels])
	while not groups.is_empty():
		var batch: Array = groups.duplicate() if _begin_waiting else [groups[0]]
		var undo: Array[Callable] = []
		for warm: Callable in batch:
			undo.append(warm.call())
		await _settle(1.0, 1.0, WARM_MAX_FRAMES)
		for done: Callable in undo:
			done.call()
		groups = groups.slice(batch.size())
	warmed = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.gameFrames.length = 0")  # 준비하며 느렸던 프레임으로 효과를 낮추지 않게
	if _begin_waiting:
		_begin_waiting = false
		begin()


## 각 _warm_*: 그 재질을 아주 작게 보이고, 되돌리는 함수를 돌려준다
func _warm_piece(kind: int) -> Callable:
	var sample := Piece.new()
	sample.kind = kind
	sample.position = Vector3(RunLogic.lane_x(kind % 3), 0.5, -6.0)
	sample.scale = Vector3.ONE * PREWARM_TINY
	_leaving.append(sample)
	_pieces_dirty = true
	return func() -> void:
		_leaving.erase(sample)
		_pieces_dirty = true


func _warm_orbs() -> Callable:
	_orb_prewarm = true
	return func() -> void: _orb_prewarm = false


func _warm_swish() -> Callable:
	_swish.scale = Vector3.ONE * PREWARM_TINY
	_swish.position = Vector3(0.0, 0.6, -5.0)
	_swish.visible = true
	return func() -> void:
		_swish.visible = false
		_swish.scale = Vector3.ONE


func _warm_drop() -> Callable:
	var drop: MeshInstance3D = runner.make_prewarm_drop()
	drop.position = Vector3(0.0, 1.0, -3.0)
	drop.scale = Vector3.ONE * PREWARM_TINY
	add_child(drop)
	return drop.queue_free


## 게임 글자(점수 170px 등)의 글자 그림을 미리 만든다
func _warm_labels() -> Callable:
	var cover := CanvasLayer.new()
	add_child(cover)
	for pair in [["0123456789", _score_label], [_restart_label.text, _restart_label], ["NEW BEST 0123456789", _best_label], ["×+0123456789", _mult_label], ["ORBS PERFECT · m0123456789", _stats_label], ["PERFECT ×+0123456789", _perfect_label], ["ABCDEFGHIJKLMNOPQRSTUVWXYZ ×/0123456789", _title.skin_name], ["NEW SKIN", _new_skin.get_child(0)], ["EQUIPDABCDEFGHIJKLMNOPQRSTUVWXYZ", _equip]]:
		var label := Label.new()
		label.text = pair[0]
		label.label_settings = pair[1].label_settings
		label.scale = Vector2.ONE * PREWARM_TINY
		cover.add_child(label)
	return cover.queue_free


# ---------- 장면 만들기 ----------

func _build_environment() -> void:
	# 안개 색을 지평선과 맞춰 먼 곳이 자연스럽게 흐려진다. 색은 _apply_tint가 정한다.
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.fog_enabled = true
	_env.fog_density = FOG_DENSITY
	_env.fog_sky_affect = 0.0
	_env.glow_enabled = true
	_env.glow_intensity = GLOW_INTENSITY
	_env.glow_strength = 1.1
	_env.set_glow_level(3, GLOW_WIDE)
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 0.9
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var dome := SphereMesh.new()
	dome.radius = SKY_RADIUS
	dome.height = SKY_RADIUS * 2.0
	dome.radial_segments = 16
	dome.rings = 8
	var sky := MeshInstance3D.new()
	sky.name = "Sky"
	sky.mesh = dome
	sky.material_override = _sky_material
	sky.position = Vector3(0.0, 3.3, 5.4)  # 카메라 자리
	add_child(sky)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.position = Vector3(0.0, 3.3, 5.4)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.7, -8.0))


## 세로 화면은 가로 폭을, 가로 화면(데스크톱 테스트)은 세로 높이를 기준으로 맞춰 길이 항상 보이게 한다.
func _fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y >= size.x else Camera3D.KEEP_HEIGHT
	_restart_label.offset_top = 370.0 if size.y >= size.x else 200.0  # 웅덩이와 겹치지 않는 자리 (세로는 아래, 가로는 위)
	# SHARE: 세로는 다시 시작 안내 아래, 가로(PC)는 그 자리가 젤리와 겹쳐 TRIES 줄 아래
	var portrait := size.y >= size.x
	_share.set_anchors_preset(Control.PRESET_CENTER if portrait else Control.PRESET_CENTER_TOP)
	_share.offset_top = _restart_label.offset_top + 100.0 if portrait else STATS_TOP + 56.0
	_share.offset_bottom = _share.offset_top + TitleScreen.DAILY_ROW
	var short := size.y / size.x < MENU_SHORT
	_menu_cam = MENU_CAM_SHORT if short else MENU_CAM
	_menu_look = MENU_LOOK_SHORT if short else MENU_LOOK
	# 메인 화면 카메라에서 본 웅덩이 앞 끝·젤리 몸의 화면 자리 → 그 아래에 스킨 이름·점·TAP TO START, 안내가 젤리에 닿으면 옆으로
	var k := _view
	_set_view(1.0)
	var x := RunLogic.lane_x(RunLogic.START_LANE)
	var pool := _camera.unproject_position(Vector3(x, 0.0, POOL_FRONT_Z)).y
	var top_left := _camera.unproject_position(Vector3(x - Runner.BODY_RADIUS, Runner.BODY_HEIGHT, 0.0))
	var bottom_right := _camera.unproject_position(Vector3(x + Runner.BODY_RADIUS, 0.0, 0.0))
	_set_view(k)
	_title.place(pool, Rect2(top_left, bottom_right - top_left), size)
	# NEW SKIN: 세로는 게임 오버 한 줄 아래 가운데, 가로(PC)는 SHARE·젤리와 겹치지 않게 오른쪽 칸
	_new_skin.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_new_skin.offset_left = (-180.0 if portrait else size.x * 0.25 - 180.0)
	_new_skin.offset_right = _new_skin.offset_left + 360.0
	_new_skin.offset_top = NEW_SKIN_TOP if portrait else STATS_TOP


func _build_floor() -> void:
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = FLOOR_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = plane
	floor_node.material_override = _floor_material
	floor_node.position = Vector3(0.0, 0.0, -140.0)
	add_child(floor_node)
	_build_rails()
	_build_dashes()
	_build_streaks()


func _build_rails() -> void:
	_rail_material = ShaderMaterial.new()
	_rail_material.shader = NEON_SHADER
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = ArtMeshes.rails(RAIL_X, RAIL_Y, RAIL_RADIUS, 8.0, -128.0, 8.0)
	rails.material_override = _rail_material
	add_child(rails)


## 레인 경계 2줄의 대시. MultiMesh 하나에 담고 새 박의 줄만 값을 쓴다 (_place_rows).
func _build_dashes() -> void:
	_dash_material = ShaderMaterial.new()
	_dash_material.shader = DASH_SHADER
	var dash := BoxMesh.new()
	dash.size = DASH_SIZE
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = dash
	many.instance_count = BeatRows.COUNT * 2
	_row_beats.resize(BeatRows.COUNT)
	_dashes = MultiMeshInstance3D.new()
	_dashes.name = "Dashes"
	_dashes.multimesh = many
	_dashes.material_override = _dash_material
	add_child(_dashes)


## 카메라 옆 빛 줄기. 자리는 고정이고 움직임은 셰이더가 이동 거리로 계산한다. 앞쪽 칸부터 보이므로 어떤 개수에서도 고르게 흩어져 있다.
func _build_streaks() -> void:
	_streak_material = ShaderMaterial.new()
	_streak_material.shader = STREAK_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = STREAK_SEED
	_streaks = MultiMesh.new()
	_streaks.transform_format = MultiMesh.TRANSFORM_3D
	_streaks.mesh = BoxMesh.new()
	_streaks.instance_count = STREAK_MAX
	for i in STREAK_MAX:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(STREAK_X.x, STREAK_X.y), rng.randf_range(STREAK_Y.x, STREAK_Y.y), rng.randf_range(0.0, 60.0))
		_streaks.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
	var node := MultiMeshInstance3D.new()
	node.name = "Streaks"
	node.multimesh = _streaks
	node.material_override = _streak_material
	node.extra_cull_margin = 16384.0
	add_child(node)


## 종류마다 MultiMesh: 몸통과 반사 두 번만 그린다. 장애물이 늘어도 그리는 횟수는 같다.
func _build_obstacle_resources() -> void:
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)
	for kind: ObstacleField.Kind in KINDS:
		var meshes := ArtMeshes.obstacle(kind)
		var body := _new_pieces_mesh(meshes["body"])
		var mirror := _new_pieces_mesh(meshes["mirror"])
		var block := ShaderMaterial.new()
		block.shader = BLOCK_SHADER
		var reflect := ShaderMaterial.new()
		reflect.shader = MIRROR_SHADER
		reflect.render_priority = -1  # 젤리 발밑 그림자보다 먼저 그린다
		block.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
		reflect.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
		reflect.set_shader_parameter("wall_shadow", RunLogic.LANE_WIDTH * 0.5 / ArtMeshes.SHADOW_HALF.x)
		var body_override: Material = block
		_kind_meshes[kind] = {"body": body, "mirror": mirror, "block": block, "reflect": reflect}
		if kind == ObstacleField.Kind.BLOCK:  # 표면마다 재질이 달라 덮어쓰기 재질을 쓰지 않는다
			var pillar := ShaderMaterial.new()
			pillar.shader = PILLAR_SHADER
			pillar.set_shader_parameter("wall_stretch", RunLogic.LANE_WIDTH * 0.5)
			pillar.render_priority = 1  # 젤리보다 뒤에: 젤리 뒤의 기둥은 깊이에 막히고, 젤리 앞의 기둥은 그 위에 비친다
			meshes["body"].surface_set_material(0, pillar)
			meshes["body"].surface_set_material(1, block)
			body_override = null
			_kind_meshes[kind]["pillar"] = pillar
		for pair: Array in [[body, body_override], [mirror, reflect]]:
			var node := MultiMeshInstance3D.new()
			node.multimesh = pair[0]
			node.material_override = pair[1]
			node.extra_cull_margin = 16384.0  # 반사는 셰이더가 옮겨 그리고, 영역 계산보다 몇 번 더 그리는 편이 싸다
			_pieces_root.add_child(node)


func _new_pieces_mesh(mesh: Mesh) -> MultiMesh:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.use_colors = true  # 끄면 꼭짓점 색(COLOR)의 RGB가 0으로 읽혀 반사가 검게 나온다
	many.mesh = mesh
	many.instance_count = MAX_PIECES
	for i in MAX_PIECES:
		many.set_instance_color(i, Color.WHITE)
	many.visible_instance_count = 0
	return many


func _small_label(node_name: String, top: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = size
	settings.font_color = color
	label.label_settings = settings
	return label


## 빛 방울 풀: 구슬과 빛 번짐 MultiMesh 두 개 (그리는 횟수 2). 새 노드를 만들지 않는다. 아슬아슬 빛 줄기도 하나 만들어 둔다.
func _build_orbs() -> void:
	var ball := SphereMesh.new()
	ball.radius = ORB_RADIUS
	ball.height = ORB_RADIUS * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	var halo := QuadMesh.new()
	halo.size = Vector2.ONE * ORB_HALO_SIZE
	_orb_material = ShaderMaterial.new()
	_orb_material.shader = ORB_SHADER
	_orb_material.set_shader_parameter("energy", ORB_ENERGY)
	_orb_material.set_shader_parameter("pulse_energy", ORB_PULSE_ENERGY)
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = ORB_HALO_SHADER
	var thread := BoxMesh.new()
	thread.size = Vector3(ORB_LINK_WIDTH, ORB_LINK_WIDTH, 1.0)  # 길이 1을 두 방울 사이 거리로 늘린다
	_link_material = ShaderMaterial.new()
	_link_material.shader = ORB_LINK_SHADER
	for pair: Array in [[ball, _orb_material, "Orbs"], [halo, _halo_material, "OrbHalos"], [thread, _link_material, "OrbLinks"]]:
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = pair[0]
		many.instance_count = ORB_MAX
		many.visible_instance_count = 0
		var node := MultiMeshInstance3D.new()
		node.name = pair[2]
		node.multimesh = many
		node.material_override = pair[1]
		node.extra_cull_margin = 16384.0
		add_child(node)
		match pair[2]:
			"Orbs": _orbs = many
			"OrbHalos": _halos = many
			_: _links = many
	var ring := QuadMesh.new()
	ring.size = Vector2.ONE * 2.0
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = ORB_RING_SHADER
	_ring = MeshInstance3D.new()
	_ring.name = "AbsorbRing"
	_ring.mesh = ring
	_ring.material_override = _ring_material
	_ring.visible = false
	add_child(_ring)
	_swish_material = StandardMaterial3D.new()
	_swish_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_swish_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_swish_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_swish_material.albedo_color = Color(1, 1, 1, SWISH_ALPHA)
	var bar := BoxMesh.new()
	bar.size = SWISH_SIZE
	_swish = MeshInstance3D.new()
	_swish.name = "Swish"
	_swish.mesh = bar
	_swish.material_override = _swish_material
	_swish.visible = false
	add_child(_swish)


## 게임 오버 NEW SKIN 묶음: "NEW SKIN"(BEST 줄 글씨) → 젤리 미리보기(2D) → EQUIP(DAILY 버튼과 같은 테)
func _build_new_skin(layer: Control) -> void:
	_new_skin = VBoxContainer.new()
	_new_skin.name = "NewSkin"
	_new_skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_skin.add_theme_constant_override("separation", 8)
	_new_skin.visible = false
	layer.add_child(_new_skin)
	var title := TitleScreen.text_label("NewSkinLabel", "NEW SKIN", 40, Color(TitleScreen.LAVENDER, 0.95))
	_new_skin.add_child(title)
	_new_skin_preview = SkinPreview.new()
	_new_skin_preview.custom_minimum_size = PREVIEW_SIZE
	_new_skin.add_child(_new_skin_preview)
	_equip = TitleScreen.text_label("EquipButton", "EQUIP", 36, Color(1, 1, 1, 0.8))
	_equip.add_theme_stylebox_override("normal", _title.daily_button.get_theme_stylebox("normal"))
	_equip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_equip.custom_minimum_size.x = 240.0
	_new_skin.add_child(_equip)


func _build_ui() -> void:
	var root := CanvasLayer.new()
	add_child(root)
	_title = TitleScreen.new()
	root.add_child(_title)
	var layer := Control.new()  # 게임 중 글자를 한꺼번에 흐리고 밝힌다
	layer.name = "Hud"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layer)
	_hud = layer
	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.text = "0"
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_score_label.offset_top = 90.0
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = 170
	settings.font_color = Color.WHITE
	_score_label.label_settings = settings
	layer.add_child(_score_label)

	# 배수: 점수 아래에 작게, ×2 이상일 때만
	_mult_label = _small_label("MultiplierLabel", MULT_TOP, 52, Color(1, 1, 1, 0.9))
	_mult_label.visible = false
	layer.add_child(_mult_label)
	# 게임 오버 한 줄: 먹은 방울, PERFECT, 거리
	_stats_label = _small_label("StatsLabel", STATS_TOP, 30, Color(1, 1, 1, 0.6))
	_stats_label.visible = false
	layer.add_child(_stats_label)
	# 최고 기록: 점수 숫자 아래에 작게 (Poppins에 한글이 없어 영문)
	_best_label = Label.new()
	_best_label.name = "BestLabel"
	_best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_best_label.offset_top = BEST_TOP
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := LabelSettings.new()
	bs.font = FONT
	bs.font_size = 40
	bs.font_color = Color(1, 1, 1, 0.7)
	_best_label.label_settings = bs
	layer.add_child(_best_label)
	# PERFECT: BEST 바로 아래, BEST와 같은 글자 설정을 함께 쓴다 (_on_close)
	_perfect_label = _small_label("PerfectLabel", PERFECT_TOP, 40, Color.WHITE)
	_perfect_label.label_settings = bs
	_perfect_label.visible = false
	layer.add_child(_perfect_label)
	_show_best()

	# 게임 오버 안내 (Poppins에 한글이 없어 영문)
	_restart_label = Label.new()
	_restart_label.name = "RestartLabel"
	_restart_label.text = "TAP TO RESTART"
	_restart_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_restart_label.offset_left = -360.0
	_restart_label.offset_right = 360.0
	_restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restart_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := LabelSettings.new()
	rs.font = FONT
	rs.font_size = 48
	rs.font_color = Color(1, 1, 1, 0.85)
	_restart_label.label_settings = rs
	_restart_label.visible = false
	layer.add_child(_restart_label)
	# 오늘의 판 SHARE: 다시 시작 안내 아래, DAILY 버튼과 같은 연보라 테
	_share = TitleScreen.text_label("ShareButton", "SHARE", 40, Color(1, 1, 1, 0.8))
	_share.set_anchors_preset(Control.PRESET_CENTER)
	_share.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_share.add_theme_stylebox_override("normal", _title.daily_button.get_theme_stylebox("normal"))
	_share.custom_minimum_size.x = 240.0
	_share.visible = false
	layer.add_child(_share)
	_build_new_skin(layer)
	_home = UiIcon.new(UiIcon.Kind.HOME, Color(1, 1, 1, 0.7), TitleScreen.SOUND_SIDE)
	_home.name = "HomeButton"
	TitleScreen.corner(_home, false)
	_home.visible = false
	layer.add_child(_home)
	_pause_btn = UiIcon.new(UiIcon.Kind.PAUSE, Color(1, 1, 1, 0.6), TitleScreen.SOUND_SIDE)
	_pause_btn.name = "PauseButton"
	TitleScreen.corner(_pause_btn, false)
	_pause_btn.visible = false
	layer.add_child(_pause_btn)

	# 아주 흐린 버전 표시 (project.godot 버전을 읽음)
	var version := Label.new()
	version.name = "VersionLabel"
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	version.offset_top = -48.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := LabelSettings.new()
	vs.font = FONT
	vs.font_size = 22
	vs.font_color = Color(1, 1, 1, 0.4)
	version.label_settings = vs
	root.add_child(version)  # 메인 화면에서도 보인다
	_pause_menu = PauseMenu.new()
	_pause_menu.resume_pressed.connect(_on_resume_pressed)
	_pause_menu.resumed.connect(_on_resumed)
	_pause_menu.home_pressed.connect(_on_pause_home)
	_pause_menu.settings_pressed.connect(open_settings)
	root.add_child(_pause_menu)
	# 숨은 성능 표시: 메인 화면·플레이·게임 오버 어디서든 (점수 글자 층과 따로, 맨 위)
	var perf_layer := CanvasLayer.new()
	perf_layer.layer = 50
	add_child(perf_layer)
	_perf_label = Label.new()
	_perf_label.name = "PerfLabel"
	_perf_label.position = Vector2(PerfStats.TAP_ZONE.position.x, 22.0)  # 두 줄이 점수 숫자(위 90px부터, 글자는 더 아래) 위에 들어간다
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := LabelSettings.new()
	ps.font_size = 18
	ps.font_color = Color(0.85, 1.0, 0.9)
	ps.outline_size = 6
	ps.outline_color = Color(0, 0, 0, 0.85)
	_perf_label.label_settings = ps
	_perf_label.visible = false
	perf_layer.add_child(_perf_label)
	_settings = SettingsPanel.new()
	_settings.closed.connect(_on_settings_closed)
	_settings.graphics_changed.connect(apply_graphics)
	root.add_child(_settings)
	var top := CanvasLayer.new()
	top.layer = 50
	add_child(top)
	_fade = ColorRect.new()
	_fade.color = Color(BOOT_COLOR, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	top.add_child(_fade)
