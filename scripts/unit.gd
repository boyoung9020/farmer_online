extends CharacterBody3D
## 유닛(사람). 진영(아군/적군) + 역할(농사/군사)을 가진다.
## - 농사(아군): 밭을 돌며 자동 일구기/심기/수확.
## - 군사(아군/적군): 가까운 적을 찾아 교전(체력/공격/사망).

const HumanMesh := preload("res://scripts/human_mesh.gd")
const Visuals := preload("res://scripts/visuals.gd")

# Kenney Blocky Characters(CC0) — 역할/진영별 스킨 (units.LICENSE.txt 참고)
const MODEL_WORKER := "res://assets/models/unit_worker.glb"   # 노동자: 초록 티 아저씨
const MODEL_ALLY := "res://assets/models/unit_ally.glb"       # 아군 군사: 경찰
const MODEL_ENEMY := "res://assets/models/unit_enemy.glb"     # 적군 군사: 검은 정장
const CHAR_SCALE := 0.8
const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"

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
var _visual: Node3D          # 몸통 메시(모내기 숙임 연출용)
var _bow := 0.0              # 남은 숙임 시간
var _anim: AnimationPlayer   # 캐릭터 모델 애니메이션(폴백이면 null)
var _bow_angle := -0.7       # 숙임 각 — GLB는 y=PI 회전 상태라 부호 반대

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

	var path := MODEL_WORKER if role == ROLE_FARMER \
		else (MODEL_ALLY if faction == FACTION_PLAYER else MODEL_ENEMY)
	_visual = Visuals.load_glb(path)
	if _visual != null:
		_visual.rotation.y = PI   # glTF(+Z 전방) → Godot(-Z 전방)
		_visual.scale = Vector3(CHAR_SCALE, CHAR_SCALE, CHAR_SCALE)
		_bow_angle = 0.7          # y=PI 회전 상태라 앞으로 숙이려면 +x
		_anim = _find_anim(_visual)
		if _anim != null:
			for a in [ANIM_IDLE, ANIM_WALK]:
				if _anim.has_animation(a):
					_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			_anim.play(ANIM_IDLE)
	else:
		# 폴백: 블록 사람(색으로 역할/진영 구분)
		var skin := Color(0.95, 0.78, 0.6)
		if role == ROLE_FARMER:
			_visual = HumanMesh.build(skin, Color(0.25, 0.7, 0.35), Color(0.3, 0.22, 0.16), Color(0.85, 0.72, 0.4), false)
		elif faction == FACTION_PLAYER:
			_visual = HumanMesh.build(skin, Color(0.2, 0.4, 0.85), Color(0.18, 0.2, 0.3), Color(0.5, 0.5, 0.55), true)  # 아군 파랑
		else:
			_visual = HumanMesh.build(skin, Color(0.55, 0.12, 0.12), Color(0.12, 0.12, 0.14), Color(0.2, 0.2, 0.22), true)  # 적군 검붉음
	add_child(_visual)

## 모델 하위에서 AnimationPlayer 찾기.
func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null

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

	# 모내기 숙임(두레 연출) — 논일을 할 때 허리를 굽힌다
	_bow = maxf(0.0, _bow - delta)
	if _visual != null:
		_visual.rotation.x = lerpf(_visual.rotation.x, _bow_angle if _bow > 0.0 else 0.0, 0.18)

	# 이동 여부에 따라 걷기/대기 애니메이션 전환
	if _anim != null:
		var want := ANIM_WALK if dir.length() > 0.01 else ANIM_IDLE
		if _anim.current_animation != want and _anim.has_animation(want):
			_anim.play(want, 0.15)

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
		_bow = 0.6   # 허리 굽혀 심기/거두기
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
