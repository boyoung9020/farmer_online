extends Node3D
## 루트 씬. 환경/조명/지면/필지/농지/농부/트랙터/노동자/HUD/미니맵 구성(러프 단계).

const USE_PARCELS := false   # true면 지적도 필지 로드(나중에 다시 켤 것). false면 평지만.

const ParcelLoaderScript := preload("res://scripts/parcel_loader.gd")
const FarmFieldScript := preload("res://scripts/farm_field.gd")
const FarmerScript := preload("res://scripts/farmer.gd")
const TractorScript := preload("res://scripts/tractor.gd")
const TransplanterScript := preload("res://scripts/transplanter.gd")
const CombineScript := preload("res://scripts/combine.gd")
const WorkerManagerScript := preload("res://scripts/worker_manager.gd")
const EnemyManagerScript := preload("res://scripts/enemy_manager.gd")
const ShopScript := preload("res://scripts/shop.gd")
const ShopUiScript := preload("res://scripts/shop_ui.gd")
const HudScript := preload("res://scripts/hud.gd")
const MinimapScript := preload("res://scripts/minimap.gd")
const VillageScript := preload("res://scripts/village.gd")
const TerrainScript := preload("res://scripts/terrain.gd")
const BirdManagerScript := preload("res://scripts/bird_manager.gd")
const DayCycleScript := preload("res://scripts/day_cycle.gd")
const Visuals := preload("res://scripts/visuals.gd")

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D

func _ready() -> void:
	# 얇은 지오메트리(전선·잎카드·논둑 모서리)가 이동 중 지글거리지 않도록 MSAA
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_setup_environment()
	_setup_light()
	_setup_base_ground()
	if USE_PARCELS:
		_setup_parcels()

	var terrain = TerrainScript.new()
	add_child(terrain)

	var field = FarmFieldScript.new()
	field.position.y = -1.6   # 경작지 침하(terrain.gd FARM_DEPTH와 동일) — 논은 마을보다 낮다
	add_child(field)

	var village = VillageScript.new()
	village.terrain = terrain
	add_child(village)

	# 농부/농기계/상점은 침하된 논이 아니라 남쪽 농로변 원지반에 선다
	var farmer = FarmerScript.new()
	farmer.position = Vector3(0, 1.5, 38.5)
	add_child(farmer)

	var tractor = TractorScript.new()
	tractor.position = Vector3(5, 1.5, 38.5)  # 농부 옆에 주차
	tractor.field = field
	add_child(tractor)

	var transplanter = TransplanterScript.new()
	transplanter.position = Vector3(10, 1.5, 38.5)  # 트랙터 옆에 주차
	transplanter.field = field
	add_child(transplanter)

	var combine = CombineScript.new()
	combine.position = Vector3(15.5, 1.5, 38.5)  # 이앙기 옆에 주차
	combine.field = field
	add_child(combine)

	farmer.tractor = tractor
	farmer.vehicles = [tractor, transplanter, combine]
	tractor.farmer = farmer
	transplanter.farmer = farmer
	combine.farmer = farmer

	var hud = HudScript.new()
	add_child(hud)
	farmer.hud = hud
	tractor.hud = hud
	transplanter.hud = hud
	combine.hud = hud

	var wm = WorkerManagerScript.new()
	wm.field = field
	wm.hud = hud
	add_child(wm)

	# 고용소(상점) + 상점 UI
	var shop = ShopScript.new()
	shop.position = Vector3(-8, 0, 39)   # 남쪽 농로 건너편(원지반)
	add_child(shop)

	var shop_ui = ShopUiScript.new()
	shop_ui.wm = wm
	shop_ui.farmer = farmer
	add_child(shop_ui)

	farmer.shop = shop
	farmer.shop_ui = shop_ui
	farmer.field = field
	farmer.set_active(true)  # 참조 연결 후 상태표시 갱신

	# 적 AI
	var enemy = EnemyManagerScript.new()
	enemy.hud = hud
	add_child(enemy)

	# 참새 떼(플레이어 논의 익은 벼를 노림 — 허수아비로 방어)
	# 디자인 검토(DEBUG_START_MATURE) 중엔 끈다 — 벼를 먹어치워 밭이 흐트러진다
	if not FarmFieldScript.DEBUG_START_MATURE:
		var birds = BirdManagerScript.new()
		birds.field = field
		birds.hud = hud
		add_child(birds)

	var mm = MinimapScript.new()
	add_child(mm)

	# 하루 사이클(새벽~밤)
	var dc = DayCycleScript.new()
	dc.sun = _sun
	dc.env = _env
	dc.sky = _sky_mat
	dc.hud = hud
	add_child(dc)

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	_sky_mat = sm
	sm.sky_top_color = Color(0.32, 0.55, 0.83)
	sm.sky_horizon_color = Color(0.78, 0.86, 0.90)
	sm.ground_horizon_color = Color(0.72, 0.78, 0.76)
	sm.ground_bottom_color = Color(0.22, 0.28, 0.22)
	sm.sun_angle_max = 25.0

	# 구름 커버 — 현장 실사(bogu 전 장에 구름 가득)의 여름 뭉게/양떼구름 느낌.
	# 노이즈 텍스처를 sky_cover 로 써서 텍스처 에셋 없이 절차 생성.
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cloud_noise.frequency = 0.006
	cloud_noise.fractal_octaves = 5
	cloud_noise.fractal_gain = 0.55
	cloud_noise.seed = 20260718
	var cloud_tex := NoiseTexture2D.new()
	cloud_tex.noise = cloud_noise
	cloud_tex.seamless = true
	cloud_tex.width = 1024
	cloud_tex.height = 512
	# 노이즈 중간값 이상만 구름으로 — 파란 하늘 사이 뭉게구름 덩어리
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.52, Color(1, 1, 1, 0.0))
	ramp.add_point(0.62, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.95))
	cloud_tex.color_ramp = ramp
	sm.sky_cover = cloud_tex
	sm.sky_cover_modulate = Color(1.0, 1.0, 1.0, 1.0)

	sky.sky_material = sm
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75

	# 실시간 전역 조명(SDFGI) — 간접광/색 번짐
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_max_distance = 400.0

	# 화면공간 반사(SSR) — 연못/논물에 하늘·나무 반사
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0

	# 원경 안개 + 볼류메트릭 포그(공기 중 빛)
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.87, 0.92)
	env.fog_density = 0.0005
	env.fog_sky_affect = 0.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012   # 은은한 공기감만
	env.volumetric_fog_albedo = Color(0.9, 0.93, 0.97)
	env.volumetric_fog_length = 200.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.03

	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-38), 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.87)   # 오후 햇살
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.5
	add_child(sun)

## 필지 사이 틈으로 떨어지지 않도록 넓은 받침 지면(들판 배경).
func _setup_base_ground() -> void:
	var ground := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14000, 14000)   # 보구곶리 전체(약 6.5km) 덮도록
	mi.mesh = pm
	mi.position.y = -1.85   # 침하 경작지(-1.6)보다 아래 — Terrain3D 지형이 위를 덮는다
	mi.material_override = Visuals.grass_field_mat()   # 언덕 지형과 같은 디타일링 풀
	ground.add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14000, 0.2, 14000)
	col.shape = box
	col.position.y = -1.95
	ground.add_child(col)
	add_child(ground)

func _setup_parcels() -> void:
	var world := Node3D.new()
	world.name = "World"
	world.set_script(ParcelLoaderScript)
	add_child(world)
