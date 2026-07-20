extends Node3D
## 독립 Terrain3D 월드 — 보구곶 실사 레퍼런스(bogu_05/08/11) 기반 리얼리티 테스트 씬.
## 본 게임(Main.tscn)과 완전 분리. 실행: Godot --path . scenes/TerrainWorld.tscn
## - 중앙: 평탄한 논 분지(연두) / 분지 가장자리: 완만한 계단식 사면
## - 사방: 소나무 언덕(자동 풀/바위 셰이더) / 원경: 급경사 산맥
## - 분지를 가로지르는 전신주 행렬(bogu_08) + 자유비행 카메라(WASD+마우스)

const Visuals := preload("res://scripts/visuals.gd")

const MAP_HALF := 1024.0
const BAKE_RES := 512
const BASIN_R := 140.0        # 논 분지 반경(평지)
const TERRACE_R := 300.0      # 계단식 사면 바깥 반경
const TERRACE_STEP := 1.2     # 계단 한 단 높이(m)
const HILL_AMP := 55.0        # 언덕 최대 높이
const MTN_START := 620.0      # 원경 산맥 시작 거리
const PINE_COUNT := 40000   # 언덕 전체를 숲으로 — 저폴리(6각 원뿔) MultiMesh라 감당 가능

var _noise: FastNoiseLite
var terrain

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 20260719
	_noise.frequency = 0.004
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.1

	_setup_environment()
	_setup_light()
	_build_terrain()
	_scatter_pines()
	_build_power_line()
	_spawn_camera()

## ── 지형 수식 ────────────────────────────────────────────────────────
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	# 언덕(분지 밖에서만 서서히)
	var hill_f := smoothstep(BASIN_R, TERRACE_R + 160.0, d)
	var h := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * HILL_AMP * hill_f
	# 계단식 사면 — 분지 가장자리 논둑 단차(bogu_05 계곡 논)
	if d > BASIN_R and d < TERRACE_R:
		var t := (d - BASIN_R) / (TERRACE_R - BASIN_R)
		var terr := t * t * 10.0
		h += floor(terr / TERRACE_STEP) * TERRACE_STEP
	elif d >= TERRACE_R:
		h += 10.0
	# 원경 산맥 — 날카로운 융기(급경사는 오토셰이더가 암벽 처리)
	var mfar := clampf((d - MTN_START) / 280.0, 0.0, 1.0)
	if mfar > 0.0:
		var mn := 1.0 - absf(_noise.get_noise_2d(x * 0.7 + 555.0, z * 0.7))
		h += mfar * mn * mn * 170.0
	return h

func surface_height(x: float, z: float) -> float:
	if terrain != null:
		var h: float = terrain.data.get_height(Vector3(x, 0.0, z))
		if not is_nan(h):
			return h
	return height_at(x, z)

## ── Terrain3D 구성 (terrain.gd 패턴 재사용) ─────────────────────────
func _build_terrain() -> void:
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain, true)

	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_base_texture", 1)     # 급경사 = 바위
	terrain.material.set_shader_param("auto_overlay_texture", 0)  # 평지 = 풀
	terrain.material.set_shader_param("auto_slope", 2.0)
	terrain.material.set_shader_param("blend_sharpness", 0.92)

	terrain.assets = Terrain3DAssets.new()
	var grass_ta = _texture_asset("풀", "leafy_grass", 0.16)
	grass_ta.albedo_color = Color(0.80, 1.0, 0.66)   # 여름 벼 연두톤(bogu_08)
	terrain.assets.set_texture(0, grass_ta)
	terrain.assets.set_texture(1, _texture_asset("바위", "gray_rocks", 0.10))
	terrain.assets.set_texture(2, _texture_asset("흙", "dirt", 0.20))
	terrain.material.set_shader_param("macro_variation1", Color(0.92, 0.97, 0.86))
	terrain.material.set_shader_param("macro_variation2", Color(0.78, 0.88, 0.70))

	var img := Image.create_empty(BAKE_RES, BAKE_RES, false, Image.FORMAT_RF)
	var step := MAP_HALF * 2.0 / float(BAKE_RES)
	for py in range(BAKE_RES):
		var z := -MAP_HALF + (py + 0.5) * step
		for px in range(BAKE_RES):
			var x := -MAP_HALF + (px + 0.5) * step
			img.set_pixel(px, py, Color(height_at(x, z), 0.0, 0.0, 1.0))
	img.resize(int(MAP_HALF) * 2, int(MAP_HALF) * 2, Image.INTERPOLATE_CUBIC)
	terrain.region_size = 1024
	terrain.data.import_images([img, null, null], Vector3(-MAP_HALF, 0, -MAP_HALF), 0.0, 1.0)

	# 시각 지형과 동일한 하이트맵으로 정적 충돌(향후 도보 탐험 대비)
	terrain.collision.mode = Terrain3DCollision.DISABLED
	var hshape := HeightMapShape3D.new()
	hshape.map_width = img.get_width()
	hshape.map_depth = img.get_height()
	hshape.map_data = img.get_data().to_float32_array()
	var hbody := StaticBody3D.new()
	var hcol := CollisionShape3D.new()
	hcol.shape = hshape
	hbody.add_child(hcol)
	add_child(hbody)

func _texture_asset(asset_name: String, slug: String, uv_scale: float):
	var alb: Image = Visuals.tex(slug + "_diff.jpg").get_image()
	alb.decompress()
	alb.convert(Image.FORMAT_RGBA8)
	alb.resize(1024, 1024)
	alb.generate_mipmaps()
	var nrm: Image = Visuals.tex(slug + "_nor_gl.jpg").get_image()
	nrm.decompress()
	nrm.convert(Image.FORMAT_RGBA8)
	nrm.resize(1024, 1024)
	nrm.generate_mipmaps()
	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = ImageTexture.create_from_image(alb)
	ta.normal_texture = ImageTexture.create_from_image(nrm)
	ta.uv_scale = uv_scale
	ta.detiling_rotation = 0.12
	return ta

## ── 환경/조명 (실사 여름 오후) ──────────────────────────────────────
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.53, 0.82)
	sm.sky_horizon_color = Color(0.80, 0.87, 0.90)
	sm.ground_horizon_color = Color(0.72, 0.78, 0.76)
	sm.ground_bottom_color = Color(0.22, 0.28, 0.22)
	sm.sun_angle_max = 25.0
	# 뭉게구름(노이즈 절차 생성 — main.gd 와 동일 기법)
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.006
	cn.fractal_octaves = 5
	cn.fractal_gain = 0.55
	cn.seed = 20260718
	var ct := NoiseTexture2D.new()
	ct.noise = cn
	ct.seamless = true
	ct.width = 1024
	ct.height = 512
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.52, Color(1, 1, 1, 0.0))
	ramp.add_point(0.62, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.95))
	ct.color_ramp = ramp
	sm.sky_cover = ct
	sm.sky_cover_modulate = Color(1, 1, 1, 1)
	sky.sky_material = sm
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_max_distance = 500.0
	# 원경이 뿌옇게 가라앉는 공기 원근(실사 산맥 겹 느낌)
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.88, 0.93)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.12
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_albedo = Color(0.9, 0.93, 0.97)
	env.volumetric_fog_length = 300.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.03
	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-46), deg_to_rad(-35), 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.87)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	sun.shadow_blur = 1.5
	add_child(sun)

## ── 소나무 스캐터 ───────────────────────────────────────────────────
## 근중경(<520m): pine.glb(Blender 제작, 껍질 PBR+잎카드) MultiMesh — 진짜 나무
## 원경(>=520m): 저폴리 원뿔 — 실루엣만 필요한 거리
const QUALITY_DIST := 520.0
const QUALITY_CAP := 12000

## pine.glb 의 (메시, 로컬변환) 목록 수집 + 잎카드 재질 보정(알파컷/양면/밉맵).
func _collect_glb_meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			if mesh != null:
				for i in range(mesh.get_surface_count()):
					var mat := mesh.surface_get_material(i)
					if mat is BaseMaterial3D:
						var bm := mat as BaseMaterial3D
						if bm.albedo_texture is ImageTexture:
							var img: Image = (bm.albedo_texture as ImageTexture).get_image()
							if img != null and not img.has_mipmaps() and not img.is_compressed():
								img.generate_mipmaps()
								bm.albedo_texture = ImageTexture.create_from_image(img)
						if String(bm.resource_name).begins_with("leafcard"):
							bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
							bm.alpha_scissor_threshold = 0.4
							bm.cull_mode = BaseMaterial3D.CULL_DISABLED
							bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				out.append([mesh, xf])
		for c in n.get_children():
			stack.append([c, xf])
	return out

func _scatter_pines() -> void:
	# 저폴리 소나무: 줄기 + 원뿔 3단 (원경용)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 5   # 4만 그루 대비 저폴리
	trunk_mesh.rings = 1
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.28, 0.20)
	bark.roughness = 1.0
	trunk_mesh.material = bark
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.5
	cone.height = 2.2
	cone.radial_segments = 6
	cone.rings = 1
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.16, 0.30, 0.16)   # 짙은 청록 소나무(실사 숲 실루엣)
	leaf.roughness = 1.0
	cone.material = leaf

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260719
	var near_spots: Array = []   # 진짜 나무(pine.glb)
	var far_spots: Array = []    # 원경 실루엣(저폴리)
	var attempts := 0
	while near_spots.size() + far_spots.size() < PINE_COUNT and attempts < PINE_COUNT * 10:
		attempts += 1
		var x := rng.randf_range(-900.0, 900.0)
		var z := rng.randf_range(-900.0, 900.0)
		var h := height_at(x, z)
		if h < 6.0 or h > 130.0:
			continue   # 분지(논)와 암벽 봉우리는 제외 — 언덕 사면만 숲
		var spot := [Vector3(x, h, z), rng.randf() * TAU, rng.randf_range(0.9, 1.9)]
		if Vector2(x, z).length() < QUALITY_DIST and near_spots.size() < QUALITY_CAP:
			near_spots.append(spot)
		else:
			far_spots.append(spot)

	# [근중경] pine.glb 를 MultiMesh 로 — 메시/재질 그대로, 수천 그루도 드로우콜 몇 개
	var proto = Visuals.load_glb("res://assets/models/pine.glb")
	if proto != null:
		for entry in _collect_glb_meshes(proto):
			var src_mesh: Mesh = entry[0]
			var local_xf: Transform3D = entry[1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src_mesh
			mm.instance_count = near_spots.size()
			for i in range(near_spots.size()):
				var s: Array = near_spots[i]
				var sc: float = s[2]
				var world := Transform3D(Basis(Vector3.UP, s[1]).scaled(Vector3(sc, sc, sc)), s[0])
				mm.set_instance_transform(i, world * local_xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
		proto.queue_free()

	# [원경] 저폴리 원뿔 실루엣
	for part in [[trunk_mesh, 1.2], [cone, 3.2], [cone, 4.6], [cone, 5.8]]:
		var part_y: float = part[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = far_spots.size()
		for i in range(far_spots.size()):
			var s: Array = far_spots[i]
			var sc: float = s[2]
			var shrink: float = 1.0 if part_y < 2.0 else (1.0 - (part_y - 3.2) * 0.14)
			var b := Basis(Vector3.UP, s[1]).scaled(Vector3(sc * shrink, sc, sc * shrink))
			mm.set_instance_transform(i, Transform3D(b, s[0] + Vector3(0, part_y * sc, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 원경은 그림자 불필요
		add_child(mmi)

	# 근경 히어로 소나무(Blender 제작 glb) — 스폰 주변 몇 그루
	for s in [[Vector3(8, 0, -14), 0.7], [Vector3(-16, 0, 6), 2.1], [Vector3(20, 0, 16), 4.2]]:
		var p = Visuals.load_glb("res://assets/models/pine.glb")
		if p == null:
			continue
		p.position = Vector3(s[0].x, surface_height(s[0].x, s[0].z), s[0].z)
		p.rotation.y = s[1]
		add_child(p)

## ── 분지를 가로지르는 전신주 행렬 (bogu_08) ─────────────────────────
func _build_power_line() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.29, 0.26)
	pole_mat.roughness = 1.0
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	var tops: Array = []
	var x := -260.0
	while x <= 260.0:
		var y := surface_height(x, 24.0)
		var pole := Node3D.new()
		pole.position = Vector3(x, y, 24.0)
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.14
		cm.height = 8.0
		post.mesh = cm
		post.position = Vector3(0, 4.0, 0)
		post.material_override = pole_mat
		pole.add_child(post)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.09, 0.09, 1.6)
		arm.mesh = am
		arm.position = Vector3(0, 7.4, 0)
		arm.material_override = pole_mat
		pole.add_child(arm)
		add_child(pole)
		tops.append(Vector3(x, y + 7.4, 24.0))
		x += 26.0
	for i in range(tops.size() - 1):
		for off in [Vector3(0, 0, -0.7), Vector3(0, 0, 0.7), Vector3(0, 0.35, 0)]:
			var p1: Vector3 = tops[i] + off
			var p2: Vector3 = tops[i + 1] + off
			var w := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.05, (p2 - p1).length())
			w.mesh = bm
			w.position = (p1 + p2) * 0.5 - Vector3(0, 0.25, 0)
			w.basis = Basis.looking_at((p2 - p1).normalized(), Vector3.UP)
			w.material_override = wire_mat
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(w)

## ── 자유비행 카메라 ─────────────────────────────────────────────────
func _spawn_camera() -> void:
	var cam := Camera3D.new()
	cam.set_script(preload("res://scripts/fly_camera.gd"))
	cam.position = Vector3(0, 4.0, 60.0)
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
