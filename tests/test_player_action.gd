extends TestCase
## 점프·슬라이드 상태와 충돌 판정 테스트.

const Kind := ObstacleField.Kind


func test_점프는_포물선이고_끝나면_땅으로() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(PlayerAction.JUMP_TIME / 2.0)
	assert_true(absf(a.height() - PlayerAction.JUMP_HEIGHT) < 0.001, "정점 높이")
	a.step(PlayerAction.JUMP_TIME / 2.0 + 0.01)
	assert_false(a.is_jumping())
	assert_eq(a.height(), 0.0)


func test_점프_중_또_점프하거나_슬라이드는_무시() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(0.2)
	var h := a.height()
	a.jump()
	a.slide()
	assert_eq(a.height(), h, "점프가 다시 시작되지 않음")
	assert_false(a.is_sliding())


func test_슬라이드_중_점프하면_슬라이드가_끊김() -> void:
	var a := PlayerAction.new()
	a.slide()
	a.step(0.3)
	assert_true(a.is_ducking())
	a.jump()
	assert_false(a.is_sliding())
	assert_true(a.is_jumping())


func test_슬라이드는_부드럽게_낮아졌다_끝나면_복귀() -> void:
	var a := PlayerAction.new()
	a.slide()
	assert_eq(a.crouch(), 0.0)
	a.step(PlayerAction.SLIDE_FADE / 2.0)
	assert_true(a.crouch() > 0.0 and a.crouch() < 1.0, "낮아지는 중")
	assert_false(a.is_ducking(), "낮아지는 중엔 아직 통과 못 함")
	a.step(PlayerAction.SLIDE_TIME)
	assert_false(a.is_sliding())
	assert_eq(a.crouch(), 0.0)


func test_블록은_높이와_상관없이_부딪힘() -> void:
	assert_true(PlayerAction.hits(Kind.BLOCK, 0.0, 0.0, 0.0, false))
	assert_true(PlayerAction.hits(Kind.BLOCK, 0.0, 0.0, 1.6, false), "점프해도 블록은 못 넘음")
	assert_true(PlayerAction.hits(Kind.BLOCK, 0.0, 0.0, 0.0, true), "슬라이드해도 블록은 못 지남")


func test_허들은_충분히_뜨면_넘고_막대는_낮아지면_지남() -> void:
	assert_true(PlayerAction.hits(Kind.LOW, 0.0, 0.0, 0.0, false), "그냥 가면 부딪힘")
	assert_false(PlayerAction.hits(Kind.LOW, 0.0, 0.0, ObstacleField.LOW_TOP + 0.01, false), "점프로 넘음")
	assert_true(PlayerAction.hits(Kind.HIGH, 0.0, 0.0, 0.0, false), "그냥 가면 부딪힘")
	assert_true(PlayerAction.hits(Kind.HIGH, 0.0, 0.0, 1.0, false), "점프하면 막대에 부딪힘")
	assert_false(PlayerAction.hits(Kind.HIGH, 0.0, 0.0, 0.0, true), "슬라이드로 지남")


func test_다른_레인이거나_멀면_부딪히지_않음() -> void:
	assert_false(PlayerAction.hits(Kind.BLOCK, RunLogic.LANE_WIDTH, 0.0, 0.0, false), "옆 레인")
	assert_false(PlayerAction.hits(Kind.BLOCK, 0.0, 3.0, 0.0, false), "아직 멀리 있음")
	assert_false(PlayerAction.hits(Kind.BLOCK, 0.0, -3.0, 0.0, false), "이미 지나감")


func test_점프로_허들_위를_지나는_동안_내내_충돌_없음() -> void:
	# 허들이 충돌 범위(앞뒤 HIT_Z)를 통과하는 동안 점프 높이가 계속 LOW_TOP 위여야 한다.
	var a := PlayerAction.new()
	a.jump()
	a.step(0.1)  # 점프 시작 직후엔 아직 낮다 → 이 시점에 뛰어 들어가면 부딪히는 게 맞음
	var window := 2.0 * PlayerAction.HIT_Z / RunLogic.SPEED
	var t := 0.0
	var clear := true
	while t < window:
		clear = clear and not PlayerAction.hits(Kind.LOW, 0.0, 0.0, a.height(), false)
		a.step(0.01)
		t += 0.01
	assert_true(clear, "정점 근처 구간에서 허들을 넘음")


func test_판정_값은_v0_2_0과_같음() -> void:
	# 점프·슬라이드 모션(v0.2.3)은 화면만 바꾼다. 판정을 바꾸려면 사용자 확인 뒤 이 테스트도 함께 고친다
	assert_eq(PlayerAction.JUMP_TIME, 0.6, "점프 시간")
	assert_eq(PlayerAction.JUMP_HEIGHT, 1.6, "점프 최고 높이")
	assert_eq(PlayerAction.SLIDE_TIME, 0.65, "슬라이드 시간")
	assert_eq(PlayerAction.SLIDE_FADE, 0.08, "슬라이드 낮아지는 시간")
	assert_eq(PlayerAction.CROUCH_SCALE, 0.45, "슬라이드 판정 높이 배율")
	assert_eq(PlayerAction.HIT_X, 0.7, "충돌 범위 좌우")
	assert_eq(PlayerAction.HIT_Z, 0.7, "충돌 범위 앞뒤")
