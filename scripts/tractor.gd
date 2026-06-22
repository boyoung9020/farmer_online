extends CharacterBody3D
## 트랙터(탈것). 농부가 F로 탑승하면 운전 가능.
## 차량식 조향(W/S 가감속, A/D 조향) + 작업 모드(일구기/심기/수확).

const MAX_SPEED := 12.0
const ACCEL := 14.0
const TURN_SPEED := 1.8
const GRAVITY := 22.0
const MOUSE_SENS := 0.003
const CAM_DIST := 12.0
const WORK_WIDTH := 8.0

var hud
var farmer
var field
var active := false

var _yaw := 0.0
var _pitch := 0.55
var _speed := 0.0
var _mode := 0   # 0=운전, 1=일구기, 2=심기, 3=수확
var _camera: Camera3D

func _ready() -> void:
	_build_tractor()
	_camera = Camera3D.new()
	_camera.far = 2000.0
	add_child(_camera)
	# 시작 시 비활성(주차 상태)

func _build_tractor() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.6, 3.6)
	col.shape = box
	col.position.y = 0.9
	add_child(col)

	_add_box(Vector3(2.0, 1.0, 3.2), Vector3(0, 0.9, 0), Color(0.20, 0.50, 0.85))
	_add_box(Vector3(1.4, 0.9, 1.2), Vector3(0, 1.7, 0.4), Color(0.15, 0.32, 0.6))
	_add_box(Vector3(WORK_WIDTH, 0.25, 0.5), Vector3(0, 0.45, -2.0), Color(0.85, 0.72, 0.15))
	_add_wheel(Vector3(-1.05, 0.45, -1.1), 0.45)
	_add_wheel(Vector3(1.05, 0.45, -1.1), 0.45)
	_add_wheel(Vector3(-1.15, 0.7, 1.2), 0.7)
	_add_wheel(Vector3(1.15, 0.7, 1.2), 0.7)

func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	add_child(m)

func _add_wheel(pos: Vector3, r: float) -> void:
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.4
	m.mesh = cy
	m.position = pos
	m.rotation_degrees = Vector3(0, 0, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	m.material_override = mat
	add_child(m)

## 농부가 탑승.
func board(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_set_active(true)

func _set_active(on: bool) -> void:
	active = on
	if on:
		add_to_group("player")
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hud != null:
			hud.set_mode(_mode_name(_mode))
	else:
		remove_from_group("player")
		_speed = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clamp(_pitch + event.relative.y * MOUSE_SENS, 0.15, 1.35)  # 상하 반전
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_mode(0)
			KEY_2: _set_mode(1)
			KEY_3: _set_mode(2)
			KEY_4: _set_mode(3)
			KEY_F: _exit()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not active:
		return
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	var steer := 0.0
	if Input.is_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_key_pressed(KEY_D):
		steer -= 1.0

	if abs(_speed) > 0.3:
		rotation.y += steer * TURN_SPEED * delta * signf(_speed)
	if throttle != 0.0:
		_speed = move_toward(_speed, throttle * MAX_SPEED, ACCEL * delta)
	else:
		_speed = move_toward(_speed, 0.0, ACCEL * 1.5 * delta)

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_update_camera()
	_do_work()

func _update_camera() -> void:
	var target := global_position + Vector3.UP * 2.0
	var h := cos(_pitch) * CAM_DIST
	var v := sin(_pitch) * CAM_DIST
	_camera.global_position = target + Vector3(sin(_yaw) * h, v, cos(_yaw) * h)
	_camera.look_at(target, Vector3.UP)

func _do_work() -> void:
	if _mode == 0 or field == null:
		return
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var center := global_position + fwd * 1.5
	var samples := 5
	for i in range(samples):
		var t := (float(i) / float(samples - 1) - 0.5) * WORK_WIDTH
		field.work_at(center + right * t, _mode)

func _set_mode(m: int) -> void:
	_mode = m
	if hud != null:
		hud.set_mode(_mode_name(m))

func _mode_name(m: int) -> String:
	match m:
		1: return "일구기"
		2: return "심기"
		3: return "수확"
		_: return "운전"

## 하차 — 농부를 옆에 내려놓고 도보로 전환.
func _exit() -> void:
	_set_active(false)
	if farmer != null:
		farmer.global_position = global_position + global_transform.basis.x * 3.0 + Vector3.UP * 0.2
		farmer.set_active(true)
