extends Node3D
## 비닐하우스 — 설치형 소극 수익 건물. 일정 주기로 채소 판매 수익이 들어온다.
## 노동자·물·참새 걱정 없는 자동 수입 — 논농사(고수익·노동 집약)와 대비되는 안정 수단.

const Visuals := preload("res://scripts/visuals.gd")

const INCOME := 15    # 주기당 수익(원)
const CYCLE := 30.0   # 수익 주기(초)

var hud
var _t := 0.0

func _ready() -> void:
	add_to_group("greenhouses")
	var model := Visuals.load_glb("res://assets/models/greenhouse.glb")
	if model != null:
		model.rotation.y = PI   # Blender 전방 보정(마을 온실과 동일)
		add_child(model)
	else:
		# 폴백: 반투명 비닐 박스
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.4, 2.2, 8.8)
		m.mesh = bm
		m.position.y = 1.1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.95, 0.98, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = mat
		add_child(m)
	# 충돌(마을 장식 온실과 동일 크기) — 걸어서 통과 못 하게
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.6, 2.2, 9.0)
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	body.add_child(col)
	add_child(body)

func _process(delta: float) -> void:
	_t += delta
	if _t >= CYCLE:
		_t -= CYCLE
		GameManager.add_money(INCOME)
		if hud != null:
			hud.flash("[비닐하우스] 채소 판매 +%d원" % INCOME)
