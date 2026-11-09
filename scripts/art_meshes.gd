class_name ArtMeshes
extends RefCounted
## 장애물·난간 메시를 코드로 만든다 (텍스처 없음). 모양 기준은 ART_BIBLE.md 6·10장.
## 장애물 몸통과 앞면 테두리는 한 메시·한 재질이라 종류마다 MultiMesh 하나로 그린다 (glass.gdshader). 뒤쪽 테두리는 만들지 않는다.
## 모든 장애물은 바닥(y=0)을 원점으로 삼고, 크기는 ObstacleField 판정 값에서 그대로 가져온다 (보이는 모양 = 판정 범위).
## 선은 가는 관(tube)이라 메시 하나에 모이고, 관 반지름을 UV.x에 담아 neon.gdshader가 멀리서 최소 굵기를 지키게 한다.

const TUBE_SIDES := 6
const ELLIPSE_SIDES := 20
const EDGE_RADIUS := 0.024
const GRAIN_RADIUS := 0.014
const ARROW_RADIUS := 0.03
const PILLAR_ROOF_START := 1.75  # 지붕이 시작하는 높이 (꼭대기는 ObstacleField.BLOCK_HEIGHT)
const LOW_CORNER := 0.13
const HIGH_CORNER := 0.17
const GRAIN_LEVEL := 0.55        # 세로 결 밝기 (모서리 = 1)
const MIRROR_GLASS_ALPHA := 0.15 # 반사 불투명도: 15~25% 안에서 면은 낮게, 선은 높게
const MIRROR_EDGE_ALPHA := 0.25
const POOL_ALPHA := 0.3          # 막대 아래 빛 웅덩이 가운데 불투명도 (35% 이하): 기둥 없이 떠 있는 높이를 말해 준다
const POOL_HALF := Vector2(0.58, 0.46)    # 웅덩이 반지름 (x, z): 막대 폭의 절반 0.65보다 살짝 좁게
const SHADOW_ALPHA := 0.6        # 기둥 접지 그림자 가운데 불투명도: 어디에 서 있는지 읽히게
const SHADOW_HALF := Vector2(0.85, 0.95)  # 그림자 반지름 (x, z): 기둥 밑면(0.55, 0.64)보다 조금 크게

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()


## 종류별 {body, mirror} 메시. 색은 재질 값이다.
## body: 몸통 + 앞면 테두리. UV.x > 0이면 테두리 관 (glass.gdshader), COLOR.r은 테두리 밝기.
## mirror: 바닥 반사 + 바닥 흔적. COLOR.r 면(0)·선(1), COLOR.g 그림자, COLOR.b 1이면 멀어도 그리는 바닥 흔적, COLOR.a 불투명도 (mirror.gdshader)
static func obstacle(kind: ObstacleField.Kind) -> Dictionary:
	var glass := ArtMeshes.new()
	var lines := ArtMeshes.new()
	match kind:
		ObstacleField.Kind.BLOCK:
			glass._pillar_faces()
			lines._pillar_lines()
		ObstacleField.Kind.LOW:
			var size := Vector3(ObstacleField.BAR_WIDTH, ObstacleField.LOW_TOP, ObstacleField.BAR_DEPTH)
			glass._rounded_box(size, LOW_CORNER, Vector3(0.0, size.y * 0.5, 0.0), true)
			lines._low_lines(size)
		ObstacleField.Kind.HIGH:
			var size := Vector3(ObstacleField.BAR_WIDTH, ObstacleField.HIGH_TOP - ObstacleField.HIGH_BOTTOM, ObstacleField.BAR_DEPTH)
			glass._rounded_box(size, HIGH_CORNER, Vector3(0.0, ObstacleField.HIGH_BOTTOM + size.y * 0.5, 0.0), false)
			lines._high_lines(size)
	var mirror := ArtMeshes.new()
	mirror._add_mirrored(glass, 0.0, MIRROR_GLASS_ALPHA)
	mirror._add_mirrored(lines, 1.0, MIRROR_EDGE_ALPHA)
	if kind == ObstacleField.Kind.HIGH:
		mirror._floor_ellipse(POOL_HALF, Color(0.0, 0.0, 1.0, POOL_ALPHA))
	elif kind == ObstacleField.Kind.BLOCK:
		mirror._floor_ellipse(SHADOW_HALF, Color(0.0, 1.0, 1.0, SHADOW_ALPHA))
	glass._add_all(lines)
	return {"body": glass.commit(), "mirror": mirror.commit()}


## 양옆 난간 한 벌: 굵은 네온 관 + 안쪽의 가는 보조선. 길이 방향으로 나눠 멀리까지 원근과 안개가 자연스럽다.
static func rails(x: float, tube_y: float, tube_radius: float, inner_x: float, inner_radius: float, z_near: float, z_far: float, piece: float) -> ArrayMesh:
	var m := ArtMeshes.new()
	var z := z_near
	while z > z_far:
		var next := z - piece
		for side in [-1.0, 1.0]:
			m._tube(Vector3(side * x, tube_y, z), Vector3(side * x, tube_y, next), tube_radius, 1.0)
			m._tube(Vector3(side * inner_x, inner_radius, z), Vector3(side * inner_x, inner_radius, next), inner_radius, 0.5)
		z = next
	return m.commit()


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _vertex(p: Vector3, n: Vector3, c: Color, tube_radius := 0.0) -> void:
	_v.append(p)
	_n.append(n)
	_c.append(c)
	_uv.append(Vector2(tube_radius, 0.0))


func _flat_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c]:
		_vertex(p, n, Color.WHITE)


## 높이 y의 육각 꼭짓점. x 폭과 z 깊이를 BLOCK_SIZE에 맞추려고 z만 늘린다. 카메라 쪽으로 평평한 면 하나가 보인다.
static func _hex(i: int, y: float) -> Vector3:
	var half := ObstacleField.BLOCK_SIZE * 0.5
	var a := TAU * i / 6.0
	return Vector3(cos(a) * half, y, sin(a) * half / sin(TAU / 6.0))


func _pillar_faces() -> void:
	var top := Vector3(0.0, ObstacleField.BLOCK_HEIGHT, 0.0)
	for i in 6:
		var a := _hex(i, 0.0)
		var b := _hex(i + 1, 0.0)
		var c := _hex(i + 1, PILLAR_ROOF_START)
		var d := _hex(i, PILLAR_ROOF_START)
		_flat_tri(a, b, c)
		_flat_tri(a, c, d)
		_flat_tri(d, c, top)


## 카메라 쪽(z > 0)에 있는 꼭짓점과 모서리만 그린다: 0(오른쪽)~3(왼쪽). 꼭짓점 0과 3은 옆 윤곽이다.
func _pillar_lines() -> void:
	var top := Vector3(0.0, ObstacleField.BLOCK_HEIGHT, 0.0)
	for i in 4:
		_tube(_hex(i, 0.0), _hex(i, PILLAR_ROOF_START), EDGE_RADIUS)
		_tube(_hex(i, PILLAR_ROOF_START), top, EDGE_RADIUS)
		if i < 3:
			_tube(_hex(i, 0.0), _hex(i + 1, 0.0), EDGE_RADIUS)
			_tube(_hex(i, PILLAR_ROOF_START), _hex(i + 1, PILLAR_ROOF_START), EDGE_RADIUS)
	# 앞면 세로 결 3줄 (길이가 달라 얼음 금처럼 보인다)
	var z := ObstacleField.BLOCK_SIZE * 0.5 + 0.004
	for grain: Vector3 in [Vector3(-0.15, 0.25, 1.1), Vector3(0.0, 0.7, 1.62), Vector3(0.14, 0.18, 0.85)]:
		_tube(Vector3(grain.x, grain.y, z), Vector3(grain.x, grain.z, z), GRAIN_RADIUS, GRAIN_LEVEL)


func _low_lines(size: Vector3) -> void:
	_outline(size, 0.0, LOW_CORNER, size.z * 0.5, true)
	# 앞면의 위쪽 화살 ^ 3개
	var y := size.y * 0.5
	var z := size.z * 0.5 + 0.006
	for x in [-0.42, 0.0, 0.42]:
		_arrow(Vector3(x, y, z), 0.13, 0.085, 1.0)


func _high_lines(size: Vector3) -> void:
	_outline(size, ObstacleField.HIGH_BOTTOM, HIGH_CORNER, size.z * 0.5, false)
	# 앞면의 아래 화살 v 2개
	var y := ObstacleField.HIGH_BOTTOM + size.y * 0.5
	var z := size.z * 0.5 + 0.006
	for x in [-0.27, 0.27]:
		_arrow(Vector3(x, y, z), 0.17, 0.12, -1.0)


## 화살 하나: up이 1이면 ^, -1이면 v
func _arrow(center: Vector3, half_w: float, half_h: float, up: float) -> void:
	var tip := center + Vector3(0.0, half_h * up, 0.0)
	for side in [-1.0, 1.0]:
		_tube(center + Vector3(side * half_w, -half_h * up, 0.0), tip, ARROW_RADIUS)


## 둥근 직사각형 테두리 (앞뒤 면 가장자리). 둥근 면 위에 올라오도록 안쪽으로 조금 들인다. flat_bottom이면 아래 모서리는 각지게 바닥에 붙는다.
func _outline(size: Vector3, bottom: float, r: float, z: float, flat_bottom: bool) -> void:
	var inset := r * (1.0 - sqrt(0.5))
	var half_x := size.x * 0.5 - inset
	var low := bottom + (0.0 if flat_bottom else inset)
	var high := bottom + size.y - inset
	var cr := r * sqrt(0.5)
	var at_z: float = z - signf(z) * inset
	var points: Array[Vector2] = []
	var corners: Array[Vector3] = [Vector3(half_x - cr, high - cr, 0.0), Vector3(-half_x + cr, high - cr, 90.0)]
	if not flat_bottom:
		corners += [Vector3(-half_x + cr, low + cr, 180.0), Vector3(half_x - cr, low + cr, 270.0)]
	for corner in corners:
		for i in 5:
			var a := deg_to_rad(corner.z + 22.5 * i)
			points.append(Vector2(corner.x + cos(a) * cr, corner.y + sin(a) * cr))
	if flat_bottom:  # 왼쪽 위 모서리에서 내려와 바닥을 지나 처음 점으로 닫힌다
		points += [Vector2(-half_x, low), Vector2(half_x, low)]
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		_tube(Vector3(p.x, p.y, at_z), Vector3(q.x, q.y, at_z), EDGE_RADIUS)


## 두 점을 잇는 둥근 관. level은 밝기 (꼭짓점 색 빨강 채널).
func _tube(a: Vector3, b: Vector3, radius: float, level := 1.0) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.UP).normalized()
	var up := dir.cross(side)
	var c := Color(level, level, level)
	for i in TUBE_SIDES:
		var a0 := TAU * i / TUBE_SIDES
		var a1 := TAU * (i + 1) / TUBE_SIDES
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		for pn: Array in [[a, n0], [b, n1], [b, n0], [a, n0], [a, n1], [b, n1]]:
			_vertex(pn[0] + pn[1] * radius, pn[1], c, radius)


## 둥근 모서리 상자. flush면 바닥보다 아래로 내려가는 모서리를 눌러 바닥에 그대로 붙인다.
func _rounded_box(size: Vector3, r: float, center: Vector3, flush: bool) -> void:
	var half := size * 0.5
	var inner := half - Vector3.ONE * r
	var bend := r * tan(deg_to_rad(22.5))
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		var us: Array[float] = [-half[u], -inner[u] - bend, -inner[u], inner[u], inner[u] + bend, half[u]]
		var ws: Array[float] = [-half[w], -inner[w] - bend, -inner[w], inner[w], inner[w] + bend, half[w]]
		for face in [-1.0, 1.0]:
			for i in us.size() - 1:
				for j in ws.size() - 1:
					for uv: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
						var p := Vector3.ZERO
						p[axis] = face * half[axis]
						p[u] = us[uv.x]
						p[w] = ws[uv.y]
						var q := p.clamp(-inner, inner)
						var n := (p - q).normalized()
						var at := center + q + n * r
						if flush:
							at.y = maxf(at.y, 0.0)
						_vertex(at, n, Color.WHITE)


## 바닥 아래로 뒤집은 복제본을 넣는다 (mirror.gdshader가 바닥 면으로 눌러 그린다). pick: 0 면 색, 1 선 색
func _add_mirrored(from: ArtMeshes, pick: float, alpha: float) -> void:
	for i in from._v.size():
		var p := from._v[i]
		_vertex(Vector3(p.x, -p.y, p.z), from._n[i], Color(pick, 0.0, 0.0, alpha * from._c[i].r))


## 다른 메시의 꼭짓점을 그대로 뒤에 붙인다 (몸통 먼저, 테두리는 그 위에)
func _add_all(from: ArtMeshes) -> void:
	_v.append_array(from._v)
	_n.append_array(from._n)
	_c.append_array(from._c)
	_uv.append_array(from._uv)


## 바닥에 놓인 타원: 가운데가 진하고 가장자리에서 0이 되어 경계가 보이지 않는다. c.a: 가운데 불투명도
func _floor_ellipse(half: Vector2, c: Color) -> void:
	var rings: Array[float] = [0.0, 0.3, 0.55, 0.8, 1.0]
	var fade := func(r: float) -> Color: return Color(c.r, c.g, c.b, c.a * (1.0 - smoothstep(0.0, 1.0, r)))
	var at := func(r: float, a: float) -> Vector3: return Vector3(cos(a) * half.x * r, 0.0, sin(a) * half.y * r)
	for k in ELLIPSE_SIDES:
		var a0 := TAU * k / ELLIPSE_SIDES
		var a1 := TAU * (k + 1) / ELLIPSE_SIDES
		for i in rings.size() - 1:
			var r0 := rings[i]
			var r1 := rings[i + 1]
			for pair: Array in [[r0, a0], [r1, a1], [r1, a0], [r0, a0], [r0, a1], [r1, a1]]:
				_vertex(at.call(pair[0], pair[1]), Vector3.UP, fade.call(pair[0]))
