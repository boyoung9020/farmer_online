extends CharacterBody3D
## 승용 이앙기 — 심기 전용 탈것. 경운된(써레질된) 논 위를 지나가면 모를 심는다.
## F로 탑승/하차. 콤바인(combine.gd)이 이 스크립트를 상속해 수확기로 쓴다.

const Visuals := preload("res://scripts/visuals.gd")

const ACCEL := 10.0
const TURN_SPEED := 1.6
const GRAVITY := 22.0
const MOUSE_SENS := 0.003
const ZOOM_MIN := 6.0
const ZOOM_MAX := 110.0   # 널널한 시야

# 파생 탈것이 _init에서 바꾸는 값들
var max_speed := 7.5
var work_width := 4.0          # 4조식
var work_mode := 2             # FarmField.MODE_PLANT
var work_offset := 1.3         # 작업 지점(+뒤/-앞)
var mode_label := "이앙기 — 써레질된 논 위로 달리면 모를 심습니다"
var model_path := "res://assets/models/transplanter.glb"

var hud
var farmer
var field
var active := false

var _yaw := 0.0
var _pitch := 1.05
var _cam_dist := 20.0
var _speed := 0.0
var _camera: Camera3D

func _ready() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.4, 2.8)
	col.shape = box
	col.position.y = 0.8
	add_child(col)

	var model := Visuals.load_glb(model_path)
	if model != null:
		model.rotation.y = PI   # Blender(-Y 전방) → Godot(-Z 전방) 보정
		add_child(model)
	else:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.2, 2.6)
		m.mesh = bm
		m.position.y = 0.9
		add_child(m)

	_camera = Camera3D.new()
	_camera.far = 2000.0
	_camera.attributes = Visuals.camera_attrs()
	add_child(_camera)

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
			hud.set_mode(mode_label)
	else:
		remove_from_group("player")
		_speed = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clamp(_pitch + event.relative.y * MOUSE_SENS, 0.12, 1.52)  # 거의 수평~수직 자유각
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_exit()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist * 0.88, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist * 1.14, ZOOM_MIN, ZOOM_MAX)

func _physics_process(delta: float) -> void:
	if not active:
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
		_speed = move_toward(_speed, throttle * max_speed, ACCEL * delta)
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
	_do_plant()

func _update_camera() -> void:
	var target := global_position + Vector3.UP * 2.0
	var h := cos(_pitch) * _cam_dist
	var v := sin(_pitch) * _cam_dist
	_camera.global_position = target + Vector3(sin(_yaw) * h, v, cos(_yaw) * h)
	_camera.look_at(target, Vector3.UP)

## 달리는 동안 작업 지점(work_offset) 폭만큼 작업한다(이앙기=심기, 콤바인=수확).
func _do_plant() -> void:
	if field == null or absf(_speed) < 0.5:
		return
	var back := global_transform.basis.z
	var right := global_transform.basis.x
	var center := global_position + back * work_offset
	for i in range(4):
		var t := (float(i) / 3.0 - 0.5) * work_width
		field.work_at(center + right * t, work_mode)

## 하차 — 농부를 옆에 내려놓고 도보로 전환.
func _exit() -> void:
	_set_active(false)
	if farmer != null:
		farmer.global_position = global_position + global_transform.basis.x * 3.0 + Vector3.UP * 0.2
		farmer.set_view(_yaw, _pitch)
		farmer.set_active(true)
