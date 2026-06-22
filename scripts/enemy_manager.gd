extends Node
## 적 AI. 적 기지에서 병사를 주기적으로 생성해 플레이어 집결지로 진군시킨다.
## (최종 타겟은 멀티플레이지만, 현재는 싱글 적 AI)

const UnitScript := preload("res://scripts/unit.gd")

const BASE_POS := Vector3(45, 0, -35)
const TARGET := Vector3(60, 0, 40)     # 플레이어 군사 집결지로 진군
const SPAWN_INTERVAL := 9.0
const FIRST_DELAY := 5.0
const MAX_ENEMIES := 8

var hud
var _t := 0.0
var _started := false

func _ready() -> void:
	_build_base()

func _process(delta: float) -> void:
	if hud != null:
		hud.set_enemies(get_tree().get_nodes_in_group("enemy_soldiers").size())

	_t += delta
	var due := FIRST_DELAY if not _started else SPAWN_INTERVAL
	if _t >= due:
		_t = 0.0
		_started = true
		if get_tree().get_nodes_in_group("enemy_units").size() < MAX_ENEMIES:
			_spawn()

func _spawn() -> void:
	var u := UnitScript.new()
	u.faction = UnitScript.FACTION_ENEMY
	u.role = UnitScript.ROLE_SOLDIER
	u.march_target = TARGET
	u.position = BASE_POS + Vector3(randf_range(-4, 4), 1.0, randf_range(-3, 3))
	add_child(u)

func _build_base() -> void:
	# 적 기지(어두운 건물 + 깃발)
	_box(Vector3(8, 3, 6), BASE_POS + Vector3(0, 1.5, 0), Color(0.18, 0.16, 0.2))
	_box(Vector3(8.6, 0.4, 6.6), BASE_POS + Vector3(0, 3.2, 0), Color(0.3, 0.1, 0.1))   # 지붕
	_box(Vector3(0.2, 4, 0.2), BASE_POS + Vector3(0, 5, 0), Color(0.1, 0.1, 0.1))         # 깃대
	_box(Vector3(1.6, 1.0, 0.1), BASE_POS + Vector3(0.9, 6.2, 0), Color(0.6, 0.1, 0.1))   # 적 깃발

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
