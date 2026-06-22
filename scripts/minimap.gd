extends CanvasLayer
## 미니맵 + 전체지도.
## - 우상단 작은 미니맵: 트랙터를 따라가는 탑다운 뷰(항상 표시).
## - M 키: 로드된 전체 영역을 한눈에 보는 큰 전체지도 토글.

const MAP_SIZE := 240           # 작은 미니맵(px)
const VIEW_METERS := 130.0      # 작은 미니맵 범위(m)
const MARGIN := 16

const FULL_SIZE := 680          # 전체지도(px)
const FULL_VIEW_METERS := 1150.0  # 전체지도 범위(m) — 로드 반경 500m을 모두 포함

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
	_cam.size = VIEW_METERS
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
	_full_cam.size = FULL_VIEW_METERS
	_full_cam.rotation_degrees = Vector3(-90, 0, 0)
	_full_cam.far = 3000.0
	_full_cam.position = Vector3(0, 600, 0)  # 시작 기준점(원점) 위에서 내려다봄
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
		var px := (p.x / FULL_VIEW_METERS) * FULL_SIZE
		var pz := (p.z / FULL_VIEW_METERS) * FULL_SIZE  # 월드 +Z = 화면 아래
		_full_marker.position = _full_center + Vector2(px, pz)
		_full_marker.rotation = -_player.rotation.y
