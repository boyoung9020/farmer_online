extends CharacterBody3D
## 트랙터(탈것). 농부가 F로 탑승하면 운전 가능.
## 차량식 조향(W/S 가감속, A/D 조향) + 작업 모드(1~4: 운전/일구기/심기/수확).

const Visuals := preload("res://scripts/visuals.gd")

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
	_camera.attributes = Visuals.camera_attrs()   # 원경 DOF
	add_child(_camera)
	# 시작 시 비활성(주차 상태)

func _build_tractor() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.6, 3.6)
	col.shape = box
	col.position.y = 0.9
	add_child(col)

	var red := Color(0.72, 0.16, 0.12)
	var red_dark := Color(0.52, 0.11, 0.09)
	var dark := Color(0.16, 0.17, 0.19)
	var steel := Color(0.55, 0.57, 0.60)

	# 차대
	_add_box(Vector3(1.5, 0.5, 3.3), Vector3(0, 0.75, 0), dark)
	# 보닛(엔진룸) + 상판
	_add_box(Vector3(1.3, 0.75, 1.7), Vector3(0, 1.32, -0.85), red)
	_add_box(Vector3(1.34, 0.1, 1.74), Vector3(0, 1.74, -0.85), red_dark)
	# 그릴 + 헤드라이트
	_add_box(Vector3(1.05, 0.55, 0.08), Vector3(0, 1.28, -1.74), dark)
	_add_box(Vector3(0.2, 0.18, 0.06), Vector3(-0.35, 1.5, -1.78), Color(1.0, 0.95, 0.65))
	_add_box(Vector3(0.2, 0.18, 0.06), Vector3(0.35, 1.5, -1.78), Color(1.0, 0.95, 0.65))
	# 배기통
	var pipe := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.07
	pm.height = 1.0
	pipe.mesh = pm
	pipe.position = Vector3(0.48, 2.2, -1.25)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = dark
	pipe.material_override = pmat
	add_child(pipe)
	# 펜더(뒷바퀴 흙받기)
	_add_box(Vector3(0.5, 0.14, 1.7), Vector3(-1.15, 1.62, 1.15), red_dark)
	_add_box(Vector3(0.5, 0.14, 1.7), Vector3(1.15, 1.62, 1.15), red_dark)
	# 캐빈: 기둥 4개 + 유리 + 지붕
	for px in [-0.6, 0.6]:
		for pz in [-0.35, 1.05]:
			_add_box(Vector3(0.1, 1.15, 0.1), Vector3(px, 2.02, pz), dark)
	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.12, 1.0, 1.34)
	glass.mesh = gm
	glass.position = Vector3(0, 2.0, 0.35)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.5, 0.66, 0.75, 0.42)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.1
	glass.material_override = gmat
	add_child(glass)
	_add_box(Vector3(1.5, 0.13, 1.8), Vector3(0, 2.66, 0.35), red)
	# 좌석 + 핸들
	_add_box(Vector3(0.55, 0.5, 0.14), Vector3(0, 1.55, 0.85), dark)
	_add_box(Vector3(0.4, 0.06, 0.3), Vector3(0, 1.55, 0.1), steel)
	# 전방 작업기(경운 롤러 + 이빨)
	_add_box(Vector3(WORK_WIDTH, 0.22, 0.35), Vector3(0, 0.55, -2.05), steel)
	for i in range(9):
		var t := (float(i) / 8.0 - 0.5) * (WORK_WIDTH - 0.6)
		_add_box(Vector3(0.12, 0.4, 0.12), Vector3(t, 0.28, -2.05), dark)

	# 바퀴: 뒤가 크고 앞이 작다
	_add_wheel(Vector3(-1.0, 0.5, -1.15), 0.5, 0.4)
	_add_wheel(Vector3(1.0, 0.5, -1.15), 0.5, 0.4)
	_add_wheel(Vector3(-1.15, 0.78, 1.15), 0.78, 0.55)
	_add_wheel(Vector3(1.15, 0.78, 1.15), 0.78, 0.55)

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

## 타이어(검정) + 휠 허브(노랑) 이중 실린더.
func _add_wheel(pos: Vector3, r: float, w: float) -> void:
	var tire := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = w
	tire.mesh = cy
	tire.position = pos
	tire.rotation_degrees = Vector3(0, 0, 90)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.09, 0.09, 0.10)
	tmat.roughness = 0.9
	tire.material_override = tmat
	add_child(tire)

	var hub := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = r * 0.45
	hc.bottom_radius = r * 0.45
	hc.height = w + 0.04
	hub.mesh = hc
	hub.position = pos
	hub.rotation_degrees = Vector3(0, 0, 90)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.85, 0.68, 0.15)
	hub.material_override = hmat
	add_child(hub)

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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
			KEY_F:
				_exit()
				get_viewport().set_input_as_handled()  # 농부가 같은 F로 재탑승하지 않도록
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# 우클릭을 누르는 동안만 마우스를 잡고 시점 회전. 떼면 즉시 해제.
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if not active:
		# 주차(비활성) 상태에서도 중력으로 땅에 내려앉도록
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		move_and_slide()
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
		farmer.set_view(_yaw, _pitch)  # 트랙터에서 보던 시점 그대로 이어받기
		farmer.set_active(true)
