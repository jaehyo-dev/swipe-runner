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


func test_점프_중_또_점프해도_점프가_다시_시작되지_않음() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(0.2)
	var h := a.height()
	a.jump()
	assert_eq(a.height(), h)
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
	assert_eq(PlayerAction.BUFFER_TIME, 0.15, "입력 저장 시간")
	assert_eq(ObstacleField.LOW_TOP, 0.45, "허들 윗면")
	assert_eq(ObstacleField.HIGH_BOTTOM, 0.62, "막대 아랫면")


# ---------- 공중 아래 스와이프 ----------

## 점프 후 t초에 아래로 밀고 땅에 닿을 때까지 걸린 시간을 돌려준다
func _drop_time(t: float) -> float:
	var a := PlayerAction.new()
	a.jump()
	a.step(t)
	a.slide()
	var took := 0.0
	while a.is_dropping():
		a.step(0.001)
		took += 0.001
	return took


func test_공중_아래_스와이프는_빠르게_떨어지고_닿자마자_슬라이드() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(0.3)
	a.slide()
	assert_true(a.is_dropping())
	assert_false(a.is_sliding(), "닿기 전엔 아직 슬라이드 아님")
	var last := a.height()
	while a.is_dropping():
		a.step(1.0 / 60.0)
		assert_true(a.height() < last, "계속 내려감")
		last = a.height()
	assert_true(a.is_sliding(), "닿은 프레임에 슬라이드")
	assert_false(a.is_jumping())
	assert_eq(a.height(), 0.0)
	assert_eq(a.crouch(), 1.0, "시작부터 낮아져 있음")
	assert_true(a.is_ducking(), "닿은 프레임부터 막대 아래를 지남")


func test_떨어지는_시간은_0_1에서_0_15초() -> void:
	for t: float in [0.05, 0.1, 0.2, 0.3, 0.4]:
		var took := _drop_time(t)
		assert_true(took >= 0.1 - 0.002 and took <= 0.15 + 0.002, "%.2f초에 밀면 %.3f초" % [t, took])
	assert_true(absf(_drop_time(0.3) - 0.15) < 0.002, "꼭대기에서 0.15초")


func test_착지_직전에_밀어도_원래_착지보다_늦어지지_않음() -> void:
	var took := _drop_time(PlayerAction.JUMP_TIME - 0.03)
	assert_true(took <= 0.03 + 0.002, "%.3f초" % took)


func test_슬라이드_시간은_땅에_닿은_때부터_0_65초() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(0.3)
	a.slide()
	while a.is_dropping():
		a.step(0.01)
	a.step(PlayerAction.SLIDE_TIME - 0.02)
	assert_true(a.is_sliding(), "아직 슬라이드")
	a.step(0.03)
	assert_false(a.is_sliding(), "0.65초에 끝남")


func test_떨어지는_동안_판정() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(0.3)
	a.slide()
	a.step(0.1)
	assert_true(a.is_ducking(), "막대: 입력 순간부터 지나감")
	assert_false(PlayerAction.hits(Kind.HIGH, 0.0, 0.0, a.height(), a.is_ducking()))
	assert_true(PlayerAction.hits(Kind.BLOCK, 0.0, 0.0, a.height(), a.is_ducking()), "블록은 그대로 부딪힘")
	assert_true(PlayerAction.hits(Kind.LOW, 0.0, 0.0, 0.1, a.is_ducking()), "허들: 낮아지면 부딪힘")
	assert_true(PlayerAction.clears_on_drop(Kind.LOW, 0.0, 0.0, 1.0), "넘고 있던 허들은 봐줌")
	assert_false(PlayerAction.clears_on_drop(Kind.LOW, 0.0, -3.0, 1.0), "아직 먼 허들은 봐주지 않음")
	assert_false(PlayerAction.clears_on_drop(Kind.LOW, 0.0, 0.0, 0.2), "넘지 못한 높이")
	assert_false(PlayerAction.clears_on_drop(Kind.BLOCK, 0.0, 0.0, 1.0), "블록은 봐주지 않음")


func test_보통_착지는_슬라이드가_되지_않음() -> void:
	var a := PlayerAction.new()
	a.jump()
	a.step(PlayerAction.JUMP_TIME + 0.01)
	assert_false(a.is_jumping())
	assert_false(a.is_sliding())


# ---------- 입력 저장 ----------

## 착지 before초 전에 점프 입력을 넣고 착지시킨다
func _buffered_jump(before: float) -> PlayerAction:
	var a := PlayerAction.new()
	a.jump()
	a.step(PlayerAction.JUMP_TIME - before)
	a.jump()
	a.step(before)
	return a


func test_착지_0_15초_안에_넣은_점프는_닿자마자_실행() -> void:
	var a := _buffered_jump(0.14)
	assert_true(a.is_jumping(), "닿은 프레임에 다시 뜀")
	a.step(0.1)
	assert_true(a.height() > 0.0)


func test_0_15초보다_일찍_넣은_점프는_버림() -> void:
	assert_false(_buffered_jump(0.16).is_jumping())


func test_저장은_하나만_새_입력이_덮어씀() -> void:
	# 슬라이드 중: 아래를 저장했다가 위가 오면 저장을 지우고 바로 뜀
	var a := PlayerAction.new()
	a.slide()
	a.step(PlayerAction.SLIDE_TIME - 0.1)
	a.slide()
	a.jump()
	assert_true(a.is_jumping(), "슬라이드 중 위는 지금처럼 바로")
	a.step(PlayerAction.JUMP_TIME + 0.01)
	assert_false(a.is_sliding(), "지워진 입력은 실행되지 않음")
	# 떨어지는 중: 위가 슬라이드를 덮어쓰고, 다시 아래가 위를 덮어쓴다
	var b := PlayerAction.new()
	b.jump()
	b.step(0.3)
	b.slide()
	b.jump()
	b.step(0.15)
	assert_true(b.is_jumping() and not b.is_sliding(), "위가 덮어써서 닿자마자 점프")
	var c := PlayerAction.new()
	c.jump()
	c.step(0.3)
	c.slide()
	c.jump()
	c.slide()
	c.step(0.15)
	assert_true(c.is_sliding() and not c.is_jumping(), "다시 아래가 덮어씀")


func test_슬라이드_끝_0_15초_안의_아래는_끝나자마자_다시_슬라이드() -> void:
	var a := PlayerAction.new()
	a.slide()
	a.step(PlayerAction.SLIDE_TIME - 0.1)
	a.slide()
	a.step(0.1)
	assert_true(a.is_sliding(), "다시 슬라이드")
	assert_eq(a.crouch(), 0.0, "끝난 몸에서 다시 낮아짐")
	var b := PlayerAction.new()
	b.slide()
	b.step(PlayerAction.SLIDE_TIME - 0.2)
	b.slide()
	b.step(0.2)
	assert_false(b.is_sliding(), "0.2초 전 입력은 버림")


func test_저장된_입력은_한_번만_실행() -> void:
	var a := _buffered_jump(0.1)
	a.step(PlayerAction.JUMP_TIME + 0.01)
	assert_false(a.is_jumping(), "한 번 뛰고 끝")


## 저장만 된 입력은 새 동작이 아니다: 아슬아슬 판정 시각을 바꾸지 않게 main이 이 값을 본다 (Codex 리뷰)
func test_점프_슬라이드는_새로_시작했을_때만_true() -> void:
	var a := PlayerAction.new()
	assert_true(a.slide(), "땅에서 슬라이드")
	assert_false(a.slide(), "슬라이드 중 또 아래는 저장만")
	assert_true(a.jump(), "슬라이드 중 점프는 끊고 뜀")
	assert_false(a.jump(), "공중 점프는 저장만")
	assert_true(a.slide(), "공중 아래는 빠르게 떨어지기 시작")
	assert_false(a.slide(), "떨어지는 중 아래는 저장만")
