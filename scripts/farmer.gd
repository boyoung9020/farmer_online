extends CharacterBody3D
## 농부(도보) — 기본 캐릭터. WASD 이동, 탑다운(쿼터뷰) 카메라.
## 휠: 줌, 우클릭 드래그: 회전. 트랙터 근처에서 F로 탑승.

const SPEED := 7.0
const GRAVITY := 22.0
const MOUSE_SENS := 0.003
const BOARD_RANGE := 4.5
const ZOOM_MIN := 8.0
const ZOOM_MAX := 40.0

const HumanMesh := preload("res://scripts/human_mesh.gd")
const Visuals := preload("res://scripts/visuals.gd")

var hud
var tractor                 # (하위호환) 첫 탈것
var vehicles: Array = []    # 탑승 가능한 탈것들(트랙터/이앙기)
var shop
var shop_ui
var field
var active := true
var ui_open := false

var _yaw := 0.0
var _pitch := 1.05          # 탑다운 기본 각(약 60도)
var _cam_dist := 18.0
var _camera: Camera3D

func _ready() -> void:
	_build()
	_camera = Camera3D.new()
	_camera.far = 2000.0
	_camera.attributes = Visuals.camera_attrs()   # 원경 DOF
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if hud != null:
			hud.set_mode("도보 (F: 트랙터 탑승)")
	else:
		remove_from_group("player")

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clamp(_pitch + event.relative.y * MOUSE_SENS, 0.7, 1.45)  # 탑다운 각 유지
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F: _try_board()
			KEY_E: _try_shop()
			KEY_C: _try_build("canal")
			KEY_B: _try_build("paddy")
			KEY_R: _try_build("scarecrow")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# 우클릭을 누르는 동안만 마우스를 잡고 시점 회전. 떼면 즉시 해제.
		if event.pressed and not ui_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		# 휠 줌(전체지도가 열려 있으면 미니맵 쪽에서 처리)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist * 0.88, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist * 1.14, ZOOM_MIN, ZOOM_MAX)

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
	var h := cos(_pitch) * _cam_dist
	var v := sin(_pitch) * _cam_dist
	_camera.global_position = target + Vector3(sin(_yaw) * h, v, cos(_yaw) * h)
	_camera.look_at(target, Vector3.UP)

func _try_board() -> void:
	if ui_open:
		return
	var list := vehicles if not vehicles.is_empty() else ([tractor] if tractor != null else [])
	var best = null
	var best_d := BOARD_RANGE
	for v in list:
		if v == null:
			continue
		var d: float = global_position.distance_to(v.global_position)
		if d <= best_d:
			best_d = d
			best = v
	if best != null:
		set_active(false)
		best.board(_yaw, _pitch)
		get_viewport().set_input_as_handled()  # 탈것이 같은 F로 즉시 하차하지 않도록
	elif hud != null:
		hud.flash("탈것이 멀어요 (트랙터/이앙기 옆에서 F)")

func _try_shop() -> void:
	if ui_open or shop == null or shop_ui == null:
		return
	if global_position.distance_to(shop.global_position) <= shop.INTERACT_RANGE:
		shop_ui.open()
	elif hud != null:
		hud.flash("고용소가 멀어요 (가까이 가서 E)")

## 서 있는 칸에 건설. what: "canal"(물길) / "paddy"(논) / "scarecrow"(허수아비).
func _try_build(what: String) -> void:
	if ui_open or field == null:
		return
	var msg: String
	match what:
		"canal":
			msg = field.build_canal_at(global_position)
		"scarecrow":
			msg = field.build_scarecrow_at(global_position)
		_:
			msg = field.build_paddy_at(global_position)
	if hud != null and msg != "":
		hud.flash(msg)
