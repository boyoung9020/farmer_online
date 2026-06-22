extends Node3D
## 루트 씬. 환경/조명/지면/필지/농지/농부/트랙터/노동자/HUD/미니맵 구성(러프 단계).

const ParcelLoaderScript := preload("res://scripts/parcel_loader.gd")
const RiceFieldScript := preload("res://scripts/rice_field.gd")
const PaddyPanelScript := preload("res://scripts/paddy_panel.gd")
const FarmerScript := preload("res://scripts/farmer.gd")
const TractorScript := preload("res://scripts/tractor.gd")
const WorkerManagerScript := preload("res://scripts/worker_manager.gd")
const EnemyManagerScript := preload("res://scripts/enemy_manager.gd")
const ShopScript := preload("res://scripts/shop.gd")
const ShopUiScript := preload("res://scripts/shop_ui.gd")
const HudScript := preload("res://scripts/hud.gd")
const MinimapScript := preload("res://scripts/minimap.gd")

func _ready() -> void:
	_setup_environment()
	_setup_light()
	_setup_base_ground()
	_setup_parcels()

	var rice = RiceFieldScript.new()
	add_child(rice)

	var farmer = FarmerScript.new()
	farmer.position = Vector3(0, 1.5, 30.0)   # 농지 남쪽에서 도보로 시작
	add_child(farmer)

	var tractor = TractorScript.new()
	tractor.position = Vector3(5, 1.5, 30.0)  # 농부 옆에 주차
	add_child(tractor)

	farmer.tractor = tractor
	tractor.farmer = farmer

	var hud = HudScript.new()
	add_child(hud)
	farmer.hud = hud
	tractor.hud = hud
	rice.hud = hud

	var wm = WorkerManagerScript.new()
	wm.rice = rice
	wm.hud = hud
	add_child(wm)

	# 고용소(상점) + 상점 UI
	var shop = ShopScript.new()
	shop.position = Vector3(-8, 0, 30)
	add_child(shop)

	var shop_ui = ShopUiScript.new()
	shop_ui.wm = wm
	shop_ui.farmer = farmer
	add_child(shop_ui)

	# 논 관리 패널
	var paddy_panel = PaddyPanelScript.new()
	paddy_panel.farmer = farmer
	paddy_panel.hud = hud
	add_child(paddy_panel)

	farmer.shop = shop
	farmer.shop_ui = shop_ui
	farmer.rice_field = rice
	farmer.paddy_panel = paddy_panel
	farmer.set_active(true)  # 참조 연결 후 상태표시 갱신

	# 적 AI
	var enemy = EnemyManagerScript.new()
	enemy.hud = hud
	add_child(enemy)

	var mm = MinimapScript.new()
	add_child(mm)

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-40), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

## 필지 사이 틈으로 떨어지지 않도록 넓은 받침 지면(녹지 배경).
func _setup_base_ground() -> void:
	var ground := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14000, 14000)   # 보구곶리 전체(약 6.5km) 덮도록
	mi.mesh = pm
	mi.position.y = -0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.38, 0.2)
	mi.material_override = mat
	ground.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14000, 0.2, 14000)
	col.shape = box
	col.position.y = -0.15
	ground.add_child(col)
	add_child(ground)

func _setup_parcels() -> void:
	var world := Node3D.new()
	world.name = "World"
	world.set_script(ParcelLoaderScript)
	add_child(world)
