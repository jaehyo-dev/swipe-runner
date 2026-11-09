class_name ArtMeshes
extends RefCounted
## 장애물·난간·레이저 메시를 코드로 만든다 (텍스처 없음). 모양 기준은 ART_BIBLE.md 6·10장.
## 장애물 몸통·테두리·기호는 한 메시·한 재질이라 종류마다 MultiMesh 하나로 그린다 (block.gdshader).
## 모든 장애물은 바닥(y=0)을 원점으로 삼고, 크기는 ObstacleField 판정 값에서 그대로 가져온다 (보이는 모양 = 판정 범위).
## 선은 가는 관(tube)이라 메시 하나에 모이고, 관 반지름을 UV.x, 부위를 UV.y에 담아 셰이더가 멀리서 최소 굵기를 지키게 한다.

enum Part { BODY, EDGE, MARK }

const TUBE_SIDES := 6
const CAP_RINGS := 3
const ELLIPSE_SIDES := 20
const EDGE_RADIUS := 0.034
const CORNER := {ObstacleField.Kind.BLOCK: 0.1, ObstacleField.Kind.LOW: 0.09, ObstacleField.Kind.HIGH: 0.11}
const MARK_SHARE := 0.55         # 기호 크기: 앞면 폭·높이의 55% (둥근 끝까지 포함)
const MARK_RADIUS := {ObstacleField.Kind.BLOCK: 0.058, ObstacleField.Kind.LOW: 0.044, ObstacleField.Kind.HIGH: 0.05}
const BLOCK_MARK_GAP := 0.14     # ‹ ›의 꺾쇠 사이 빈틈의 절반
const MIRROR_BODY_ALPHA := 0.5   # 반사 불투명도: 몸통은 어두워 바닥을 가리는 역할, 빛은 또렷하게
const MIRROR_EDGE_ALPHA := 0.3
const POOL_ALPHA := 0.3          # 슬라이드 블록 아래 빛 웅덩이 가운데 불투명도 (35% 이하): 떠 있는 높이를 말해 준다
const POOL_HALF := Vector2(0.58, 0.46)    # 웅덩이 반지름 (x, z): 블록 폭의 절반 0.65보다 살짝 좁게
const LASER_COUNT := 6           # 양쪽 번갈아: 앞에서부터 켜지므로 4줄이면 양쪽 2줄씩
const LASER_ORIGIN := Vector3(34.0, -1.0, -150.0)  # 첫 줄 시작점 (x는 양쪽)
const LASER_STEP := 30.0         # 같은 쪽 다음 줄이 더 바깥으로 가는 거리

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _part := Part.BODY


## 종류별 {body, mirror} 메시. 색은 재질 값이다.
## body: 몸통 + 테두리 + 기호. UV.x 관 반지름(몸통 0), UV.y 부위.
## mirror: 바닥 반사 + 바닥 흔적. COLOR.r 몸통(0)·빛(1), COLOR.b 1이면 멀어도 그리는 바닥 흔적, COLOR.a 불투명도 (mirror.gdshader)
static func obstacle(kind: ObstacleField.Kind) -> Dictionary:
	var size: Vector3 = _size_of(kind)
	var bottom: float = ObstacleField.HIGH_BOTTOM if kind == ObstacleField.Kind.HIGH else 0.0
	var flush: bool = kind != ObstacleField.Kind.HIGH
	var corner: float = CORNER[kind]
	var body := ArtMeshes.new()
	body._rounded_box(size, corner, Vector3(0.0, bottom + size.y * 0.5, 0.0), flush)
	var front := ArtMeshes.new()
	front._outline(size, bottom, corner, size.z * 0.5, flush)
	var mirror := ArtMeshes.new()
	mirror._add_mirrored(body, 0.0, MIRROR_BODY_ALPHA)
	mirror._add_mirrored(front, 1.0, MIRROR_EDGE_ALPHA)  # 앞 테두리만 비친다. 기호는 비치지 않는다: 뒤집힌 ^는 슬라이드 기호 v로 읽힌다
	var lines := ArtMeshes.new()
	lines._part = Part.EDGE
	lines._box_edges(size, bottom, corner, flush)
	lines._part = Part.MARK
	lines._mark(kind, size, bottom)
	if kind == ObstacleField.Kind.HIGH:
		mirror._floor_ellipse(POOL_HALF, Color(1.0, 0.0, 1.0, POOL_ALPHA))
	body._add_all(lines)
	return {"body": body.commit(), "mirror": mirror.commit()}


static func _size_of(kind: ObstacleField.Kind) -> Vector3:
	match kind:
		ObstacleField.Kind.BLOCK:
			return Vector3(ObstacleField.BLOCK_SIZE, ObstacleField.BLOCK_HEIGHT, ObstacleField.BLOCK_SIZE)
		ObstacleField.Kind.LOW:
			return Vector3(ObstacleField.BAR_WIDTH, ObstacleField.LOW_TOP, ObstacleField.BAR_DEPTH)
		_:
			return Vector3(ObstacleField.BAR_WIDTH, ObstacleField.HIGH_TOP - ObstacleField.HIGH_BOTTOM, ObstacleField.BAR_DEPTH)


## 양옆 난간: 굵은 네온 관 + 위쪽의 흰빛 심(UV.y = EDGE). 길이 방향으로 나눠 멀리까지 원근과 안개가 자연스럽다.
static func rails(x: float, tube_y: float, tube_radius: float, z_near: float, z_far: float, piece: float) -> ArrayMesh:
	var m := ArtMeshes.new()
	var core_y := tube_y + tube_radius * 0.8
	var core_radius := tube_radius * 0.2
	var z := z_near
	while z > z_far:
		var next := z - piece
		for side in [-1.0, 1.0]:
			m._part = Part.BODY
			m._tube(Vector3(side * x, tube_y, z), Vector3(side * x, tube_y, next), tube_radius)
			m._part = Part.EDGE
			m._tube(Vector3(side * x, core_y, z), Vector3(side * x, core_y, next), core_radius)
		z = next
	return m.commit()


## 레이저 6줄 한 메시. 줄마다 사각형 하나, 움직임은 laser.gdshader가 계산한다.
static func lasers() -> ArrayMesh:
	var m := ArtMeshes.new()
	for i in LASER_COUNT:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * (LASER_ORIGIN.x + (i / 2) * LASER_STEP), LASER_ORIGIN.y, LASER_ORIGIN.z)
		var c := Color(float(i % 2 == (i / 2) % 2), i / float(LASER_COUNT - 1), fposmod(i * 0.37, 1.0), fposmod(i * 0.61, 1.0))
		for uv: Vector2 in [Vector2(0.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(0.0, -1.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]:
			m._v.append(at)
			m._n.append(Vector3.BACK)
			m._c.append(c)
			m._uv.append(uv)
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
	_uv.append(Vector2(tube_radius, float(_part)))


## 상자의 빛 모서리: 앞뒤 둘레 + 잇는 모서리. 몸통이 불투명해 뒤쪽 선은 저절로 가려진다.
func _box_edges(size: Vector3, bottom: float, r: float, flush: bool) -> void:
	var half_z := size.z * 0.5
	_outline(size, bottom, r, half_z, flush)
	_outline(size, bottom, r, -half_z, flush)
	var inset := r * (1.0 - sqrt(0.5))
	var x := size.x * 0.5 - inset
	var top := bottom + size.y - inset
	var low := bottom + (0.0 if flush else inset)
	for side in [-1.0, 1.0]:
		for y in [top, low]:
			_tube(Vector3(side * x, y, half_z - inset), Vector3(side * x, y, -half_z + inset), EDGE_RADIUS)


## 앞면 기호: 굵고 둥근 선 하나. 옆 = ‹ ›, 점프 = ^, 슬라이드 = v. 폭과 높이가 앞면의 MARK_SHARE가 되도록 둥근 끝을 뺀 자리에 놓는다.
func _mark(kind: ObstacleField.Kind, size: Vector3, bottom: float) -> void:
	var r: float = MARK_RADIUS[kind]
	var half_w := size.x * MARK_SHARE * 0.5 - r
	var half_h := size.y * MARK_SHARE * 0.5 - r
	var y := bottom + size.y * 0.5
	var z := size.z * 0.5 - r * 0.3  # 앞면에서 살짝 솟은 관
	match kind:
		ObstacleField.Kind.BLOCK:
			for side: float in [-1.0, 1.0]:
				var inner := side * BLOCK_MARK_GAP
				_chevron(Vector3(side * half_w, y, z), Vector3(inner, y + half_h, z), Vector3(inner, y - half_h, z), r)
		ObstacleField.Kind.LOW:
			_chevron(Vector3(0.0, y + half_h, z), Vector3(-half_w, y - half_h, z), Vector3(half_w, y - half_h, z), r)
		ObstacleField.Kind.HIGH:
			_chevron(Vector3(0.0, y - half_h, z), Vector3(-half_w, y + half_h, z), Vector3(half_w, y + half_h, z), r)


## 꺾쇠 하나: 꼭짓점 tip에서 두 끝으로 가는 둥근 선
func _chevron(tip: Vector3, end_a: Vector3, end_b: Vector3, r: float) -> void:
	_cap(tip, r)
	for end: Vector3 in [end_a, end_b]:
		_tube(tip, end, r)
		_cap(end, r)


## 선 끝의 둥근 마개: 작은 공
func _cap(center: Vector3, r: float) -> void:
	var point := func(i: int, j: int) -> Vector3:
		var lat := PI * i / CAP_RINGS
		var lon := TAU * j / TUBE_SIDES
		return Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
	for i in CAP_RINGS:
		for j in TUBE_SIDES:
			for pair: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var n: Vector3 = point.call(pair.x, pair.y)
				_vertex(center + n * r, n, Color.WHITE, r)


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
		for pn: Array in [[a, n0], [b, n0], [b, n1], [a, n0], [b, n1], [a, n1]]:  # 바깥이 앞면 (불투명 재질은 뒷면을 잘라 낸다)
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
					var corners: Array[Vector2i] = [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
					if face > 0.0:  # 불투명 몸통은 뒷면을 잘라 내므로 면마다 감기 방향을 바깥쪽으로 맞춘다
						corners.reverse()
					for uv: Vector2i in corners:
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
