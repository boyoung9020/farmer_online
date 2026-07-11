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
const SCARECROW_COST := 15    # 허수아비 비용
const SCARECROW_RANGE := 9.0  # 허수아비가 참새를 쫓는 반경(m)
const SEED_COST := 2          # 셀당 씨앗값
const HARVEST_VALUE := 10     # 셀당 수확 수익
const GROW_TIME := 4.0        # 단계당 성장 시간(초)

# 마을 공용 저수지: 농지 구역 완전 밖, 마을 서쪽 평지(셀 좌표 — 음수 = 구역 밖).
# 물은 인입수로(도수로)가 서쪽 경계 취수구(ENTRY_ROW)로 끌어온다.
# 실제 저수지처럼 길쭉하고 비대칭한 윤곽(타원 + 다중 굴곡 + 회전).
const POND_CENTER := Vector2(-18.5, -7.0)  # (ix, iy) → 월드 (-67, -46)
const ENTRY_ROW := 2                       # 인입수로가 들어오는 서쪽 경계 행(취수구)
const POND_RADIUS := 2.9                  # 기본 반지름(셀)
const POND_STRETCH := 1.75                # 가로로 길쭉하게
const POND_ANGLE := 0.35                  # 전체 회전(rad)
const POND_WATER_Y := 0.7                 # 수면 높이 — 논물(0.1)보다 높아 자연 관개가 되는 구조
const BANK_TOP := 0.95                    # 제방 둑마루 높이
const BANK_CELLS := 2.0                   # 호안선 바깥 제방 폭(셀) — 이 구역엔 논 건설 금지

const RICE_ROWS := 4                          # 칸당 한 변의 모 줄 수(이앙기 줄심기)
const RICE_PER_CELL := RICE_ROWS * RICE_ROWS  # 칸당 벼 포기 수(MultiMesh) — 성능 고려 4x4

# 논둑: 사다리꼴 단면의 흙둑(레퍼런스 사진 기준 — 벼·논물보다 한참 높은 단차)
const BUND_BASE_W := 0.85   # 밑변 폭
const BUND_TOP_W := 0.4     # 윗면 폭(사람이 걷는 흙길)
const BUND_H := 0.48        # 높이 — 논물(0.1)·모(0.4)보다 높다

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
var _rice_mms: Dictionary = {}   # 생육 단계 -> 벼 포기 MultiMesh (단계별 고정색 재질)
var _ear_mm: MultiMesh           # 익은 벼 이삭(성숙 시에만 표시)
var _scarecrows: Array = []      # 허수아비 월드 좌표 목록
var _parcel: PackedInt32Array    # 셀 -> 필지 id (실제 논의 불규칙 필지 모자이크)
var _parcel_rects: Array = []    # pid -> [x, y, w, h] (셀 좌표)
var _parcel_deco: Dictionary = {}  # pid -> {"root": Node3D, "water": MeshInstance3D}

# 필지별 색조(밝기) 변화 — 실제 논은 필지마다 톤이 다르다
const PARCEL_TINTS := [1.0, 0.92, 1.08, 0.97]
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

	_gen_parcels()
	_setup_rice()

	# 풀밭 셀은 바닥 박스를 만들지 않는다(지형이 곧 풀밭 — 드로우콜 절약).
	# 물길/연못/논이 될 때 _ensure_ground()로 그때 생성.
	for iy in range(ROWS):
		for ix in range(COLS):
			var idx := iy * COLS + ix
			_kind[idx] = KIND_GROUND
			_state[idx] = EMPTY
			_timer[idx] = 0.0
			_ground[idx] = null

	_carve_pond()
	# 취수구: 인입수로가 서쪽 경계로 들어오는 물길 2칸 — 여기서부터 물길(C)을 이어 짓는다
	_set_kind(ENTRY_ROW * COLS + 0, KIND_CANAL)
	_set_kind(ENTRY_ROW * COLS + 1, KIND_CANAL)
	print("[FarmField] %dx%d 구역, 서쪽 저수지+인입수로. C: 물길, B: 논 건설." % [COLS, ROWS])

func _cell_x(ix: int) -> float:
	return _min_x + (ix + 0.5) * CELL

func _cell_z(iy: int) -> float:
	return _min_z + (iy + 0.5) * CELL

## 필지 분할(BSP): 실제 논처럼 크기·모양이 제각각인 필지 모자이크를 만든다.
## 논둑은 필지 경계에만 서고, 필지마다 색조/수위가 미세하게 다르다.
func _gen_parcels() -> void:
	_parcel = PackedInt32Array()
	_parcel.resize(COLS * ROWS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stack: Array = [[0, 0, COLS, ROWS]]
	var pid := 0
	while not stack.is_empty():
		var r: Array = stack.pop_back()
		var x: int = r[0]
		var y: int = r[1]
		var w: int = r[2]
		var h: int = r[3]
		var can_w := w >= 6
		var can_h := h >= 6
		if (not can_w and not can_h) or (w <= 7 and h <= 7 and rng.randf() < 0.55):
			for iy in range(y, y + h):
				for ix in range(x, x + w):
					_parcel[iy * COLS + ix] = pid
			_parcel_rects.append([x, y, w, h])
			pid += 1
			continue
		if can_w and (w >= h or not can_h):
			var cut := rng.randi_range(3, w - 3)
			stack.append([x, y, cut, h])
			stack.append([x + cut, y, w - cut, h])
		else:
			var cut := rng.randi_range(3, h - 3)
			stack.append([x, y, w, cut])
			stack.append([x, y + cut, w, h - cut])

func _parcel_tint(idx: int) -> Color:
	var f: float = PARCEL_TINTS[_parcel[idx] % PARCEL_TINTS.size()]
	return Color(f, f, f * 0.98)

## 필지 구조물(둘레 논둑 + 필지 전체 담수 한 장) — 필지에 첫 논이 생길 때 만든다.
## 셀당 둑 4개 대신 필지당 박스 5개라 드로우콜이 크게 준다.
func _ensure_parcel_deco(pid: int) -> void:
	if _parcel_deco.has(pid):
		return
	var r: Array = _parcel_rects[pid]
	# 저수지에 걸친 필지는 담수판/논둑을 만들지 않는다(수면을 가리는 문제 방지)
	for iy in range(r[1], r[1] + r[3]):
		for ix in range(r[0], r[0] + r[2]):
			if _kind[iy * COLS + ix] == KIND_POND:
				_parcel_deco[pid] = {"root": null, "water": null}
				return
	var w_m: float = r[2] * CELL
	var h_m: float = r[3] * CELL
	var cx: float = _min_x + (r[0] + r[2] * 0.5) * CELL
	var cz: float = _min_z + (r[1] + r[3] * 0.5) * CELL

	var root := Node3D.new()
	root.position = Vector3(cx, 0.0, cz)

	# 둘레 논둑: 사다리꼴 흙둑(풀 덮인 사면 + 흙 밑단) — 논물보다 한참 높은 단차.
	# 물길/연못이 경계를 지나는 구간은 둑을 끊어 물길을 막지 않는다.
	for side in range(4):
		var horizontal := side < 2
		var n_cells: int = r[2] if horizontal else r[3]
		var run_start := -1
		for i in range(n_cells + 1):
			var blocked := false
			if i < n_cells:
				if horizontal:
					var bx: int = r[0] + i
					var by: int = r[1] if side == 0 else r[1] + r[3] - 1
					blocked = _is_waterway(bx, by) or _is_waterway(bx, by + (-1 if side == 0 else 1))
				else:
					var vx: int = r[0] if side == 2 else r[0] + r[2] - 1
					var vy: int = r[1] + i
					blocked = _is_waterway(vx, vy) or _is_waterway(vx + (-1 if side == 2 else 1), vy)
			if i < n_cells and not blocked:
				if run_start < 0:
					run_start = i
				continue
			if run_start >= 0:
				_add_bund(root, side, w_m, h_m, run_start, i)
				run_start = -1

	# 필지 담수(한 장) — 논둑보다 한참 낮게 고인다. 필지 안 논이 경운되면 보인다
	var wtr := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(w_m - 0.2, 0.04, h_m - 0.2)
	wtr.mesh = wm
	wtr.position = Vector3(0, 0.1 + float(pid % 3) * 0.008, 0)
	wtr.material_override = Visuals.paddy_water_mat(pid % 3)
	wtr.visible = false
	root.add_child(wtr)

	add_child(root)
	_parcel_deco[pid] = {"root": root, "water": wtr}

## 물길/연못 칸인가(경계 밖은 아님) — 논둑을 끊을 자리 판정.
func _is_waterway(ix: int, iy: int) -> bool:
	if ix < 0 or ix >= COLS or iy < 0 or iy >= ROWS:
		return false
	var k := _kind[iy * COLS + ix]
	return k == KIND_CANAL or k == KIND_POND

## 한 변의 [c0, c1) 셀 구간에 사다리꼴 논둑을 세운다(풀 프리즘 + 흙 밑단).
## side별로 높이를 미세하게 달리해 이웃 필지 둑과의 z-파이팅을 피한다.
func _add_bund(root: Node3D, side: int, w_m: float, h_m: float, c0: int, c1: int) -> void:
	var horizontal := side < 2
	var seg_len := float(c1 - c0) * CELL + 0.4
	var along := -(w_m if horizontal else h_m) * 0.5 + (float(c0) + float(c1 - c0) * 0.5) * CELL
	var off := (-h_m if side == 0 else h_m) * 0.5
	if not horizontal:
		off = (-w_m if side == 2 else w_m) * 0.5
	var pos := Vector3(along, 0, off) if horizontal else Vector3(off, 0, along)

	var prism := MeshInstance3D.new()
	prism.mesh = _bund_prism(seg_len, BUND_H + float(side) * 0.004)
	prism.position = pos
	if horizontal:
		prism.rotation.y = PI * 0.5
	prism.material_override = Visuals.grass_mat()
	root.add_child(prism)

	# 물가에 드러나는 흙 밑단(사진의 진흙 둑 발치)
	var skirt := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(seg_len, 0.12, BUND_BASE_W + 0.14) if horizontal \
		else Vector3(BUND_BASE_W + 0.14, 0.12, seg_len)
	skirt.mesh = sm
	skirt.position = pos + Vector3(0, 0.06 + float(side) * 0.003, 0)
	skirt.material_override = Visuals.dirt_mat()
	root.add_child(skirt)

var _bund_meshes: Dictionary = {}   # "길이_높이" -> ArrayMesh 캐시

## 사다리꼴 단면 프리즘(z축 압출) — 논둑 몸체.
func _bund_prism(length: float, height: float) -> ArrayMesh:
	var key := "%.2f_%.3f" % [length, height]
	if _bund_meshes.has(key):
		return _bund_meshes[key]
	var hb := BUND_BASE_W * 0.5
	var ht := BUND_TOP_W * 0.5
	var hl := length * 0.5
	var pts := [Vector2(-hb, 0.0), Vector2(-ht, height), Vector2(ht, height), Vector2(hb, 0.0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(3):   # 좌사면, 윗면, 우사면
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var a1 := Vector3(a.x, a.y, -hl)
		var b1 := Vector3(b.x, b.y, -hl)
		var a2 := Vector3(a.x, a.y, hl)
		var b2 := Vector3(b.x, b.y, hl)
		st.add_vertex(a1)
		st.add_vertex(b2)
		st.add_vertex(b1)
		st.add_vertex(a1)
		st.add_vertex(a2)
		st.add_vertex(b2)
	for zdir: float in [1.0, -1.0]:   # 양 끝 마구리
		var p: Array = [pts[3], pts[2], pts[1], pts[0]] if zdir > 0.0 else pts
		for t: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in t:
				var q: Vector2 = p[k]
				st.add_vertex(Vector3(q.x, q.y, hl * zdir))
	st.generate_normals()
	var mesh := st.commit()
	_bund_meshes[key] = mesh
	return mesh

## 필지 담수 표시 갱신 — 경운된 논이 하나라도 있으면 물을 댄다.
func _update_parcel_water(pid: int) -> void:
	if not _parcel_deco.has(pid) or _parcel_deco[pid]["water"] == null:
		return
	var r: Array = _parcel_rects[pid]
	var flooded := false
	for iy in range(r[1], r[1] + r[3]):
		for ix in range(r[0], r[0] + r[2]):
			var idx := iy * COLS + ix
			if _kind[idx] == KIND_PADDY and _state[idx] != EMPTY:
				flooded = true
				break
		if flooded:
			break
	(_parcel_deco[pid]["water"] as MeshInstance3D).visible = flooded

## 벼 MultiMesh — 생육 단계별 포기 3벌 + 이삭 1벌. 단계 색은 재질 유니폼으로 고정.
func _setup_rice() -> void:
	_rice_mms[PLANTED] = _make_mm(Visuals.rice_clump_mesh(), Color(0.38, 0.72, 0.28))  # 모(연두)
	_rice_mms[GROWING] = _make_mm(Visuals.rice_clump_mesh(), Color(0.16, 0.42, 0.13))  # 분얼기 진초록
	_rice_mms[MATURE] = _make_mm(Visuals.rice_clump_mesh(), Color(0.42, 0.45, 0.16))   # 성숙기 황록 잎
	_ear_mm = _make_mm(Visuals.rice_ear_mesh(), Color(0.74, 0.58, 0.24))               # 황금 이삭

func _make_mm(mesh: Mesh, col: Color) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = COLS * ROWS * RICE_PER_CELL
	var zero := Transform3D().scaled(Vector3(0.001, 0.001, 0.001))
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, zero)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Visuals.sway_mat(col)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED   # 흔들리는 초목은 GI 제외(성능)
	add_child(mmi)
	return mm

## 저수지 윤곽 반지름(로컬 각도 기준) — 여러 주파수의 굴곡으로 비대칭 호안선.
## 한쪽이 너무 쪼그라들지 않게 하한을 둔다.
func _pond_r(ang: float) -> float:
	return POND_RADIUS * maxf(0.55, 1.0
		+ 0.30 * sin(ang + 0.8)
		+ 0.20 * sin(ang * 2.0 + 2.1)
		+ 0.13 * sin(ang * 3.0 + 4.6)
		+ 0.08 * sin(ang * 6.0 + 1.2))

## 저수지 로컬 좌표계: 회전 + 가로 스트레치를 푼 좌표(셀 단위).
func _pond_local(p: Vector2) -> Vector2:
	var d := (p - POND_CENTER).rotated(-POND_ANGLE)
	d.x /= POND_STRETCH
	return d

## 저수지 윤곽 위 월드 좌표(pad: 셀 단위 여유).
func _pond_edge(ang: float, pad: float) -> Vector2:
	var r := _pond_r(ang) + pad
	var p := Vector2(cos(ang) * r * POND_STRETCH, sin(ang) * r).rotated(POND_ANGLE) + POND_CENTER
	return Vector2(_min_x + p.x * CELL, _min_z + p.y * CELL)

## 불규칙 윤곽 판 메시(수면/둑용).
func _pond_fan(pad: float, y: float, mat: Material) -> void:
	var cx := _min_x + POND_CENTER.x * CELL
	var cz := _min_z + POND_CENTER.y * CELL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 56
	for i in range(segs):
		var e1 := _pond_edge(TAU * float(i) / float(segs), pad)
		var e2 := _pond_edge(TAU * float(i + 1) / float(segs), pad)
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(Vector3(e1.x - cx, 0, e1.y - cz))
		st.add_vertex(Vector3(e2.x - cx, 0, e2.y - cz))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = Vector3(cx, y, cz)
	mi.material_override = mat
	add_child(mi)

## 두 윤곽선(pad/높이) 사이 띠 메시 — 저수지 제방 사면/둑마루용.
func _pond_ring(pad_out: float, y_out: float, pad_in: float, y_in: float, mat: Material, walkable := false) -> void:
	var cx := _min_x + POND_CENTER.x * CELL
	var cz := _min_z + POND_CENTER.y * CELL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 56
	for i in range(segs):
		var o1 := _pond_edge(TAU * float(i) / float(segs), pad_out)
		var o2 := _pond_edge(TAU * float(i + 1) / float(segs), pad_out)
		var n1 := _pond_edge(TAU * float(i) / float(segs), pad_in)
		var n2 := _pond_edge(TAU * float(i + 1) / float(segs), pad_in)
		var vo1 := Vector3(o1.x - cx, y_out, o1.y - cz)
		var vo2 := Vector3(o2.x - cx, y_out, o2.y - cz)
		var vn1 := Vector3(n1.x - cx, y_in, n1.y - cz)
		var vn2 := Vector3(n2.x - cx, y_in, n2.y - cz)
		st.add_vertex(vn1)
		st.add_vertex(vo1)
		st.add_vertex(vo2)
		st.add_vertex(vn1)
		st.add_vertex(vo2)
		st.add_vertex(vn2)
	st.index()   # 정점 병합 → 부드러운 사면 음영
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = Vector3(cx, 0.0, cz)
	mi.material_override = mat
	add_child(mi)
	if walkable:
		mi.create_trimesh_collision()

## 취수구를 향한 제방 수문(콘크리트 기둥 + 물막이 판 + 핸들) + 농지까지 인입수로.
func _build_sluice() -> void:
	# 취수구(서쪽 경계 물길) 월드 좌표
	var entry := Vector2(_min_x + 1.0, _min_z + (float(ENTRY_ROW) + 0.5) * CELL)
	var best_ang := 0.0
	var best_d := 1e9
	for i in range(112):
		var ang := TAU * float(i) / 112.0
		var dd := _pond_edge(ang, 1.05).distance_to(entry)
		if dd < best_d:
			best_d = dd
			best_ang = ang
	var best := _pond_edge(best_ang, 1.05)
	var root := Node3D.new()
	root.position = Vector3(best.x, 0.0, best.y)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.28, 0.30)
	metal.metallic = 0.6
	metal.roughness = 0.5
	for sx: float in [-0.62, 0.62]:
		var p := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.24, 1.5, 0.3)
		p.mesh = pm
		p.position = Vector3(sx, 1.3, 0)
		p.material_override = Visuals.concrete_mat()
		root.add_child(p)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.55, 0.22, 0.3)
	beam.mesh = bm
	beam.position = Vector3(0, 2.0, 0)
	beam.material_override = Visuals.concrete_mat()
	root.add_child(beam)
	var gate := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.0, 0.85, 0.1)
	gate.mesh = gm
	gate.position = Vector3(0, 1.15, 0)
	gate.material_override = metal
	root.add_child(gate)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.2
	wheel.mesh = tm
	wheel.position = Vector3(0, 2.18, 0)
	wheel.material_override = metal
	root.add_child(wheel)
	add_child(root)
	root.look_at(Vector3(entry.x, 0.0, entry.y), Vector3.UP)   # 물막이 판이 흐름과 직각

	# 인입수로(도수로): 제방 통관 출구에서 간선도로 앞까지 — 도로 밑은 암거로 지나
	var p0 := _pond_edge(best_ang, 2.45)
	var dirv := (entry - p0).normalized()
	var total := p0.distance_to(entry)
	var t_road := (( -35.2 - p0.x) / dirv.x) if absf(dirv.x) > 0.001 else -1.0
	if t_road > 0.0 and t_road < total:
		_feeder_channel(p0, p0 + dirv * t_road)
	else:
		_feeder_channel(p0, entry)

## 저수지→농지 콘크리트 도수로 한 구간(바닥판 + 양쪽 벽 + 물).
func _feeder_channel(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var root := Node3D.new()
	root.position = Vector3(mid.x, 0.0, mid.y)
	add_child(root)
	root.look_at(Vector3(b.x, 0.0, b.y), Vector3.UP)
	var L := a.distance_to(b)
	var bed := MeshInstance3D.new()
	var bedm := BoxMesh.new()
	bedm.size = Vector3(1.6, 0.05, L)
	bed.mesh = bedm
	bed.position = Vector3(0, 0.025, 0)
	bed.material_override = Visuals.concrete_mat()
	root.add_child(bed)
	for sx: float in [-0.69, 0.69]:
		var wall := MeshInstance3D.new()
		var wmb := BoxMesh.new()
		wmb.size = Vector3(0.22, 0.36, L)
		wall.mesh = wmb
		wall.position = Vector3(sx, 0.18, 0)
		wall.material_override = Visuals.concrete_mat()
		root.add_child(wall)
	var w := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.2, 0.05, L)
	w.mesh = wm
	w.position = Vector3(0, 0.11, 0)
	w.material_override = Visuals.water_mat()
	root.add_child(w)

## 제방(둑) 구역인가 — 호안선 밖 BANK_CELLS 이내. 논 건설 금지(물길은 통관처럼 관통 가능).
func _in_bank(idx: int) -> bool:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var d := _pond_local(Vector2(ix + 0.5, iy + 0.5))
	var r := _pond_r(d.angle())
	var dist := d.length()
	return dist > r and dist <= r + BANK_CELLS

## 마을 공용 저수지: 불규칙 윤곽으로 칸을 침수시키고 제방(둑)으로 농지와 분리한다.
## 실제 저수지처럼 수면이 논보다 높고, 둑마루 흙길·수문·갈대가 붙는다.
func _carve_pond() -> void:
	for iy in range(ROWS):
		for ix in range(COLS):
			var d := _pond_local(Vector2(ix + 0.5, iy + 0.5))
			if d.length() <= _pond_r(d.angle()):
				var idx := iy * COLS + ix
				_kind[idx] = KIND_POND
				_paint(idx)

	# 제방: 바깥 풀 사면 → 둑마루 흙길 → 물속 안쪽 사면, 마지막에 수면
	_pond_ring(2.2, 0.02, 1.25, BANK_TOP, Visuals.grass_field_mat(), true)
	_pond_ring(1.25, BANK_TOP, 0.9, BANK_TOP, Visuals.dirt_mat(), true)
	_pond_ring(0.9, BANK_TOP, 0.0, 0.3, Visuals.dirt_mat())
	_pond_fan(0.75, POND_WATER_Y, Visuals.water_mat())
	_build_sluice()

	# 둘레 갈대 — 안쪽 사면 얕은 물가를 따라 듬성듬성
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.30, 0.48, 0.22)
	for i in range(22):
		var ang := TAU * float(i) / 22.0 + 0.15
		if (i * 7) % 5 == 0:
			continue   # 드문드문 비운다
		var e := _pond_edge(ang, 0.5)
		var reed := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.03
		rm.bottom_radius = 0.06
		rm.height = 1.1 + 0.5 * sin(float(i) * 3.7)
		reed.mesh = rm
		reed.position = Vector3(e.x, 0.55 + rm.height * 0.5, e.y)
		reed.material_override = reed_mat
		add_child(reed)

## 적 AI용: 취수구에서 이어지는 가로 인입선 + 세로 간선 + 남쪽 경작지 가로 지선.
func build_default_irrigation() -> void:
	var main_col := 15
	for ix in range(2, main_col + 1):
		var idx := ENTRY_ROW * COLS + ix
		if _kind[idx] == KIND_GROUND:
			_set_kind(idx, KIND_CANAL)
	for iy in range(ENTRY_ROW, ROWS):
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
	if _in_bank(idx):
		return "저수지 둑에는 논을 만들 수 없어요"
	if not _adjacent_to_water(idx):
		return "물이 닿는 곳(물길/연못/논 옆)에만 논을 만들 수 있어요"
	if not _eco().spend_money(PADDY_COST):
		return "돈 부족 — 논 건설 %d원" % PADDY_COST
	_set_kind(idx, KIND_PADDY)
	return "논 건설 완료! (-%d원)" % PADDY_COST

## 서 있는 칸에 허수아비 설치. 풀밭/논 위 어디든 가능(물길·연못 제외).
func build_scarecrow_at(world_pos: Vector3) -> String:
	var idx := _cell_index(world_pos)
	if idx < 0:
		return "농지 밖입니다"
	if _kind[idx] == KIND_CANAL or _kind[idx] == KIND_POND:
		return "물 위에는 허수아비를 못 세웁니다"
	var pos := _cell_pos(idx)
	for sc: Vector3 in _scarecrows:
		if sc.distance_to(pos) < 3.0:
			return "여기엔 이미 허수아비가 있어요"
	if not _eco().spend_money(SCARECROW_COST):
		return "돈 부족 — 허수아비 %d원" % SCARECROW_COST
	var model := Visuals.load_glb("res://assets/models/scarecrow.glb")
	if model != null:
		model.position = to_local(pos)
		model.position.y = 0.1
		model.rotation.y = PI + (float(idx % 7) - 3.0) * 0.2   # 삐뚤빼뚤하게
		add_child(model)
	_scarecrows.append(pos)
	return "허수아비 세움! 참새가 얼씬 못 합니다 (-%d원)" % SCARECROW_COST

## 참새 방어: 이 위치가 허수아비 반경 안인가.
func is_guarded(world_pos: Vector3) -> bool:
	for sc: Vector3 in _scarecrows:
		if sc.distance_to(world_pos) <= SCARECROW_RANGE:
			return true
	return false

## 참새용: 익은 벼 칸 하나를 무작위로. 없으면 {}.
func random_mature_cell() -> Dictionary:
	var candidates: Array = []
	for idx in range(_state.size()):
		if _kind[idx] == KIND_PADDY and _state[idx] == MATURE:
			candidates.append(idx)
	if candidates.is_empty():
		return {}
	var idx: int = candidates[randi() % candidates.size()]
	return {"idx": idx, "pos": _cell_pos(idx)}

## 참새가 벼를 쪼아먹음 — 익은 벼가 수확 없이 사라진다.
func bird_eat(idx: int) -> void:
	if idx >= 0 and idx < _kind.size() and _kind[idx] == KIND_PADDY and _state[idx] == MATURE:
		_state[idx] = TILLED
		_paint(idx)

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
		if _kind[idx] == KIND_GROUND and not _in_bank(idx) and _adjacent_to_water(idx):
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
const SIDE_DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]  # 북/남/서/동

## 칸 종류 변경 + 시각 갱신을 한 번에.
## 물길이 되면 이웃 물길의 흙둑 연결도 다시 계산한다.
func _set_kind(idx: int, kind: int) -> void:
	_kind[idx] = kind
	if kind == KIND_PADDY:
		_state[idx] = EMPTY
	_paint(idx)
	if kind == KIND_CANAL:
		var ix := idx % COLS
		@warning_ignore("integer_division")
		var iy := idx / COLS
		for d: Vector2i in SIDE_DIRS:
			var nx: int = ix + d.x
			var ny: int = iy + d.y
			if nx >= 0 and nx < COLS and ny >= 0 and ny < ROWS:
				var nidx := ny * COLS + nx
				if _kind[nidx] == KIND_CANAL:
					_paint(nidx)
				# 새 물길이 필지 경계를 지나면 이웃 필지 논둑을 다시 지어 물길을 튼다
				_rebuild_parcel_deco(_parcel[nidx])
		_rebuild_parcel_deco(_parcel[idx])

## 논둑/담수를 허물고 다시 짓는다(물길이 경계를 뚫었을 때).
func _rebuild_parcel_deco(pid: int) -> void:
	if not _parcel_deco.has(pid):
		return
	var root = _parcel_deco[pid]["root"]
	if root != null:
		(root as Node).queue_free()
	_parcel_deco.erase(pid)
	_ensure_parcel_deco(pid)
	_update_parcel_water(pid)

## 물이 이어지는 방향 비트마스크(이웃이 물길/연못이면 그쪽으로 도랑이 트인다).
func _canal_mask(idx: int) -> int:
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var mask := 0
	for i in range(4):
		var nx: int = ix + SIDE_DIRS[i].x
		var ny: int = iy + SIDE_DIRS[i].y
		if nx >= 0 and nx < COLS and ny >= 0 and ny < ROWS:
			var k := _kind[ny * COLS + nx]
			if k == KIND_CANAL or k == KIND_POND:
				mask |= 1 << i
		elif nx < 0 and iy == ENTRY_ROW:
			mask |= 1 << i   # 서쪽 경계 취수구 — 인입수로와 이어져 벽을 트지 않는다
	return mask

## 셀 바닥 박스를 필요할 때 생성(풀밭 셀은 지형이 대신한다). top_y: 바닥 윗면 높이.
func _ensure_ground(idx: int, top_y := 0.05) -> MeshInstance3D:
	if _ground[idx] != null:
		return _ground[idx]
	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var g := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(CELL, 0.1, CELL)
	g.mesh = gm
	g.position = Vector3(_cell_x(ix), top_y - 0.05, _cell_z(iy))
	add_child(g)
	_ground[idx] = g
	return g

func _paint(idx: int) -> void:
	match _kind[idx]:
		KIND_GROUND:
			if _ground[idx] != null:
				(_ground[idx] as Node).queue_free()
				_ground[idx] = null
			_set_extra(idx, "")
		KIND_CANAL:
			# 도랑은 바닥 박스 없이(지형 위에) 흙둑 단면 + 낮은 수면으로 판다
			if _ground[idx] != null:
				(_ground[idx] as Node).queue_free()
				_ground[idx] = null
			_set_extra(idx, "canal_%d" % _canal_mask(idx))
		KIND_POND:
			# 수면 판(_pond_fan) 바로 아래 보조 물 박스 — 비스듬히 볼 때 빈틈 메움
			_ensure_ground(idx, POND_WATER_Y - 0.08).material_override = Visuals.water_mat()
			_set_extra(idx, "")
		KIND_PADDY:
			var tint := _parcel_tint(idx)
			_ensure_ground(idx).material_override = \
				Visuals.dry_mud_mat(tint) if _state[idx] == EMPTY else Visuals.wet_mud_mat(tint)
			_set_extra(idx, "")
			var pid: int = _parcel[idx]
			_ensure_parcel_deco(pid)
			_update_parcel_water(pid)
	_update_rice(idx)

## 칸 위 구조물 교체. type: "" / "canal"(도랑물).
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

	if type.begins_with("canal"):
		# 콘크리트 U형 농수로: 물이 이어지지 않는 쪽에 회색 벽, 바닥판 + 맑은 물
		var mask := int(type.get_slice("_", 1))
		for side in range(4):
			if mask & (1 << side) != 0:
				continue   # 그쪽으로 물이 이어짐 — 벽 없음
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var horizontal := side < 2
			bm.size = Vector3(CELL + 0.08, 0.36, 0.22) if horizontal else Vector3(0.22, 0.36, CELL + 0.08)
			b.mesh = bm
			var off := CELL * 0.5 - 0.11
			if horizontal:
				b.position = Vector3(0, 0.18, -off if side == 0 else off)
			else:
				b.position = Vector3(-off if side == 2 else off, 0.18, 0)
			b.material_override = Visuals.concrete_mat()
			root.add_child(b)
		# 수로 바닥판(콘크리트) + 맑은 물(벽보다 낮게)
		var bed := MeshInstance3D.new()
		var bedm := BoxMesh.new()
		bedm.size = Vector3(CELL, 0.05, CELL)
		bed.mesh = bedm
		bed.position = Vector3(0, 0.025, 0)
		bed.material_override = Visuals.concrete_mat()
		root.add_child(bed)
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(CELL - 0.1, 0.05, CELL - 0.1)
		w.mesh = wm
		w.position = Vector3(0, 0.11, 0)
		w.material_override = Visuals.water_mat()   # 맑은 수로물(논물과 색으로 구분)
		root.add_child(w)

	add_child(root)
	_extra[idx] = root

## 논 칸의 벼 갱신 — 이앙기처럼 줄 맞춰 심고, 자랄수록 키·부피가 커져 수면을 덮는다.
## 성숙하면 잎은 황록색으로 남고 포기 끝에 황금 이삭이 고개를 숙인다(레퍼런스 기준).
func _update_rice(idx: int) -> void:
	var base := idx * RICE_PER_CELL
	var s := _state[idx]
	var zero := Transform3D().scaled(Vector3(0.001, 0.001, 0.001))
	var has_rice: bool = _kind[idx] == KIND_PADDY and (s == PLANTED or s == GROWING or s == MATURE)
	if not has_rice:
		for b in range(RICE_PER_CELL):
			for mm: MultiMesh in _rice_mms.values():
				mm.set_instance_transform(base + b, zero)
			_ear_mm.set_instance_transform(base + b, zero)
		return

	var h := 0.32           # 키
	var fat := 0.4          # 포기 퍼짐 — 갓 심은 모는 작고 또렷한 포기(사이로 물이 보인다)
	if s == GROWING:
		h = 0.75
		fat = 1.5
	elif s == MATURE:
		h = 1.0
		fat = 3.4           # 빽빽한 카펫(수면이 안 보이게)

	var ix := idx % COLS
	@warning_ignore("integer_division")
	var iy := idx / COLS
	var spacing := CELL / float(RICE_ROWS)
	for b in range(RICE_PER_CELL):
		var bx := b % RICE_ROWS
		@warning_ignore("integer_division")
		var bzi := b / RICE_ROWS
		# 줄 맞춘 격자 + 아주 작은 지터(손모 흔들림)
		var jx := (float((idx * 73856093 + b * 19349663) % 100) / 100.0 - 0.5) * 0.06
		var jz := (float((idx * 83492791 + b * 12582917) % 100) / 100.0 - 0.5) * 0.06
		var jh := 1.0 + (float((idx * 15485863 + b * 32452843) % 100) / 100.0 - 0.5) * 0.25
		var px := _cell_x(ix) - CELL * 0.5 + (bx + 0.5) * spacing + jx
		var pz := _cell_z(iy) - CELL * 0.5 + (bzi + 0.5) * spacing + jz
		var rot := jx * 105.0   # 포기마다 방향만 다르게
		var t := Transform3D()
		t = t.scaled(Vector3(fat, h * jh, fat))
		t = t.rotated(Vector3.UP, rot)
		t.origin = Vector3(px, 0.08 + h * jh * 0.5, pz)
		# 현재 단계 MultiMesh에만 그리고 나머지는 숨김
		for stage: int in _rice_mms:
			var mm: MultiMesh = _rice_mms[stage]
			mm.set_instance_transform(base + b, t if stage == s else zero)

		# 이삭: 성숙 시에만 포기 상단에 표시
		if s == MATURE:
			var et := Transform3D()
			var es := 0.85 + jh * 0.2
			et = et.scaled(Vector3(es, es, es))
			et = et.rotated(Vector3.UP, rot + 0.7)
			et.origin = Vector3(px, 0.08 + h * jh * 0.88, pz)
			_ear_mm.set_instance_transform(base + b, et)
		else:
			_ear_mm.set_instance_transform(base + b, zero)

## 디버그: 모든 논 칸의 생육 단계를 채운다. stage<0이면 단계를 골고루 섞는다.
func debug_grow(stage: int = -1) -> void:
	var n := 0
	for idx in range(_kind.size()):
		if _kind[idx] != KIND_PADDY:
			continue
		_state[idx] = stage if stage >= 0 else [TILLED, PLANTED, GROWING, MATURE][n % 4]
		_paint(idx)
		n += 1
