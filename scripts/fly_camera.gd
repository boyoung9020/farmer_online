extends Camera3D
## 자유비행 카메라 — 지형 월드 답사용.
## 좌클릭: 마우스 캡처 / ESC: 해제 / WASD+QE 이동 / Shift 가속

const SPEED := 18.0
const BOOST := 4.0
const SENS := 0.0022

var _captured := false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_captured = true
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_captured = false
	if _captured and event is InputEventMouseMotion:
		rotation.y -= event.relative.x * SENS
		rotation.x = clampf(rotation.x - event.relative.y * SENS, -1.5, 1.5)

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	var sp := SPEED * (BOOST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * sp * delta if dir != Vector3.ZERO else Vector3.ZERO
