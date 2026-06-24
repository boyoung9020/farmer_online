extends Node
## 적 진영 AI — 플레이어와 "동일한 시스템"으로 경쟁한다.
## 멀리 떨어진 자기 농지에서 노동자가 논농사로 돈을 벌고(독립 경제),
## 그 돈으로 군사를 뽑아 플레이어 집결지로 진군시킨다.

const UnitScript := preload("res://scripts/unit.gd")
const FarmFieldScript := preload("res://scripts/farm_field.gd")
const EconomyScript := preload("res://scripts/economy.gd")

# 플레이어 농지(원점)에서 훨씬 멀리 떨어진 적 본거지.
const ENEMY_ORIGIN := Vector3(60, 0, -520)
const BASE_OFFSET := Vector3(0, 0, -16)        # 농지 북쪽에 적 기지
const TARGET := Vector3(60, 0, 40)             # 플레이어 군사 집결지로 진군

const START_MONEY := 300
const SEED_PADDIES := 24        # 시작 시 무료 개간(이미 개발된 논)
const N_FARMERS := 4            # 적 농사 노동자 수
const SOLDIER_COST := 150
const MAX_SOLDIERS := 8
const SOLDIER_SPEED := 7.5      # 멀리서 진군하므로 빠르게
const EXPAND_INTERVAL := 12.0   # 논 추가 개간 주기
const CHECK_INTERVAL := 2.0     # 군사 충원 판단 주기

var hud

var _economy
var _field
var _expand_t := 0.0
var _check_t := 0.0

func _ready() -> void:
	_economy = EconomyScript.new(START_MONEY)

	# 적 농지(저수지/물길 포함, 플레이어와 동일) — 멀리 배치 + 독립 경제
	_field = FarmFieldScript.new()
	_field.economy = _economy
	_field.position = ENEMY_ORIGIN
	add_child(_field)
	_field.seed_paddies(SEED_PADDIES)   # 이미 개간된 논으로 시작

	_build_base()

	# 적 농사 노동자 고용(자기 농지를 자동 경작 → 적 돈 증가)
	for i in range(N_FARMERS):
		_spawn_farmer(i)

func _process(delta: float) -> void:
	if hud != null:
		hud.set_enemies(get_tree().get_nodes_in_group("enemy_soldiers").size())

	# 주기적으로 논 확장(돈이 있으면)
	_expand_t += delta
	if _expand_t >= EXPAND_INTERVAL:
		_expand_t = 0.0
		_field.ai_expand_paddy()

	# 돈이 모이면 군사 충원
	_check_t += delta
	if _check_t >= CHECK_INTERVAL:
		_check_t = 0.0
		if get_tree().get_nodes_in_group("enemy_soldiers").size() < MAX_SOLDIERS:
			if _economy.spend_money(SOLDIER_COST):
				_spawn_soldier()

func _spawn_farmer(i: int) -> void:
	var u := UnitScript.new()
	u.faction = UnitScript.FACTION_ENEMY
	u.role = UnitScript.ROLE_FARMER
	u.field = _field
	u.position = ENEMY_ORIGIN + Vector3((i % 5) * 1.6 - 3.0, 1.0, 6.0)
	add_child(u)

func _spawn_soldier() -> void:
	var u := UnitScript.new()
	u.faction = UnitScript.FACTION_ENEMY
	u.role = UnitScript.ROLE_SOLDIER
	u.march_target = TARGET
	u.move_speed = SOLDIER_SPEED
	u.position = ENEMY_ORIGIN + BASE_OFFSET + Vector3(randf_range(-4, 4), 1.0, randf_range(-3, 3))
	add_child(u)

func _build_base() -> void:
	var base := ENEMY_ORIGIN + BASE_OFFSET
	# 적 기지(어두운 건물 + 깃발)
	_box(Vector3(8, 3, 6), base + Vector3(0, 1.5, 0), Color(0.18, 0.16, 0.2))
	_box(Vector3(8.6, 0.4, 6.6), base + Vector3(0, 3.2, 0), Color(0.3, 0.1, 0.1))   # 지붕
	_box(Vector3(0.2, 4, 0.2), base + Vector3(0, 5, 0), Color(0.1, 0.1, 0.1))         # 깃대
	_box(Vector3(1.6, 1.0, 0.1), base + Vector3(0.9, 6.2, 0), Color(0.6, 0.1, 0.1))   # 적 깃발

func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	body.position = pos
	body.add_child(m)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	add_child(body)
