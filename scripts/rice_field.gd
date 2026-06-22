extends Node3D
## 논농사 농지. 셀 격자를 4개 논배미(2×2)로 나눠 각각 Paddy로 관리한다.
## 전역 날씨(맑음/흐림/비)를 순환시키며 각 논을 갱신한다.

const PaddyScript := preload("res://scripts/paddy.gd")

const COLS := 30
const ROWS := 20
const CELL := 2.0
const HALF_C := 15   # COLS/2
const HALF_R := 10   # ROWS/2

var hud
var _paddies: Array = []
var _min_x := 0.0
var _min_z := 0.0

# 날씨
var weather := PaddyScript.W_SUNNY
var _w_timer := 0.0
var _w_next := 22.0

func _ready() -> void:
	_min_x = -COLS * CELL * 0.5
	_min_z = -ROWS * CELL * 0.5

	for i in range(4):
		var p = PaddyScript.new()
		p.index = i
		p.min_x = INF
		p.max_x = -INF
		p.min_z = INF
		p.max_z = -INF
		_paddies.append(p)

	for iy in range(ROWS):
		for ix in range(COLS):
			var cx := _min_x + (ix + 0.5) * CELL
			var cz := _min_z + (iy + 0.5) * CELL
			var pidx := (1 if ix >= HALF_C else 0) + (2 if iy >= HALF_R else 0)
			var p = _paddies[pidx]

			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(CELL * 0.94, 0.06, CELL * 0.94)
			g.mesh = gm
			g.position = Vector3(cx, 0.06, cz)
			g.material_override = StandardMaterial3D.new()
			add_child(g)
			p.grounds.append(g)

			var c := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.7, 1.0, 0.7)
			c.mesh = cm
			c.position = Vector3(cx, 0.1, cz)
			c.material_override = StandardMaterial3D.new()
			c.visible = false
			add_child(c)
			p.crops.append(c)

			p.min_x = minf(p.min_x, cx - CELL * 0.5)
			p.max_x = maxf(p.max_x, cx + CELL * 0.5)
			p.min_z = minf(p.min_z, cz - CELL * 0.5)
			p.max_z = maxf(p.max_z, cz + CELL * 0.5)

	for p in _paddies:
		p.center = Vector3((p.min_x + p.max_x) * 0.5, 0.0, (p.min_z + p.max_z) * 0.5)
		p._paint()

	print("[RiceField] 논 %d개, 셀 %d개" % [_paddies.size(), COLS * ROWS])

func _process(delta: float) -> void:
	_w_timer += delta
	if _w_timer >= _w_next:
		_w_timer = 0.0
		_w_next = randf_range(18.0, 34.0)
		weather = randi() % 3
		if weather == PaddyScript.W_RAIN:
			for p in _paddies:
				if p.stage != PaddyScript.FALLOW and p.stage != PaddyScript.PLOWED:
					p.flooded = true
					p._paint()
		if hud != null:
			hud.set_weather(weather_name())

	for p in _paddies:
		p.update(delta, weather)

func weather_name() -> String:
	match weather:
		PaddyScript.W_SUNNY: return "맑음"
		PaddyScript.W_CLOUDY: return "흐림"
		PaddyScript.W_RAIN: return "비"
	return "?"

## 위치가 속한 논 반환(없으면 null).
func paddy_at(pos: Vector3):
	for p in _paddies:
		if p.contains(pos):
			return p
	return null

## 자동 관리할 일이 있는 가장 가까운 논(노동자용).
func nearest_actionable_paddy(pos: Vector3):
	var best = null
	var best_d := INF
	for p in _paddies:
		if p.auto_next() == "":
			continue
		var d: float = pos.distance_squared_to(p.center)
		if d < best_d:
			best_d = d
			best = p
	return best
