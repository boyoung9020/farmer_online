extends Node3D
## 마을 풍경.
## - 공용 연못(농지 북쪽) 주변의 시골집 몇 채 (PBR 텍스처)
## - 들판 전체에 나무 2종/바위 산포 (MultiMesh, 지형 높이 반영)
## - 플레이어 주변 들판에 바람에 흔들리는 잔디 수만 그루

const Visuals := preload("res://scripts/visuals.gd")

const TREE_COUNT := 260
const ROCK_COUNT := 70
const GRASS_COUNT := 30000

var terrain   # terrain.gd — height_at(x, z)

func _ready() -> void:
	_build_houses()
	_build_power_lines()
	_scatter_nature()
	_scatter_grass()

func _h(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0

# --- 집 ---
func _build_houses() -> void:
	# 연못(월드 약 (0, -24)) 북쪽·서쪽으로 옹기종기
	var spots := [
		[Vector3(-14, 0, -42), 0.35],
		[Vector3(0, 0, -46), 0.0],
		[Vector3(13, 0, -43), -0.4],
		[Vector3(-26, 0, -33), 0.9],
	]
	for s in spots:
		var h := _house()
		h.position = s[0]
		h.rotation.y = s[1]
		add_child(h)

## 시골집 한 채: 회벽 + 기와지붕 + 문/창. (공용 PBR 재질)
func _house() -> Node3D:
	var root := Node3D.new()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.68, 0.75)
	glass.roughness = 0.15
	glass.metallic = 0.4

	# 기단(돌)
	_box(root, Vector3(4.6, 0.3, 3.8), Vector3(0, 0.15, 0), Visuals.stone_mat())
	# 몸체(회벽)
	_box(root, Vector3(4.0, 2.2, 3.2), Vector3(0, 1.4, 0), Visuals.plaster_mat())
	# 기와지붕(맞배)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(4.8, 1.5, 4.0)
	roof.mesh = pm
	roof.position = Vector3(0, 3.25, 0)
	roof.material_override = Visuals.roof_mat()
	root.add_child(roof)
	# 문/창(정면 -Z)
	_box(root, Vector3(0.85, 1.5, 0.08), Vector3(0, 1.05, -1.65), Visuals.wood_mat())
	var win_l := MeshInstance3D.new()
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(0.75, 0.65, 0.06)
	win_l.mesh = win_mesh
	win_l.position = Vector3(-1.25, 1.6, -1.64)
	win_l.material_override = glass
	root.add_child(win_l)
	var win_r := win_l.duplicate()
	win_r.position = Vector3(1.25, 1.6, -1.64)
	root.add_child(win_r)

	# 굴뚝
	_box(root, Vector3(0.4, 1.4, 0.4), Vector3(1.5, 3.6, 0.9), Visuals.stone_mat())

	# 충돌(몸체만) — 걸어서 통과 못 하게
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 2.2, 3.2)
	col.shape = shape
	col.position = Vector3(0, 1.4, 0)
	body.add_child(col)
	root.add_child(body)
	return root

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = mat
	parent.add_child(m)

# --- 전봇대 ---
## 마을 서쪽 들판을 남북으로 가로지르는 전봇대 행렬(시골 풍경의 필수 요소).
func _build_power_lines() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.29, 0.26)
	pole_mat.roughness = 1.0
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.05)

	var xline := -40.0
	var tops: Array = []
	var z := 44.0
	while z > -565.0:
		var y := _h(xline, z)
		var pole := Node3D.new()
		pole.position = Vector3(xline, y, z)
		# 기둥
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.14
		cm.height = 8.0
		post.mesh = cm
		post.position = Vector3(0, 4.0, 0)
		post.material_override = pole_mat
		pole.add_child(post)
		# 가로대(완철)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(1.6, 0.09, 0.09)
		arm.mesh = am
		arm.position = Vector3(0, 7.4, 0)
		arm.material_override = pole_mat
		pole.add_child(arm)
		add_child(pole)
		tops.append(Vector3(xline, y + 7.4, z))
		z -= 26.0

	# 전선 3가닥(가로대 양끝 + 중앙 위)
	for i in range(tops.size() - 1):
		for off in [Vector3(-0.7, 0, 0), Vector3(0.7, 0, 0), Vector3(0, 0.35, 0)]:
			_wire(tops[i] + off, tops[i + 1] + off, wire_mat)

func _wire(p1: Vector3, p2: Vector3, mat: Material) -> void:
	var mid := (p1 + p2) * 0.5 - Vector3(0, 0.25, 0)   # 살짝 처짐
	var d := p2 - p1
	var w := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, d.length())
	w.mesh = bm
	w.position = mid
	w.basis = Basis.looking_at(d.normalized(), Vector3.UP)
	w.material_override = mat
	add_child(w)

# --- 나무/바위 산포 ---
## 마을·농지·적 진영을 피해서 들판에 자연물을 뿌린다.
func _blocked(x: float, z: float) -> bool:
	if x > -48 and x < 48 and z > -58 and z < 48:
		return true   # 플레이어 마을 + 농지 + 고용소
	if x > 10 and x < 110 and z > -590 and z < -462:
		return true   # 적 진영
	return false

func _scatter_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260707

	# 위치 수집 → 소나무/활엽수 절반씩
	var pines: Array = []
	var oaks: Array = []
	var attempts := 0
	while pines.size() + oaks.size() < TREE_COUNT and attempts < 6000:
		attempts += 1
		var x := rng.randf_range(-280.0, 280.0)
		var z := rng.randf_range(-640.0, 150.0)
		if _blocked(x, z):
			continue
		var item := [Vector3(x, _h(x, z), z), rng.randf() * TAU, rng.randf_range(0.8, 1.5)]
		if rng.randf() < 0.55:
			pines.append(item)
		else:
			oaks.append(item)

	# 줄기(공용 나무껍질 텍스처)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 2.4
	_scatter_mm(trunk, Visuals.bark_mat(), pines + oaks, 1.2)

	# 소나무: 원뿔 2단
	var cone1 := CylinderMesh.new()
	cone1.top_radius = 0.0
	cone1.bottom_radius = 1.6
	cone1.height = 2.6
	_scatter_mm(cone1, _leaf_mat(Color(0.15, 0.32, 0.16)), pines, 3.0)
	var cone2 := CylinderMesh.new()
	cone2.top_radius = 0.0
	cone2.bottom_radius = 1.1
	cone2.height = 2.0
	_scatter_mm(cone2, _leaf_mat(Color(0.19, 0.38, 0.18)), pines, 4.4)

	# 활엽수: 둥근 수관 2덩이
	var ball1 := SphereMesh.new()
	ball1.radius = 1.5
	ball1.height = 2.6
	_scatter_mm(ball1, _leaf_mat(Color(0.22, 0.42, 0.17)), oaks, 3.2)
	var ball2 := SphereMesh.new()
	ball2.radius = 1.0
	ball2.height = 1.8
	_scatter_mm(ball2, _leaf_mat(Color(0.27, 0.48, 0.20)), oaks, 4.2)

	# 바위(돌 텍스처)
	var rocks: Array = []
	attempts = 0
	while rocks.size() < ROCK_COUNT and attempts < 2500:
		attempts += 1
		var x := rng.randf_range(-280.0, 280.0)
		var z := rng.randf_range(-640.0, 150.0)
		if _blocked(x, z):
			continue
		rocks.append([Vector3(x, _h(x, z) + 0.15, z), rng.randf() * TAU, rng.randf_range(0.5, 1.8)])
	var rock := SphereMesh.new()
	rock.radius = 0.8
	rock.height = 1.0   # 납작한 바위
	_scatter_mm(rock, Visuals.rock_mat(), rocks, 0.3)

func _leaf_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

## items: [위치, y회전, 크기] 배열을 MultiMesh 하나로 그린다. y_off는 부위별 높이(크기 배율 적용).
func _scatter_mm(mesh: Mesh, mat: Material, items: Array, y_off: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		var pos: Vector3 = items[i][0]
		var rot: float = items[i][1]
		var s: float = items[i][2]
		var tb := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(tb, pos + Vector3(0, y_off * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)

# --- 잔디 ---
## 플레이어 활동 반경의 들판에 잔디 수만 그루. 십자 배치 2겹 + 바람 셰이더.
func _scatter_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 977

	var items: Array = []   # [Transform3D 기본, 색]
	var attempts := 0
	while items.size() < GRASS_COUNT and attempts < GRASS_COUNT * 3:
		attempts += 1
		var x := rng.randf_range(-240.0, 240.0)
		var z := rng.randf_range(-300.0, 140.0)
		if _blocked(x, z):
			continue
		var s := rng.randf_range(0.7, 1.4)
		var rot := rng.randf() * TAU
		var g := rng.randf_range(0.85, 1.15)
		var col := Color(0.28 * g, 0.44 * g, 0.18 * g)
		items.append([Vector3(x, _h(x, z), z), rot, s, col])

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.8)
	for layer in range(2):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = items.size()
		var extra_rot := PI * 0.5 * float(layer)   # 두 겹을 십자로
		for i in range(items.size()):
			var pos: Vector3 = items[i][0]
			var rot: float = items[i][1]
			var s: float = items[i][2]
			var tb := Basis(Vector3.UP, rot + extra_rot).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(tb, pos + Vector3(0, 0.32 * s, 0)))
			mm.set_instance_color(i, items[i][3])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Visuals.sway_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
