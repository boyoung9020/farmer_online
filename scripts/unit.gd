extends CharacterBody3D
## 유닛(사람). 진영(아군/적군) + 역할(농사/군사)을 가진다.
## - 농사(아군): 밭을 돌며 자동 일구기/심기/수확.
## - 군사(아군/적군): 가까운 적을 찾아 교전(체력/공격/사망).

const HumanMesh := preload("res://scripts/human_mesh.gd")

const FACTION_PLAYER := 0
const FACTION_ENEMY := 1
const ROLE_FARMER := 0
const ROLE_SOLDIER := 1

const SPEED := 4.2
const GRAVITY := 20.0
const WORK_RANGE := 1.6
const DETECT_RADIUS := 22.0
const ATTACK_RANGE := 2.2
const ATTACK_CD := 0.8
const ATTACK_DMG := 12

# main/매니저가 생성 시 설정
var faction := FACTION_PLAYER
var role := ROLE_SOLDIER
var field                           # FarmField (농사 노동자용)
var rally := Vector3.ZERO         # 아군 군사 대기 지점
var march_target := Vector3.ZERO   # 적군 진군 목표
var max_health := 60
var move_speed := SPEED            # 진영별로 덮어쓸 수 있는 이동 속도

var _health := 60
var _target := Vector3.ZERO
var _has_target := false
var _mode := 0
var _atk_timer := 0.0

func _ready() -> void:
	add_to_group("units")
	var side := "player" if faction == FACTION_PLAYER else "enemy"
	add_to_group(side + "_units")
	add_to_group(side + ("_farmers" if role == ROLE_FARMER else "_soldiers"))

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.height = 1.6
	cs.radius = 0.35
	col.shape = cs
	col.position.y = 0.8
	add_child(col)

	var skin := Color(0.95, 0.78, 0.6)
	if role == ROLE_FARMER:
		add_child(HumanMesh.build(skin, Color(0.25, 0.7, 0.35), Color(0.3, 0.22, 0.16), Color(0.85, 0.72, 0.4), false))
	elif faction == FACTION_PLAYER:
		add_child(HumanMesh.build(skin, Color(0.2, 0.4, 0.85), Color(0.18, 0.2, 0.3), Color(0.5, 0.5, 0.55), true))  # 아군 파랑
	else:
		add_child(HumanMesh.build(skin, Color(0.55, 0.12, 0.12), Color(0.12, 0.12, 0.14), Color(0.2, 0.2, 0.22), true))  # 적군 검붉음

	_health = max_health

func _physics_process(delta: float) -> void:
	var dir := _farm_dir() if role == ROLE_FARMER else _combat_dir(delta)

	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.2)
	move_and_slide()

func take_damage(amount: int) -> void:
	_health -= amount
	if _health <= 0:
		queue_free()

# --- 농사(아군): 밭을 돌며 자동 일구기/심기/수확 ---
func _farm_dir() -> Vector3:
	if field == null:
		return Vector3.ZERO
	if not _has_target:
		var job: Dictionary = field.request_job(global_position)
		if job.is_empty():
			return Vector3.ZERO
		_target = job["pos"]
		_mode = job["mode"]
		_has_target = true
	var to := _target - global_position
	to.y = 0.0
	if to.length() < WORK_RANGE:
		field.work_at(_target, _mode)
		_has_target = false
		return Vector3.ZERO
	return to.normalized()

# --- 전투(군사) ---
func _combat_dir(delta: float) -> Vector3:
	_atk_timer = maxf(0.0, _atk_timer - delta)
	var foe := _nearest_foe()
	if foe != null:
		var to: Vector3 = foe.global_position - global_position
		to.y = 0.0
		if to.length() <= ATTACK_RANGE:
			if _atk_timer <= 0.0:
				foe.take_damage(ATTACK_DMG)
				_atk_timer = ATTACK_CD
			return Vector3.ZERO
		return to.normalized()

	# 적 없으면 본진/목표로 이동
	var home := rally if faction == FACTION_PLAYER else march_target
	var th := home - global_position
	th.y = 0.0
	if th.length() < 2.0:
		return Vector3.ZERO
	return th.normalized()

func _nearest_foe() -> Node3D:
	var grp := "enemy_units" if faction == FACTION_PLAYER else "player_units"
	var best: Node3D = null
	var best_d := DETECT_RADIUS * DETECT_RADIUS
	for u in get_tree().get_nodes_in_group(grp):
		if not is_instance_valid(u):
			continue
		var d := global_position.distance_squared_to((u as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = u
	return best
