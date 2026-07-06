extends Node3D
## 고용소(상점) 모델. 농부가 가까이서 E로 상점 UI를 연다.

const Visuals := preload("res://scripts/visuals.gd")

const INTERACT_RANGE := 5.0

func _ready() -> void:
	# 기단(돌) + 바닥
	_box(Vector3(4.6, 0.25, 3.6), Vector3(0, 0.12, 0), Visuals.stone_mat())
	# 뒷벽/옆벽 (앞은 계산대만 있는 개방형)
	_box(Vector3(4.2, 2.3, 0.18), Vector3(0, 1.4, 1.55), Visuals.plaster_mat())
	_box(Vector3(0.18, 2.3, 3.2), Vector3(-2.0, 1.4, 0), Visuals.plaster_mat())
	_box(Vector3(0.18, 2.3, 3.2), Vector3(2.0, 1.4, 0), Visuals.plaster_mat())
	# 계산대(가판)
	_box(Vector3(3.4, 1.0, 0.5), Vector3(0, 0.75, -1.35), Visuals.wood_mat())
	_box(Vector3(3.6, 0.12, 0.7), Vector3(0, 1.3, -1.35), Visuals.wood_mat())
	# 앞 기둥
	_box(Vector3(0.16, 2.4, 0.16), Vector3(-1.85, 1.45, -1.6), Visuals.wood_mat())
	_box(Vector3(0.16, 2.4, 0.16), Vector3(1.85, 1.45, -1.6), Visuals.wood_mat())
	# 맞배지붕(기와)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(5.0, 1.3, 4.4)
	roof.mesh = pm
	roof.position = Vector3(0, 3.2, 0)
	roof.material_override = Visuals.roof_mat()
	add_child(roof)
	# 간판
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.95, 0.88, 0.55)
	_box(Vector3(2.6, 0.75, 0.1), Vector3(0, 2.75, -1.7), sign_mat)

	var sign_label := Label3D.new()
	sign_label.text = "고용소 (E)"
	sign_label.font_size = 110
	sign_label.pixel_size = 0.006
	sign_label.position = Vector3(0, 2.75, -1.76)
	sign_label.modulate = Color(0.2, 0.15, 0.1)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var f := _korean_font()
	if f != null:
		sign_label.font = f
	add_child(sign_label)

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = mat
	add_child(m)

func _korean_font() -> FontFile:
	for path in ["C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/gulim.ttc"]:
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			if f.load_dynamic_font(path) == OK:
				return f
	return null
