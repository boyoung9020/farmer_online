extends Node3D
## 고용소(상점) 모델. 농부가 가까이서 E로 상점 UI를 연다.

const INTERACT_RANGE := 5.0

func _ready() -> void:
	# 가판대
	_box(Vector3(3.2, 1.0, 1.3), Vector3(0, 0.5, 0), Color(0.5, 0.35, 0.2))
	_box(Vector3(3.2, 0.15, 1.3), Vector3(0, 1.05, 0), Color(0.6, 0.45, 0.28))
	# 기둥
	_box(Vector3(0.16, 2.2, 0.16), Vector3(-1.5, 1.1, -0.55), Color(0.4, 0.28, 0.16))
	_box(Vector3(0.16, 2.2, 0.16), Vector3(1.5, 1.1, -0.55), Color(0.4, 0.28, 0.16))
	_box(Vector3(0.16, 2.2, 0.16), Vector3(-1.5, 1.1, 0.55), Color(0.4, 0.28, 0.16))
	_box(Vector3(0.16, 2.2, 0.16), Vector3(1.5, 1.1, 0.55), Color(0.4, 0.28, 0.16))
	# 차양 지붕
	_box(Vector3(3.8, 0.2, 1.8), Vector3(0, 2.3, 0), Color(0.8, 0.2, 0.2))
	# 간판
	_box(Vector3(2.4, 0.7, 0.1), Vector3(0, 2.85, -0.5), Color(0.95, 0.85, 0.45))

	var sign_label := Label3D.new()
	sign_label.text = "고용소 (E)"
	sign_label.font_size = 110
	sign_label.pixel_size = 0.006
	sign_label.position = Vector3(0, 2.85, -0.56)
	sign_label.modulate = Color(0.2, 0.15, 0.1)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var f := _korean_font()
	if f != null:
		sign_label.font = f
	add_child(sign_label)

func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	add_child(m)

func _korean_font() -> FontFile:
	for path in ["C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/gulim.ttc"]:
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			if f.load_dynamic_font(path) == OK:
				return f
	return null
