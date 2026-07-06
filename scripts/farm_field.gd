extends Node3D
## 관개(灌漑) 기반 농지 구역.
## 북쪽 끝에 마을 공용 연못이 있고, 경작지와는 풀밭으로 떨어져 있다.
## 플레이어는 연못에서 물길(C)을 파서 남쪽 경작지까지 물을 끌어오고,
## 물이 닿는 칸에 논(B)을 건설한다. 건설된 논에서만 트랙터/노동자가
## 경운→심기→성장→수확을 한다. (실제 논 구조)
## 적(AI) 농지는 build_default_irrigation()으로 물길이 미리 깔린 채 시작한다.

const Visuals := preload("res://scripts/visuals.gd")

const COLS := 30
const ROWS := 32              # 북쪽 연못 + 완충 풀밭 + 남쪽 경작지 (60m x 64m)
const CELL := 2.0             # 셀 크기(미터)
const CANAL_COST := 2         # 물길 1칸 건설 비용
const PADDY_COST := 5         # 논 1칸 건설 비용
const SEED_COST := 2          # 셀당 씨앗값
const HARVEST_VALUE := 10     # 셀당 수확 수익
const GROW_TIME := 4.0        # 단계당 성장 시간(초)

# 마을 공용 연못: 구역 북쪽 끝의 둥근 물웅덩이(셀 좌표). 경작지와 떨어져 있다.
const POND_CENTER := Vector2(15.0, 4.0)   # (ix, iy)
const POND_RADIUS := 3.5                  # 셀 단위

const RICE_ROWS := 6                          # 칸당 한 변의 모 줄 수(이앙기 줄심기)
const RICE_PER_CELL := RICE_ROWS * RICE_ROWS  # 칸당 벼 포기 수(MultiMesh)

# 칸 종류
enum { KIND_GROUND, KIND_CANAL, KIND_PADDY, KIND_POND }
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
var _ground: Array = []       # MeshInstance3D 셀 바닥
var _extra: Array = []        # 칸 위 구조물(물길 수면/논둑+담수). Node3D 또는 null
var _rice_mm: MultiMesh
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
	_extra.resize(n)

	_setup_rice()

	for iy in range(ROWS):
		for ix in range(COLS):
			var idx := iy * COLS + ix
			_kind[idx] = KIND_GROUND   # 빈 풀밭에서 시작(관개는 건설로)
			_state[idx] = EMPTY
			_timer[idx] = 0.0

			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(CELL, 0.12, CELL)
			g.mesh = gm
			g.position = Vector3(_cell_x(ix), 0.06, _cell_z(iy))
			add_child(g)
			_ground[idx] = g

			_paint(idx)

	_carve_pond()
	print("[FarmField] %dx%d 구역, 북쪽 공용 연못. C: 물길, B: 논 건설." % [COLS, ROWS])

func _cell_x(ix: int) -> float:
	return _min_x + (ix + 0.5) * CELL

func _cell_z(iy: int) -> float:
	return _min_z + (iy + 0.5) * CELL

## 벼 포기 MultiMesh — 논 전체의 벼를 인스턴스 하나로 그린다.
func _setup_rice() -> void:
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 1.0, 0.05)   # 가는 모 — 자라면서 스케일로 굵어진다
	_rice_mm = MultiMesh.new()
	_rice_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rice_mm.use_colors = true
	_rice_mm.mesh = blade
	_rice_mm.instance_count = COLS * ROWS * RICE_PER_CELL
	var zero := Transform3D().scaled(Vector3(0.001, 0.001, 0.001))
	for i in range(_rice_mm.instance_count):
		_rice_mm.set_instance_transform(i, zero)
		_rice_mm.set_instance_color(i, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _rice_mm
	mmi.material_override = Visuals.rice_mat()
	add_child(mmi)

## 마을 공용 연못: 반경 안 칸을 물로 바꾸고, 둥근 수면/둑 장식을 얹는다.
func _carve_pond() -> void:
	for iy in range(ROWS):
		for ix in range(COLS):
			if Vector2(ix + 0.5, iy + 0.5).distance_to(POND_CENTER) <= POND_RADIUS:
				var idx := iy * COLS + ix
				_kind[idx] = KIND_POND
				_paint(idx)

	var cx := _min_x + POND_CENTER.x * CELL
	var cz := _min_z + POND_CENTER.y * CELL
	var r := POND_RADIUS * CELL

	# 둑(흙 테두리)
	var bank := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = r + 1.0
	bm.bottom_radius = r + 1.6
	bm.height = 0.4
	bank.mesh = bm
	bank.position = Vector3(cx, 0.05, cz)
	bank.material_override = Visuals.dirt_mat()
	add_child(bank)

	# 둥근 수면
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = r + 0.5
	wm.bottom_radius = r + 0.5
	wm.height = 0.16
	water.mesh = wm
	water.position = Vector3(cx, 0.18, cz)
	water.material_override = Visuals.water_mat()
	add_child(water)

	# 둘레 갈대(가는 초록 기둥 다발)
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.30, 0.48, 0.22)
	for i in range(14):
		var ang := TAU * float(i) / 14.0 + 0.2
		var reed := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.03
		rm.bottom_radius = 0.06
		rm.height = 1.1 + 0.5 * sin(float(i) * 3.7)
		reed.mesh = rm
		reed.position = Vector3(
			cx + cos(ang) * (r + 1.1),
			rm.height * 0.5,
			cz + sin(ang) * (r + 1.1))
		reed.material_override = reed_mat
		add_child(reed)

## 적 AI용: 연못에서 내려오는 세로 수로 + 남쪽 경작지 가로 지선을 미리 깐다.
func build_default_irrigation() -> void:
	var main_col := int(POND_CENTER.x)
	for iy in range(ROWS):
		var idx := iy * COLS + main_col
		if _kind[idx] == KIND_GROUND:
			_set_kind(idx, KIND_CANAL)
	for branch_row: int in [16, 22, 28]:
		for ix in range(COLS):
			var idx := branch_row * COLS + ix
			if _kind[idx] == KIND_GROUND:
				_set_kind(idx, KIND_CANAL)

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
	return to_global(Vector3(_cell_x(ix), 0.2, _cell_z(iy)))

# --- 건설(플레이어) ---
## 서 있는 풀밭 칸에 물길 건설. 연못/기존 물길에 이어져야 물이 흐른다.
func build_canal_at(world_pos: Vector3) -> String:
	var idx := _cell_index(world_pos)
	if idx < 0:
		return "농지 밖입니다"
	if _kind[idx] != KIND_GROUND:
		return "빈 풀밭에만 물길을 팔 수 있어요"
	if not _adjacent_to_any(idx, [KIND_POND, KIND_CANAL]):
		return "물길은 연못이나 기존 물길 옆에만 팔 수 있어요"
	if not _eco().spend_money(CANAL_COST):
		return "돈 부족 — 물길 %d원" % CANAL_COST
	_set_kind(idx, KIND_CANAL)
	return "물길 연결! (-%d원)" % CANAL_COST

## 물이 닿는 풀밭(물길/연못/기존 논 옆)이면 논으로 건설. 결과 메시지 반환.
func build_paddy_at(world_pos: Vector3) -> String:
	var idx := _cell_index(world_pos)
	if idx < 0:
		return "농지 밖입니다"
	match _kind[idx]:
		KIND_CANAL:
			return "물길 위에는 논을 못 만듭니다"
		KIND_POND:
			return "연못 위에는 논을 못 만듭니다"
		KIND_PADDY:
			return "이미 논입니다"
	if not _adjacent_to_water(idx):
		return "물이 닿는 곳(물길/연못/논 옆)에만 논을 만들 수 있어요"
	if not _eco().spend_money(PADDY_COST):
		return "돈 부족 — 논 건설 %d원" % PADDY_COST
	_set_kind(idx, KIND_PADDY)
	return "논 건설 완료! (-%d원)" % PADDY_COST

## 4방향 이웃 중 물길/연못/기존 논이 있으면 true (물이 닿는 칸).
func _adjacent_to_water(idx: int) -> bool:
	return _adjacent_to_any(idx, [KIND_CANAL, KIND_POND, KIND_PADDY])

func _adjacent_to_any(idx: int, kinds: Array) -> bool:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ix + d.x
		var ny: int = iy + d.y
		if nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS:
			continue
		if _kind[ny * COLS + nx] in kinds:
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
		_set_kind(idx, KIND_PADDY)
		made += 1

## AI 확장: 돈을 내고 논 한 칸을 더 개간. 성공 시 true.
func ai_expand_paddy() -> bool:
	var idx := _first_buildable()
	if idx < 0:
		return false
	if not _eco().spend_money(PADDY_COST):
		return false
	_set_kind(idx, KIND_PADDY)
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
## 칸 종류 변경 + 시각 갱신을 한 번에.
func _set_kind(idx: int, kind: int) -> void:
	_kind[idx] = kind
	if kind == KIND_PADDY:
		_state[idx] = EMPTY
	_paint(idx)

func _paint(idx: int) -> void:
	var g: MeshInstance3D = _ground[idx]
	match _kind[idx]:
		KIND_GROUND:
			g.material_override = Visuals.grass_mat(idx)
			_set_extra(idx, "")
		KIND_CANAL:
			g.material_override = Visuals.dirt_mat()
			_set_extra(idx, "canal")
		KIND_POND:
			g.material_override = Visuals.water_mat()
			_set_extra(idx, "")
		KIND_PADDY:
			g.material_override = Visuals.dry_mud_mat() if _state[idx] == EMPTY else Visuals.wet_mud_mat()
			_set_extra(idx, "paddy")
			# 경운 전(마른 논)에는 물이 없고, 경운하면 물을 댄다.
			var water: MeshInstance3D = _extra[idx].get_node("water")
			water.visible = _state[idx] != EMPTY
	_update_rice(idx)

## 칸 위 구조물 교체. type: "" / "canal"(수면) / "paddy"(논둑+담수).
func _set_extra(idx: int, type: String) -> void:
	var cur: Node3D = _extra[idx]
	if cur != null and cur.get_meta("type", "") == type:
		return
	if cur != null:
		cur.queue_free()
		_extra[idx] = null
	if type == "":
		return

	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var root := Node3D.new()
	root.position = Vector3(_cell_x(ix), 0.0, _cell_z(iy))
	root.set_meta("type", type)

	if type == "canal":
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(CELL * 0.9, 0.06, CELL * 0.9)
		w.mesh = wm
		w.position = Vector3(0, 0.15, 0)
		w.material_override = Visuals.muddy_water_mat()   # 흙탕 도랑물
		root.add_child(w)
	elif type == "paddy":
		# 논둑 — 풀이 덮인 낮은 흙둑이 칸을 두른다(실제 논둑).
		var bund_h := 0.22
		for side in range(4):
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var horizontal := side < 2
			bm.size = Vector3(CELL, bund_h, 0.24) if horizontal else Vector3(0.24, bund_h, CELL)
			b.mesh = bm
			var off := CELL * 0.5 - 0.1
			b.position = Vector3(0, bund_h * 0.5 + 0.06, -off if side == 0 else off) if horizontal \
				else Vector3(-off if side == 2 else off, bund_h * 0.5 + 0.06, 0)
			b.material_override = Visuals.grass_mat()
			root.add_child(b)
		# 담수 수면
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(CELL * 0.82, 0.05, CELL * 0.82)
		w.mesh = wm
		w.name = "water"
		w.position = Vector3(0, 0.16, 0)
		w.material_override = Visuals.paddy_water_mat()
		root.add_child(w)

	add_child(root)
	_extra[idx] = root

## 논 칸의 벼 포기 갱신 — 이앙기처럼 줄 맞춰 심고, 자랄수록 키·부피가 커져 수면을 덮는다.
func _update_rice(idx: int) -> void:
	var base := idx * RICE_PER_CELL
	var s := _state[idx]
	var has_rice: bool = _kind[idx] == KIND_PADDY and (s == PLANTED or s == GROWING or s == MATURE)
	if not has_rice:
		var zero := Transform3D().scaled(Vector3(0.001, 0.001, 0.001))
		for b in range(RICE_PER_CELL):
			_rice_mm.set_instance_transform(base + b, zero)
		return

	var h := 0.3            # 키
	var fat := 1.0          # 포기 굵기(수면 덮는 정도)
	var col := Color(0.48, 0.85, 0.38)   # 갓 심은 모(연두)
	if s == GROWING:
		h = 0.7
		fat = 3.0
		col = Color(0.24, 0.58, 0.20)    # 분얼기 진초록
	elif s == MATURE:
		h = 1.0
		fat = 5.5                        # 빽빽한 카펫
		col = Color(0.90, 0.76, 0.28)    # 황금빛

	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var spacing := CELL / float(RICE_ROWS)
	for b in range(RICE_PER_CELL):
		var bx := b % RICE_ROWS
		var bz := b / float(RICE_ROWS)
		var bzi := int(bz)
		# 줄 맞춘 격자 + 아주 작은 지터(손모 흔들림)
		var jx := (float((idx * 73856093 + b * 19349663) % 100) / 100.0 - 0.5) * 0.06
		var jz := (float((idx * 83492791 + b * 12582917) % 100) / 100.0 - 0.5) * 0.06
		var jh := 1.0 + (float((idx * 15485863 + b * 32452843) % 100) / 100.0 - 0.5) * 0.25
		var px := _cell_x(ix) - CELL * 0.5 + (bx + 0.5) * spacing + jx
		var pz := _cell_z(iy) - CELL * 0.5 + (bzi + 0.5) * spacing + jz
		var t := Transform3D()
		t = t.scaled(Vector3(fat, h * jh, fat))
		t = t.rotated(Vector3.UP, jx * 50.0)
		t.origin = Vector3(px, 0.12 + h * jh * 0.5, pz)
		_rice_mm.set_instance_transform(base + b, t)
		_rice_mm.set_instance_color(base + b, col)

## 디버그: 모든 논 칸의 생육 단계를 골고루 채워 시각 확인용으로 만든다.
func debug_grow() -> void:
	var n := 0
	for idx in range(_kind.size()):
		if _kind[idx] != KIND_PADDY:
			continue
		_state[idx] = [TILLED, PLANTED, GROWING, MATURE][n % 4]
		_paint(idx)
		n += 1
