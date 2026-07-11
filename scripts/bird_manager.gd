extends Node
## 참새 떼 — 익은 벼를 노리는 전통 벼농사의 골칫거리.
## 주기적으로 참새 떼가 날아와 익은 벼 칸을 쪼아먹는다.
## 허수아비(R) 반경 안이면 얼씬 못 하고 달아난다.

const SPAWN_MIN := 22.0      # 다음 떼까지 최소 시간(초)
const SPAWN_MAX := 40.0
const FLY_SPEED := 14.0
const EAT_TIME := 6.0        # 이만큼 쪼아먹으면 벼 한 칸 소실
const N_BIRDS := 6

var field                    # 플레이어 농지(farm_field.gd)
var hud

enum { IDLE, DESCEND, EAT, FLEE }

var _timer := 15.0           # 첫 떼는 조금 일찍
var _state := IDLE
var _flock: Node3D
var _birds: Array = []
var _target_pos := Vector3.ZERO
var _target_idx := -1
var _eat_t := 0.0
var _bob_t := 0.0

func _process(delta: float) -> void:
	match _state:
		IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_try_spawn()
		DESCEND:
			_bob(delta)
			if field.is_guarded(_target_pos):
				_scare()
				return
			var to := _target_pos + Vector3.UP * 1.0 - _flock.position
			if to.length() < 0.8:
				_state = EAT
				_eat_t = EAT_TIME
				if hud != null:
					hud.flash("참새 떼가 벼를 쪼아먹고 있어요! (허수아비: R)")
			else:
				_flock.position += to.normalized() * FLY_SPEED * delta
		EAT:
			_bob(delta, true)
			if field.is_guarded(_target_pos):
				_scare()
				return
			_eat_t -= delta
			if _eat_t <= 0.0:
				field.bird_eat(_target_idx)
				if hud != null:
					hud.flash("참새가 벼 한 칸을 먹어치웠습니다...")
				_state = FLEE
		FLEE:
			_bob(delta)
			_flock.position += Vector3(0.6, 1.0, -0.5).normalized() * FLY_SPEED * 1.6 * delta
			if _flock.position.y > 45.0:
				_flock.queue_free()
				_flock = null
				_state = IDLE
				_timer = randf_range(SPAWN_MIN, SPAWN_MAX)

## 익은 벼가 있을 때만 떼가 온다.
func _try_spawn() -> void:
	var cell: Dictionary = field.random_mature_cell()
	if cell.is_empty():
		_timer = 8.0   # 익은 벼가 없으면 잠시 후 다시
		return
	_target_idx = cell["idx"]
	_target_pos = cell["pos"]

	_flock = Node3D.new()
	_flock.position = _target_pos + Vector3(randf_range(-25, 25), 30.0, randf_range(-25, 25))
	_birds.clear()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.32, 0.24, 0.18)   # 참새 갈색
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.2, 0.15, 0.11)
	for i in range(N_BIRDS):
		var b := Node3D.new()
		b.position = Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 0.5), randf_range(-1.5, 1.5))
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.12, 0.24)
		body.mesh = bm
		body.material_override = body_mat
		b.add_child(body)
		for sx in [-1, 1]:
			var wing := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.2, 0.02, 0.12)
			wing.mesh = wm
			wing.position = Vector3(0.15 * sx, 0.04, 0)
			wing.material_override = wing_mat
			b.add_child(wing)
		_flock.add_child(b)
		_birds.append(b)
	add_child(_flock)
	_state = DESCEND
	if hud != null:
		hud.flash("참새 떼가 논으로 날아옵니다!")

## 허수아비에 놀라 달아남.
func _scare() -> void:
	_state = FLEE
	if hud != null:
		hud.flash("허수아비 덕분에 참새가 달아났어요!")

## 새들 파닥임(위아래 진동 + 흩어짐).
func _bob(delta: float, hopping := false) -> void:
	_bob_t += delta * 10.0
	for i in range(_birds.size()):
		var b: Node3D = _birds[i]
		if not is_instance_valid(b):
			continue
		var amp := 0.05 if hopping else 0.18
		b.position.y += sin(_bob_t + i * 1.7) * amp * delta * 10.0
		b.position.y = clampf(b.position.y, -0.6, 0.8)
		b.rotation.y += delta * (0.5 + 0.2 * float(i % 3))
