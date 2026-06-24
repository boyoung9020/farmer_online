extends Node3D
## 관개(灌漑) 기반 농지.
## 북쪽 저수지 → 메인 수로(가로) + 세로 물길(수로)이 고정으로 깔린다.
## 플레이어는 물길(또는 기존 논)에 인접한 풀밭 칸에만 "논"을 건설할 수 있고,
## 건설된 논에서만 트랙터/노동자가 경운→심기→성장→수확을 한다. (실제 논 구조)

const COLS := 30
const ROWS := 20
const CELL := 2.0            # 셀 크기(미터) -> 60m x 40m 농지
const PADDY_COST := 5        # 논 1칸 건설 비용
const SEED_COST := 2         # 셀당 씨앗값
const HARVEST_VALUE := 10    # 셀당 수확 수익
const GROW_TIME := 4.0       # 단계당 성장 시간(초)

# 물길 배치: 북쪽 끝 행은 메인 수로, 일정 간격 열은 세로 물길.
const MAIN_ROW := 0          # iy==0 : 저수지에서 내려오는 메인 수로(가로)
const LATERAL_STEP := 7
const LATERAL_OFFSET := 5    # ix % STEP == OFFSET -> 세로 물길 (5,12,19,26)

# 칸 종류
enum { KIND_GROUND, KIND_CANAL, KIND_PADDY }
# 논(KIND_PADDY)의 생육 상태
enum { EMPTY, TILLED, PLANTED, GROWING, MATURE }
# 트랙터 작업 모드
const MODE_OFF := 0
const MODE_TILL := 1
const MODE_PLANT := 2
const MODE_HARVEST := 3

var economy   # null이면 플레이어(GameManager). 적은 자기 경제 객체를 주입.

var _kind: PackedByteArray
var _state: PackedInt32Array
var _timer: PackedFloat32Array
var _ground: Array = []   # MeshInstance3D 셀 바닥
var _crop: Array = []     # MeshInstance3D 작물
var _min_x: float
var _min_z: float

func _eco():
	return economy if economy != null else GameManager

func _ready() -> void:
	add_to_group("farm_field")
	_min_x = -COLS * CELL * 0.5
	_min_z = -ROWS * CELL * 0.5

	var n := COLS * ROWS
	_kind = PackedByteArray()
	_kind.resize(n)
	_state = PackedInt32Array()
	_state.resize(n)
	_timer = PackedFloat32Array()
	_timer.resize(n)
	_ground.resize(n)
	_crop.resize(n)

	for iy in range(ROWS):
		for ix in range(COLS):
			var idx := iy * COLS + ix
			_kind[idx] = KIND_CANAL if _is_canal_cell(ix, iy) else KIND_GROUND
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

	_build_reservoir()
	print("[FarmField] %dx%d 격자, 물길 포함. B로 물길 옆에 논 건설." % [COLS, ROWS])

func _is_canal_cell(ix: int, iy: int) -> bool:
	return iy == MAIN_ROW or (ix % LATERAL_STEP) == LATERAL_OFFSET

## 북쪽 저수지(물 탱크) + 둑.
func _build_reservoir() -> void:
	var width := COLS * CELL * 0.75
	var depth := 9.0
	var cz := _min_z - depth * 0.5 - 0.2   # 메인 수로 바로 북쪽

	# 물
	var water := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(width, 0.3, depth)
	water.mesh = wm
	water.position = Vector3(0, 0.1, cz)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.18, 0.40, 0.62, 0.92)
	wmat.metallic = 0.3
	wmat.roughness = 0.1
	water.material_override = wmat
	add_child(water)

	# 둑(흙 테두리) — 물 주위를 살짝 감싼다
	var bank := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width + 2.0, 0.5, depth + 2.0)
	bank.mesh = bm
	bank.position = Vector3(0, 0.0, cz)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.34, 0.27, 0.17)
	bank.material_override = bmat
	add_child(bank)
	move_child(bank, get_child_count() - 2)  # 물 아래로

func _process(delta: float) -> void:
	for idx in range(_state.size()):
		if _kind[idx] != KIND_PADDY:
			continue
		var s := _state[idx]
		if s == PLANTED or s == GROWING:
			_timer[idx] += delta
			if _timer[idx] >= GROW_TIME:
				_timer[idx] = 0.0
				_state[idx] = GROWING if s == PLANTED else MATURE
				_paint(idx)

# --- 인덱스/좌표 변환 (농지 노드가 이동돼도 동작하도록 로컬/글로벌 변환) ---
func _cell_index(world_pos: Vector3) -> int:
	var p := to_local(world_pos)
	var ix := int(floor((p.x - _min_x) / CELL))
	var iy := int(floor((p.z - _min_z) / CELL))
	if ix < 0 or ix >= COLS or iy < 0 or iy >= ROWS:
		return -1
	return iy * COLS + ix

func _cell_pos(idx: int) -> Vector3:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	return to_global(Vector3(_min_x + (ix + 0.5) * CELL, 0.2, _min_z + (iy + 0.5) * CELL))

# --- 논 건설(플레이어) ---
## 물길 또는 기존 논에 인접한 풀밭이면 논으로 건설. 결과 메시지 반환.
func build_paddy_at(world_pos: Vector3) -> String:
	var idx := _cell_index(world_pos)
	if idx < 0:
		return "농지 밖입니다"
	match _kind[idx]:
		KIND_CANAL:
			return "물길 위에는 논을 못 만듭니다"
		KIND_PADDY:
			return "이미 논입니다"
	if not _adjacent_to_water(idx):
		return "물길 옆(또는 기존 논 옆)에만 논을 만들 수 있어요"
	if not _eco().spend_money(PADDY_COST):
		return "돈 부족 — 논 건설 %d원" % PADDY_COST
	_kind[idx] = KIND_PADDY
	_state[idx] = EMPTY
	_paint(idx)
	return "논 건설 완료! (-%d원)" % PADDY_COST

## 4방향 이웃 중 물길/기존 논이 있으면 true (물이 닿는 칸).
func _adjacent_to_water(idx: int) -> bool:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ix + d.x
		var ny: int = iy + d.y
		if nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS:
			continue
		var k := _kind[ny * COLS + nx]
		if k == KIND_CANAL or k == KIND_PADDY:
			return true
	return false

## 물에 닿는 첫 풀밭 칸 인덱스(없으면 -1). AI 확장용.
func _first_buildable() -> int:
	for idx in range(_kind.size()):
		if _kind[idx] == KIND_GROUND and _adjacent_to_water(idx):
			return idx
	return -1

## AI 초기 개간: count칸을 무료로 논으로 만든다(적이 시작부터 논을 갖도록).
func seed_paddies(count: int) -> void:
	var made := 0
	while made < count:
		var idx := _first_buildable()
		if idx < 0:
			break
		_kind[idx] = KIND_PADDY
		_state[idx] = EMPTY
		_paint(idx)
		made += 1

## AI 확장: 돈을 내고 논 한 칸을 더 개간. 성공 시 true.
func ai_expand_paddy() -> bool:
	var idx := _first_buildable()
	if idx < 0:
		return false
	if not _eco().spend_money(PADDY_COST):
		return false
	_kind[idx] = KIND_PADDY
	_state[idx] = EMPTY
	_paint(idx)
	return true

# --- 트랙터/노동자 작업 ---
## 월드 좌표가 속한 논 칸에 작업 모드를 적용(트랙터가 호출). 논이 아니면 무시.
func work_at(world_pos: Vector3, mode: int) -> void:
	var idx := _cell_index(world_pos)
	if idx < 0 or _kind[idx] != KIND_PADDY:
		return
	_apply(idx, mode)

## 노동자가 호출: 가장 가까운 "할 일 있는 논 칸"의 위치와 작업 모드. 없으면 {}.
func request_job(from_pos: Vector3) -> Dictionary:
	var best := -1
	var best_d := INF
	var best_mode := 0
	var can_plant: bool = _eco().money >= SEED_COST
	for idx in range(_state.size()):
		if _kind[idx] != KIND_PADDY:
			continue
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

func _apply(idx: int, mode: int) -> void:
	var s := _state[idx]
	match mode:
		MODE_TILL:
			if s == EMPTY:
				_state[idx] = TILLED
				_paint(idx)
		MODE_PLANT:
			if s == TILLED:
				if _eco().spend_money(SEED_COST):
					_state[idx] = PLANTED
					_timer[idx] = 0.0
					_paint(idx)
		MODE_HARVEST:
			if s == MATURE:
				_eco().add_money(HARVEST_VALUE)
				_state[idx] = TILLED
				_paint(idx)

# --- 시각 ---
func _paint(idx: int) -> void:
	var g: MeshInstance3D = _ground[idx]
	var c: MeshInstance3D = _crop[idx]
	var gmat := g.material_override as StandardMaterial3D
	var cmat := c.material_override as StandardMaterial3D

	if _kind[idx] == KIND_GROUND:
		gmat.albedo_color = Color(0.28, 0.42, 0.20)   # 풀밭(건설 가능 대상)
		c.visible = false
		return
	if _kind[idx] == KIND_CANAL:
		gmat.albedo_color = Color(0.18, 0.40, 0.62)   # 물길
		gmat.metallic = 0.3
		gmat.roughness = 0.1
		c.visible = false
		return

	# KIND_PADDY: 담수된 논 + 생육 단계
	match _state[idx]:
		EMPTY:
			gmat.albedo_color = Color(0.30, 0.40, 0.42)   # 물 댄 빈 논
			c.visible = false
		TILLED:
			gmat.albedo_color = Color(0.30, 0.34, 0.36)   # 써레질된 논
			c.visible = false
		PLANTED:
			gmat.albedo_color = Color(0.28, 0.34, 0.30)
			_crop_visual(c, cmat, 0.3, Color(0.35, 0.8, 0.3))
		GROWING:
			gmat.albedo_color = Color(0.28, 0.32, 0.26)
			_crop_visual(c, cmat, 0.65, Color(0.25, 0.65, 0.2))
		MATURE:
			gmat.albedo_color = Color(0.30, 0.30, 0.20)
			_crop_visual(c, cmat, 1.0, Color(0.9, 0.78, 0.2))   # 노랗게 익음

func _crop_visual(c: MeshInstance3D, cmat: StandardMaterial3D, grow: float, color: Color) -> void:
	c.visible = true
	c.scale = Vector3(1.0, grow, 1.0)
	c.position.y = 0.1 + grow * 0.5
	cmat.albedo_color = color
