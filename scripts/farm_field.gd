extends Node3D
## 대규모 농지. 셀 격자를 트랙터가 지나가며 일괄 처리한다.
## (사람이 한 칸씩 X — 트랙터가 작업 폭만큼 한 번에)

const COLS := 30
const ROWS := 20
const CELL := 2.0            # 셀 크기(미터) -> 60m x 40m 농지
const SEED_COST := 2         # 셀당 씨앗값
const HARVEST_VALUE := 10    # 셀당 수확 수익
const GROW_TIME := 4.0       # 단계당 성장 시간(초)

# 셀 상태
enum { EMPTY, TILLED, PLANTED, GROWING, MATURE }
# 트랙터 작업 모드
const MODE_OFF := 0
const MODE_TILL := 1
const MODE_PLANT := 2
const MODE_HARVEST := 3

var _state: PackedInt32Array
var _timer: PackedFloat32Array
var _ground: Array = []   # MeshInstance3D 셀 바닥
var _crop: Array = []     # MeshInstance3D 작물
var _min_x: float
var _min_z: float

func _ready() -> void:
	add_to_group("farm_field")
	_min_x = -COLS * CELL * 0.5
	_min_z = -ROWS * CELL * 0.5

	var n := COLS * ROWS
	_state = PackedInt32Array()
	_state.resize(n)
	_timer = PackedFloat32Array()
	_timer.resize(n)
	_ground.resize(n)
	_crop.resize(n)

	for iy in range(ROWS):
		for ix in range(COLS):
			var idx := iy * COLS + ix
			_state[idx] = EMPTY
			_timer[idx] = 0.0
			var cx := _min_x + (ix + 0.5) * CELL
			var cz := _min_z + (iy + 0.5) * CELL

			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(CELL * 0.94, 0.06, CELL * 0.94)
			g.mesh = gm
			g.position = Vector3(cx, 0.06, cz)
			g.material_override = StandardMaterial3D.new()
			add_child(g)
			_ground[idx] = g

			var c := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.7, 1.0, 0.7)
			c.mesh = cm
			c.position = Vector3(cx, 0.1, cz)
			c.material_override = StandardMaterial3D.new()
			c.visible = false
			add_child(c)
			_crop[idx] = c

			_paint(idx)

	print("[FarmField] 셀 %d개 (%dx%d, %dx%dm)" % [n, COLS, ROWS, int(COLS * CELL), int(ROWS * CELL)])

func _process(delta: float) -> void:
	for idx in range(_state.size()):
		var s := _state[idx]
		if s == PLANTED or s == GROWING:
			_timer[idx] += delta
			if _timer[idx] >= GROW_TIME:
				_timer[idx] = 0.0
				_state[idx] = GROWING if s == PLANTED else MATURE
				_paint(idx)

## 월드 좌표가 속한 셀에 작업 모드를 적용한다(트랙터가 호출).
func work_at(world_pos: Vector3, mode: int) -> void:
	var ix := int(floor((world_pos.x - _min_x) / CELL))
	var iy := int(floor((world_pos.z - _min_z) / CELL))
	if ix < 0 or ix >= COLS or iy < 0 or iy >= ROWS:
		return
	_apply(iy * COLS + ix, mode)

## 노동자가 호출: 현재 위치에서 가장 가까운 "할 일 있는 셀"의 위치와 작업 모드 반환.
## (수확/일구기/심기 중 가능한 것. 심기는 돈이 있을 때만.) 없으면 빈 Dictionary.
func request_job(from_pos: Vector3) -> Dictionary:
	var best := -1
	var best_d := INF
	var best_mode := 0
	var can_plant := GameManager.money >= SEED_COST
	for idx in range(_state.size()):
		var s := _state[idx]
		var mode := 0
		if s == MATURE:
			mode = MODE_HARVEST
		elif s == EMPTY:
			mode = MODE_TILL
		elif s == TILLED and can_plant:
			mode = MODE_PLANT
		else:
			continue
		var pos := _cell_pos(idx)
		var d := from_pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = idx
			best_mode = mode
	if best == -1:
		return {}
	return {"pos": _cell_pos(best), "mode": best_mode}

func _cell_pos(idx: int) -> Vector3:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	return Vector3(_min_x + (ix + 0.5) * CELL, 0.2, _min_z + (iy + 0.5) * CELL)

func _apply(idx: int, mode: int) -> void:
	var s := _state[idx]
	match mode:
		MODE_TILL:
			if s == EMPTY:
				_state[idx] = TILLED
				_paint(idx)
		MODE_PLANT:
			if s == TILLED:
				if GameManager.spend_money(SEED_COST):
					_state[idx] = PLANTED
					_timer[idx] = 0.0
					_paint(idx)
		MODE_HARVEST:
			if s == MATURE:
				GameManager.add_money(HARVEST_VALUE)
				_state[idx] = TILLED
				_paint(idx)

func _paint(idx: int) -> void:
	var g: MeshInstance3D = _ground[idx]
	var c: MeshInstance3D = _crop[idx]
	var gmat := g.material_override as StandardMaterial3D
	var cmat := c.material_override as StandardMaterial3D
	match _state[idx]:
		EMPTY:
			gmat.albedo_color = Color(0.30, 0.45, 0.22)   # 풀(미경작)
			c.visible = false
		TILLED:
			gmat.albedo_color = Color(0.38, 0.25, 0.14)   # 일군 흙
			c.visible = false
		PLANTED:
			gmat.albedo_color = Color(0.32, 0.21, 0.12)
			_crop_visual(c, cmat, 0.3, Color(0.35, 0.8, 0.3))
		GROWING:
			gmat.albedo_color = Color(0.32, 0.21, 0.12)
			_crop_visual(c, cmat, 0.65, Color(0.25, 0.65, 0.2))
		MATURE:
			gmat.albedo_color = Color(0.32, 0.21, 0.12)
			_crop_visual(c, cmat, 1.0, Color(0.9, 0.78, 0.2))   # 노랗게 익음

func _crop_visual(c: MeshInstance3D, cmat: StandardMaterial3D, grow: float, color: Color) -> void:
	c.visible = true
	c.scale = Vector3(1.0, grow, 1.0)
	c.position.y = 0.1 + grow * 0.5
	cmat.albedo_color = color
