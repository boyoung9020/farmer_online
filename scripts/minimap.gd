extends CanvasLayer
## 미니맵 + 전체지도.
## - 우상단 작은 미니맵: 트랙터를 따라가는 탑다운 뷰(항상 표시).
## - M 키: 로드된 전체 영역을 한눈에 보는 큰 전체지도 토글.

const MAP_SIZE := 240           # 작은 미니맵(px)
const VIEW_METERS := 130.0      # 작은 미니맵 범위(m)
const MARGIN := 16

const FULL_SIZE := 680          # 전체지도(px)
const FULL_VIEW_METERS := 7200.0  # 전체지도 범위(m) — 보구곶리 전체 포함
const FULL_CENTER := Vector3(-1347, 0, -494)  # 지적도 전체의 중심(월드 좌표)

var _player: Node3D

# 작은 미니맵
var _cam: Camera3D
var _marker: Polygon2D
var _map_center: Vector2

# 전체지도
var _full_root: Control
var _full_cam: Camera3D
var _full_sv: SubViewport
var _full_marker: Polygon2D
var _full_center: Vector2
var _full_visible := false

# 줌(휠) — 보이는 범위(m), 작을수록 확대
var _mini_view := VIEW_METERS
var _full_view := FULL_VIEW_METERS

func _ready() -> void:
	var screen := get_viewport().get_visible_rect().size
	_setup_minimap(screen)
	_setup_fullmap(screen)

func _setup_minimap(screen: Vector2) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(MAP_SIZE, MAP_SIZE)
	sv.world_3d = get_viewport().world_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_DISABLED
	add_child(sv)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = _mini_view
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	_cam.far = 2000.0
	_cam.position = Vector3(0, 200, 0)
	sv.add_child(_cam)

	var origin := Vector2(screen.x - MAP_SIZE - MARGIN, MARGIN)

	var frame := ColorRect.new()
	frame.color = Color(0, 0, 0, 0.65)
	frame.position = origin - Vector2(4, 4)
	frame.size = Vector2(MAP_SIZE + 8, MAP_SIZE + 8)
	add_child(frame)

	var map_tex := TextureRect.new()
	map_tex.texture = sv.get_texture()
	map_tex.position = origin
	map_tex.size = Vector2(MAP_SIZE, MAP_SIZE)
	add_child(map_tex)

	_map_center = origin + Vector2(MAP_SIZE, MAP_SIZE) * 0.5
	_marker = _make_marker()
	_marker.position = _map_center
	add_child(_marker)

func _setup_fullmap(screen: Vector2) -> void:
	_full_root = Control.new()
	_full_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.visible = false
	_full_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_full_root)

	# 어두운 배경
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_root.add_child(dim)

	_full_sv = SubViewport.new()
	_full_sv.size = Vector2i(FULL_SIZE, FULL_SIZE)
	_full_sv.world_3d = get_viewport().world_3d
	_full_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED  # 열렸을 때만 갱신
	_full_sv.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_full_sv)

	_full_cam = Camera3D.new()
	_full_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_full_cam.size = _full_view
	_full_cam.rotation_degrees = Vector3(-90, 0, 0)
	_full_cam.far = 5000.0
	_full_cam.position = Vector3(FULL_CENTER.x, 1500, FULL_CENTER.z)  # 마을 전체 중심 위에서 내려다봄
	_full_sv.add_child(_full_cam)

	var fo := Vector2((screen.x - FULL_SIZE) * 0.5, (screen.y - FULL_SIZE) * 0.5)

	var fframe := ColorRect.new()
	fframe.color = Color(0.05, 0.05, 0.05, 0.95)
	fframe.position = fo - Vector2(6, 6)
	fframe.size = Vector2(FULL_SIZE + 12, FULL_SIZE + 12)
	_full_root.add_child(fframe)

	var ftex := TextureRect.new()
	ftex.texture = _full_sv.get_texture()
	ftex.position = fo
	ftex.size = Vector2(FULL_SIZE, FULL_SIZE)
	_full_root.add_child(ftex)

	_full_center = fo + Vector2(FULL_SIZE, FULL_SIZE) * 0.5
	_full_marker = _make_marker()
	_full_root.add_child(_full_marker)

func _make_marker() -> Polygon2D:
	var m := Polygon2D.new()
	m.polygon = PackedVector2Array([Vector2(0, -9), Vector2(7, 8), Vector2(-7, 8)])
	m.color = Color(0.2, 0.9, 1.0)
	return m

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_toggle_fullmap()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
			get_viewport().set_input_as_handled()

## 휠로 줌. dir<0 확대, dir>0 축소. 전체지도가 열려있으면 전체지도, 아니면 미니맵.
func _zoom(dir: float) -> void:
	var f := 1.18 if dir > 0.0 else 0.85
	if _full_visible:
		_full_view = clampf(_full_view * f, 300.0, 8000.0)
		_full_cam.size = _full_view
	else:
		_mini_view = clampf(_mini_view * f, 40.0, 700.0)
		_cam.size = _mini_view

func _toggle_fullmap() -> void:
	_full_visible = not _full_visible
	_full_root.visible = _full_visible
	_full_sv.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if _full_visible else SubViewport.UPDATE_DISABLED
	)

func _process(_delta: float) -> void:
	# 활성 컨트롤러(도보 농부 또는 운전 중 트랙터)를 매 프레임 추적
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var p := _player.global_position

	# 작은 미니맵: 카메라가 따라가므로 마커는 중앙 고정
	_cam.position = Vector3(p.x, 200, p.z)
	_marker.rotation = -_player.rotation.y

	# 전체지도: 카메라는 고정, 마커를 플레이어 위치로 매핑
	if _full_visible:
		var px := ((p.x - FULL_CENTER.x) / _full_view) * FULL_SIZE
		var pz := ((p.z - FULL_CENTER.z) / _full_view) * FULL_SIZE  # 월드 +Z = 화면 아래
		_full_marker.position = _full_center + Vector2(px, pz)
		_full_marker.rotation = -_player.rotation.y
