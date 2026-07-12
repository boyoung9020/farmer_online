extends Node3D
## 마을 풍경.
## - 공용 연못(농지 북쪽) 주변의 시골집 몇 채 (PBR 텍스처)
## - 들판 전체에 나무 2종/바위 산포 (MultiMesh, 지형 높이 반영)
## - 플레이어 주변 들판에 바람에 흔들리는 잔디 수만 그루

const Visuals := preload("res://scripts/visuals.gd")

const TREE_COUNT := 420
const ROCK_COUNT := 70
const GRASS_COUNT := 30000

var terrain   # terrain.gd — height_at(x, z)

func _ready() -> void:
	_build_houses()
	_build_power_lines()
	_build_roads()
	_build_greenhouses()
	_build_big_tree()
	_build_korean_trees()
	_build_quality_trees()
	_scatter_nature()
	_scatter_grass()

## GLB 잎 카드 재질 보정: 알파컷 + 양면 렌더 (익스포트 과정에서 유실돼도 안전하게).
## 런타임 로드 GLB 텍스처는 밉맵이 없어 이동 시 지글거림 → 밉맵 생성.
func _fix_foliage(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var mat := mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					bm.albedo_texture = _with_mipmaps(bm.albedo_texture)
					bm.normal_texture = _with_mipmaps(bm.normal_texture)
					bm.roughness_texture = _with_mipmaps(bm.roughness_texture)
					if String(bm.resource_name).begins_with("leafcard"):
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						bm.alpha_scissor_threshold = 0.4
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
						# MSAA와 함께 잎 가장자리를 부드럽게(알파-투-커버리지)
						bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	for c in n.get_children():
		_fix_foliage(c)

## 밉맵 없는 ImageTexture에 밉맵을 만들어 되돌려준다(중복 호출 안전).
func _with_mipmaps(tex: Texture2D) -> Texture2D:
	if tex is ImageTexture:
		var img: Image = (tex as ImageTexture).get_image()
		if img != null and not img.has_mipmaps():
			if img.is_compressed():
				return tex
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return tex

# --- 고품질 나무(Blender 제작): 마을·길가 주요 자리만 배치 — 원경 스캐터는 저폴리 유지(LOD) ---
func _build_quality_trees() -> void:
	var spots := [
		["pine", Vector3(-37, 0, -28), 0.7, 1.15],   # 간선도로 서쪽 가로수(전봇대와 도로 사이)
		["pine", Vector3(-37, 0, -6), 2.3, 1.0],
		["pine", Vector3(-37, 0, 12), 4.0, 1.25],
		["pine", Vector3(-8.5, 0, -50.5), 1.1, 1.1],  # 집 뒤 소나무들
		["pine", Vector3(7.5, 0, -49.5), 3.3, 0.95],
		["pine", Vector3(21.5, 0, -48), 5.1, 1.2],
		["pine", Vector3(24.5, 0, -34.2), 0.3, 1.0],  # 마을길 동쪽 끝
		# 농로변은 가벼운 잎카드 나무(76만 폴리 실사 나무는 정자나무 1그루 전용)
		["zelkova", Vector3(-14, 0, 38.5), 1.8, 1.0],
		["zelkova", Vector3(23.5, 0, 38.6), 4.6, 0.9],   # 농기계 주차열과 안 겹치게
		["pine", Vector3(-37, 0, 30), 2.9, 1.0],
	]
	for s in spots:
		var t := Visuals.load_glb("res://assets/models/%s.glb" % s[0])
		if t == null:
			continue
		_fix_foliage(t)
		t.position = s[1]
		t.rotation.y = s[2]
		t.scale = Vector3.ONE * (s[3] as float)
		add_child(t)

# --- 한국적인 나무들: 버드나무(저수지 물가), 감나무(집 마당) ---
func _build_korean_trees() -> void:
	# 버드나무 — 저수지 제방 사면에 뿌리내려 물가로 가지가 늘어진다
	for s in [[Vector3(-57.5, 0.6, -52.5), 0.4], [Vector3(-78.5, 0.6, -42.0), 2.1]]:
		var w: Node3D = Visuals.load_glb("res://assets/models/willow.glb")
		if w == null:
			w = _willow()
		else:
			_fix_foliage(w)
		w.position = s[0]
		w.rotation.y = s[1]
		add_child(w)
	# 감나무 — 집 마당마다 한 그루씩(주황 감이 달린)
	for s in [[Vector3(-17.5, 0, -39.0), 0.0], [Vector3(3.5, 0, -42.5), 1.2],
			[Vector3(16.5, 0, -40.0), 2.4], [Vector3(-22.5, 0, -33.8), 0.7]]:
		var p := _persimmon()
		p.position = s[0]
		p.rotation.y = s[1]
		add_child(p)

## 버드나무: 기울어진 줄기 + 둥근 수관 + 물가로 늘어지는 가지들.
func _willow() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.3
	tm.height = 3.2
	trunk.mesh = tm
	trunk.position = Vector3(0, 1.5, 0)
	trunk.rotation.z = 0.18   # 물 쪽으로 기울어짐
	trunk.material_override = Visuals.bark_mat()
	root.add_child(trunk)

	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.36, 0.52, 0.24)   # 버들잎 연둣빛
	leaf.roughness = 1.0
	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.9
	cm.height = 2.6
	canopy.mesh = cm
	canopy.position = Vector3(0.5, 3.6, 0)
	canopy.material_override = leaf
	root.add_child(canopy)

	# 늘어진 가지(치렁치렁)
	for i in range(12):
		var ang := TAU * float(i) / 12.0
		var strand := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var slen := 1.4 + 0.6 * sin(float(i) * 2.9)
		sm.size = Vector3(0.09, slen, 0.09)
		strand.mesh = sm
		strand.position = Vector3(0.5 + cos(ang) * 1.7, 3.4 - slen * 0.5, sin(ang) * 1.7)
		strand.material_override = leaf
		root.add_child(strand)
	return root

## 감나무: 아담한 키 + 둥근 수관 + 주황 감.
func _persimmon() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.12
	tm.bottom_radius = 0.2
	tm.height = 1.9
	trunk.mesh = tm
	trunk.position = Vector3(0, 0.95, 0)
	trunk.material_override = Visuals.bark_mat()
	root.add_child(trunk)

	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.20, 0.36, 0.15)   # 짙은 감잎
	leaf.roughness = 1.0
	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.5
	cm.height = 2.2
	canopy.mesh = cm
	canopy.position = Vector3(0, 2.7, 0)
	canopy.material_override = leaf
	root.add_child(canopy)

	var fruit := StandardMaterial3D.new()
	fruit.albedo_color = Color(0.95, 0.5, 0.1)    # 주황 감
	fruit.roughness = 0.5
	for i in range(9):
		var ang := TAU * float(i) / 9.0
		var f := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.11
		fm.height = 0.2
		f.mesh = fm
		f.position = Vector3(cos(ang) * 1.25, 2.4 + 0.5 * sin(float(i) * 2.1), sin(ang) * 1.25)
		f.material_override = fruit
		root.add_child(f)
	return root

# --- 농로 (콘크리트 포장길: 마을~농지~고용소, 경운기/트랙터 통행로) ---
# 흙길 셰이더: 옅은 마른 흙 + 가장자리가 불규칙하게 풀로 스며드는 페이드(직각 경계 제거)
const DIRT_ROAD_SHADER := "
shader_type spatial;
uniform sampler2D albedo_tex: source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint: source_color = vec3(1.0, 0.94, 0.82);
uniform float tex_scale = 3.4;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 alb = texture(albedo_tex, wpos.xz / tex_scale).rgb;
	float d = min(UV.y, 1.0 - UV.y);   // 폭 방향 가장자리 거리
	float wob = sin(UV.x * 90.0) * 0.03 + sin(UV.x * 33.0 + 1.7) * 0.05;
	ALPHA = smoothstep(0.01 + wob, 0.34 + wob, d);   // 넓은 그라데이션 — 중심만 진하고 서서히 풀로
	ALBEDO = alb * tint;
	ROUGHNESS = 1.0;
}
"
static var _dirt_road_mat: ShaderMaterial

func _build_roads() -> void:
	# [세로] 남북 간선(농지 서쪽 가장자리) / [가로] 마을 안길, 남쪽 농로(농기계 주차장 앞)
	# 폭은 넓은 가장자리 그라데이션을 감안해 여유 있게
	_dirt_road(Vector3(-32.8, 0.045, -3.0), 4.4, 92.0, false)
	_dirt_road(Vector3(-7.0, 0.045, -38.0), 3.6, 52.0, true)
	_dirt_road(Vector3(-5.0, 0.045, 34.0), 3.9, 56.0, true)

	_build_street_lamps()

## 흙길 한 판 — 가장자리가 풀에 자연스럽게 섞이는 평면.
func _dirt_road(pos: Vector3, width: float, length: float, horizontal: bool) -> void:
	if _dirt_road_mat == null:
		var sh := Shader.new()
		sh.code = DIRT_ROAD_SHADER
		_dirt_road_mat = ShaderMaterial.new()
		_dirt_road_mat.shader = sh
		_dirt_road_mat.set_shader_parameter("albedo_tex", Visuals.tex("dry_mud_field_001_diff.jpg"))
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(length, width)
	m.mesh = pm
	m.position = pos
	if not horizontal:
		m.rotation.y = PI * 0.5
	m.material_override = _dirt_road_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)

# --- 가로등 (도로변, 밤에 점등 — day_cycle이 그룹으로 제어) ---
func _build_street_lamps() -> void:
	# 남북 간선 동측
	for i in range(6):
		_street_lamp(Vector3(-30.9, 0, -42.0 + i * 16.0), PI * 0.5)
	# 남쪽 농로 북측
	for i in range(4):
		_street_lamp(Vector3(-26.0 + i * 16.0, 0, 32.3), 0.0)
	# 마을 안길 남측
	for i in range(3):
		_street_lamp(Vector3(-26.0 + i * 16.0, 0, -36.3), PI)

func _street_lamp(pos: Vector3, rot: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.23, 0.25)
	dark.metallic = 0.5
	dark.roughness = 0.5

	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.055
	pm.bottom_radius = 0.08
	pm.height = 4.6
	pole.mesh = pm
	pole.position = Vector3(0, 2.3, 0)
	pole.material_override = dark
	root.add_child(pole)

	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.07, 0.07, 1.2)
	arm.mesh = am
	arm.position = Vector3(0, 4.55, -0.55)
	arm.material_override = dark
	root.add_child(arm)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.24, 0.12, 0.55)
	head.mesh = hm
	head.position = Vector3(0, 4.5, -1.1)
	head.material_override = dark
	root.add_child(head)

	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.18, 0.05, 0.45)
	glass.mesh = gm
	glass.position = Vector3(0, 4.43, -1.1)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.9, 0.6)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.85, 0.5)
	gmat.emission_energy_multiplier = 0.4
	glass.material_override = gmat
	root.add_child(glass)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 4.2, -1.1)
	light.light_color = Color(1.0, 0.85, 0.55)
	light.omni_range = 14.0
	light.light_energy = 0.0   # 밤에 day_cycle이 켠다
	root.add_child(light)

	root.add_to_group("street_lamps")
	root.set_meta("light", light)
	root.set_meta("glass", gmat)
	add_child(root)

# --- 비닐하우스 + 모판 (한국 농촌 시그니처) ---
func _build_greenhouses() -> void:
	for s in [[Vector3(27, 0, -40), 0.06], [Vector3(33.5, 0, -46), 0.1]]:
		var gh := Visuals.load_glb("res://assets/models/greenhouse.glb")
		if gh == null:
			continue
		gh.position = s[0]
		gh.rotation.y = PI + s[1]
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.6, 2.2, 9.0)
		col.shape = shape
		col.position = Vector3(0, 1.1, 0)
		body.add_child(col)
		gh.add_child(body)
		add_child(gh)

	# 모판 더미 — 비닐하우스 앞마당(육묘장)
	for s in [[Vector3(29.6, 0, -42.6), 0.4], [Vector3(31.0, 0, -43.4), -0.7], [Vector3(28.3, 0, -43.1), 1.2]]:
		var tray := Visuals.load_glb("res://assets/models/seedtray.glb")
		if tray == null:
			continue
		tray.position = s[0]
		tray.rotation.y = s[1]
		add_child(tray)

# --- 정자나무 (마을 큰 나무) ---
func _build_big_tree() -> void:
	var root := Node3D.new()
	root.position = Vector3(-20, 0, -34.5)   # 마을 서쪽(집 지붕·저수지에 안 겹치게)
	# 마을 정자나무 — 실사 포토스캔 나무(Poly Haven island_tree_02), 폴백은 제작 느티나무
	var tree := Visuals.load_glb("res://assets/models/real_tree_a.glb")
	if tree == null:
		tree = Visuals.load_glb("res://assets/models/zelkova.glb")
		if tree != null:
			tree.scale = Vector3(1.3, 1.3, 1.3)
	if tree != null:
		_fix_foliage(tree)
		root.add_child(tree)
	# 나무 밑동 평상(마을 쉼터)
	var bench := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.35, 2.0)
	bench.mesh = bm
	bench.position = Vector3(2.6, 0.18, 1.4)
	bench.material_override = Visuals.wood_mat()
	root.add_child(bench)
	add_child(root)

func _h(x: float, z: float) -> float:
	# 실제 렌더 지형 표면에 스냅(하이트맵 업샘플과 수식값의 오차 방지)
	return terrain.surface_height(x, z) if terrain != null else 0.0

# --- 집 ---
func _build_houses() -> void:
	# 연못(월드 약 (0, -24)) 북쪽·서쪽으로 옹기종기 — 기와집 2채 + 초가집 2채
	var spots := [
		[Vector3(-14, 0, -42), 0.35, true],
		[Vector3(0, 0, -46), 0.0, false],
		[Vector3(13, 0, -43), -0.4, true],
		[Vector3(-26, 0, -33), 0.9, false],
	]
	for s in spots:
		var h: Node3D
		if s[2]:
			h = Visuals.load_glb("res://assets/models/choga.glb")
			if h == null:
				h = _house()
			else:
				h.rotation.y = PI   # Blender 전방 보정
				var body := StaticBody3D.new()
				var col := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(4.0, 2.2, 3.1)
				col.shape = shape
				col.position = Vector3(0, 1.2, 0)
				body.add_child(col)
				h.add_child(body)
		else:
			h = _house()
		h.position = s[0]
		h.rotation.y += s[1]
		add_child(h)

	_build_village_guardians()

## 마을 입구 수호: 장승 한 쌍(천하대장군·지하여장군) + 솟대.
## 마을과 경작지 사이 길목에 세운다.
func _build_village_guardians() -> void:
	# 간선도로에서 마을길로 들어오는 길목 양옆(저수지 제방과 겹치지 않게)
	var spots := [
		["res://assets/models/jangseung.glb", Vector3(-29.5, 0, -36.3), -1.45, 1.0],
		["res://assets/models/jangseung.glb", Vector3(-29.5, 0, -39.7), -1.7, 0.88],  # 지하여장군은 조금 작게
		["res://assets/models/sotdae.glb", Vector3(-28.0, 0, -35.2), 0.6, 1.0],
	]
	for s in spots:
		var m := Visuals.load_glb(s[0])
		if m == null:
			continue
		m.position = s[1]
		m.rotation.y = PI + s[2]   # 남쪽(경작지/방문자 방향)을 바라보게
		m.scale = Vector3.ONE * s[3]
		add_child(m)

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
	bm.size = Vector3(0.05, 0.05, d.length())
	w.mesh = bm
	w.position = mid
	w.basis = Basis.looking_at(d.normalized(), Vector3.UP)
	w.material_override = mat
	# 가는 전선의 그림자는 섀도맵 해상도 아래라 지글거림만 만든다
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)

# --- 나무/바위 산포 ---
## 마을·농지·적 진영을 피해서 들판에 자연물을 뿌린다.
func _blocked(x: float, z: float) -> bool:
	if x > -48 and x < 48 and z > -58 and z < 48:
		return true   # 플레이어 마을 + 농지 + 고용소
	if x > -92 and x < -44 and z > -64 and z < -28:
		return true   # 마을 서쪽 저수지 터
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

	# 마을 뒷산 숲(배산임수) — 능선에 빽빽하게
	var ridge_trees := 0
	attempts = 0
	while ridge_trees < 300 and attempts < 5000:
		attempts += 1
		var x := rng.randf_range(-190.0, 190.0)
		var z := rng.randf_range(-175.0, -62.0)
		if _blocked(x, z):
			continue
		var y := _h(x, z)
		if y < 2.0:
			continue   # 능선 위쪽에만(평지 제외)
		ridge_trees += 1
		var item := [Vector3(x, y, z), rng.randf() * TAU, rng.randf_range(0.9, 1.6)]
		if rng.randf() < 0.7:
			pines.append(item)
		else:
			oaks.append(item)

	# 원경 산맥 사면 숲 — 쇼케이스처럼 산허리를 나무로 덮는다(중턱만, 꼭대기는 암벽)
	var mtn := 0
	attempts = 0
	while mtn < 900 and attempts < 9000:
		attempts += 1
		var x := rng.randf_range(-780.0, 780.0)
		var z := rng.randf_range(-1000.0, 560.0)
		var y := _h(x, z)
		if y < 20.0 or y > 90.0:
			continue
		mtn += 1
		var item := [Vector3(x, y, z), rng.randf() * TAU, rng.randf_range(1.6, 2.8)]
		if rng.randf() < 0.8:
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
	_scatter_mm(cone1, _leaf_mat(Color(0.24, 0.40, 0.20)), pines, 3.0)
	var cone2 := CylinderMesh.new()
	cone2.top_radius = 0.0
	cone2.bottom_radius = 1.1
	cone2.height = 2.0
	_scatter_mm(cone2, _leaf_mat(Color(0.29, 0.46, 0.23)), pines, 4.4)

	# 활엽수: 둥근 수관 2덩이
	var ball1 := SphereMesh.new()
	ball1.radius = 1.5
	ball1.height = 2.6
	_scatter_mm(ball1, _leaf_mat(Color(0.33, 0.49, 0.22)), oaks, 3.2)
	var ball2 := SphereMesh.new()
	ball2.radius = 1.0
	ball2.height = 1.8
	_scatter_mm(ball2, _leaf_mat(Color(0.39, 0.55, 0.26)), oaks, 4.2)

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
## Terrain3D 인스턴서로 풀포기 카드를 심는다(지형 시스템이 청크·컬링 관리).
## 색은 terrain.gd의 풀포기 메시 에셋(지면 텍스처 톤과 매칭) 2종을 번갈아 쓴다.
func _scatter_grass() -> void:
	if terrain == null or terrain.terrain == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 977

	var xforms_a: Array[Transform3D] = []
	var xforms_b: Array[Transform3D] = []
	var made := 0
	var attempts := 0
	while made < GRASS_COUNT and attempts < GRASS_COUNT * 3:
		attempts += 1
		var x := rng.randf_range(-240.0, 240.0)
		var z := rng.randf_range(-300.0, 140.0)
		if _blocked(x, z):
			continue
		made += 1
		var s := rng.randf_range(0.7, 1.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		var t := Transform3D(b, Vector3(x, terrain.surface_height(x, z), z))
		if made % 2 == 0:
			xforms_a.push_back(t)
		else:
			xforms_b.push_back(t)
	terrain.terrain.instancer.add_transforms(0, xforms_a)
	terrain.terrain.instancer.add_transforms(1, xforms_b)
