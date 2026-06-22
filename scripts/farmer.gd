extends CharacterBody3D
## 농부(도보) — 기본 캐릭터. WASD 이동, 마우스 시점(상하 반전).
## 트랙터 근처에서 F로 탑승.

const SPEED := 7.0
const GRAVITY := 22.0
const MOUSE_SENS := 0.003
const CAM_DIST := 7.0
const BOARD_RANGE := 4.5

const HumanMesh := preload("res://scripts/human_mesh.gd")

var hud
var tractor
var shop
var shop_ui
var rice_field
var paddy_panel
var active := true
var ui_open := false

var _yaw := 0.0
var _pitch := 0.55
var _camera: Camera3D

func _ready() -> void:
	_build()
	_camera = Camera3D.new()
	_camera.far = 2000.0
	add_child(_camera)
	set_active(active)

func _build() -> void:
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.height = 1.8
	cs.radius = 0.4
	col.shape = cs
	col.position.y = 0.9
	add_child(col)

	# 사람(농부) 외형: 파란 셔츠 + 갈색 바지 + 밀짚모자
	add_child(HumanMesh.build(
		Color(0.96, 0.8, 0.62),   # 피부
		Color(0.2, 0.45, 0.8),    # 셔츠
		Color(0.35, 0.25, 0.18),  # 바지
		Color(0.85, 0.72, 0.4),   # 밀짚모자
		false))

## 트랙터에서 내릴 때 시점을 그대로 이어받기 위해 호출.
func set_view(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch

func set_active(on: bool) -> void:
	active = on
	visible = on
	set_physics_process(on)
	collision_layer = 1 if on else 0
	collision_mask = 1 if on else 0
	if on:
		add_to_group("player")
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hud != null:
			hud.set_mode("도보 (F: 트랙터 탑승)")
	else:
		remove_from_group("player")

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clamp(_pitch + event.relative.y * MOUSE_SENS, 0.15, 1.35)  # 상하 반전
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F: _try_board()
			KEY_E: _try_interact()
			KEY_ESCAPE:
				if not ui_open:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if not ui_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var move := Vector3.ZERO
	if not ui_open:
		var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		if Input.is_key_pressed(KEY_W):
			move += forward
		if Input.is_key_pressed(KEY_S):
			move -= forward
		if Input.is_key_pressed(KEY_D):
			move += right
		if Input.is_key_pressed(KEY_A):
			move -= right
		move = move.normalized()

	velocity.x = move.x * SPEED
	velocity.z = move.z * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if move.length() > 0.01:
		# 정면(-Z)이 이동 방향을 향하도록
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), 0.2)

	move_and_slide()
	_update_camera()

func _update_camera() -> void:
	var target := global_position + Vector3.UP * 1.5
	var h := cos(_pitch) * CAM_DIST
	var v := sin(_pitch) * CAM_DIST
	_camera.global_position = target + Vector3(sin(_yaw) * h, v, cos(_yaw) * h)
	_camera.look_at(target, Vector3.UP)

func _try_board() -> void:
	if ui_open:
		return
	if tractor != null and global_position.distance_to(tractor.global_position) <= BOARD_RANGE:
		set_active(false)
		tractor.board(_yaw, _pitch)
		get_viewport().set_input_as_handled()  # 트랙터가 같은 F로 즉시 하차하지 않도록
	elif hud != null:
		hud.flash("트랙터가 멀어요 (가까이 가서 F)")

func _try_interact() -> void:
	if ui_open:
		return
	# 고용소 우선
	if shop != null and shop_ui != null and global_position.distance_to(shop.global_position) <= shop.INTERACT_RANGE:
		shop_ui.open()
		return
	# 논 안이면 논 관리 패널
	if rice_field != null and paddy_panel != null:
		var pd = rice_field.paddy_at(global_position)
		if pd != null:
			paddy_panel.open(pd)
			return
	if hud != null:
		hud.flash("논 안에서 E (또는 고용소 근처에서 E)")
