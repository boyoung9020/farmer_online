extends RefCounted
## 블록형 휴머노이드(사람) 외형을 코드로 조립해 Node3D로 반환한다.
## 발이 y=0, 키 약 1.85m. 정면은 -Z (코/눈이 -Z 쪽).
## 농부/노동자가 공용으로 사용(색만 다르게).

static func build(skin: Color, shirt: Color, pants: Color, hat: Color, soldier: bool = false) -> Node3D:
	var root := Node3D.new()
	var boots := Color(0.15, 0.1, 0.08)
	var dark := Color(0.08, 0.08, 0.08)

	# 다리
	_box(root, Vector3(0.22, 0.7, 0.28), Vector3(-0.16, 0.35, 0), pants)
	_box(root, Vector3(0.22, 0.7, 0.28), Vector3(0.16, 0.35, 0), pants)
	# 신발
	_box(root, Vector3(0.26, 0.16, 0.36), Vector3(-0.16, 0.08, -0.04), boots)
	_box(root, Vector3(0.26, 0.16, 0.36), Vector3(0.16, 0.08, -0.04), boots)
	# 몸통
	_box(root, Vector3(0.6, 0.65, 0.32), Vector3(0, 1.02, 0), shirt)
	# 팔
	_box(root, Vector3(0.16, 0.6, 0.22), Vector3(-0.39, 1.05, 0), shirt)
	_box(root, Vector3(0.16, 0.6, 0.22), Vector3(0.39, 1.05, 0), shirt)
	# 손
	_box(root, Vector3(0.16, 0.16, 0.22), Vector3(-0.39, 0.72, 0), skin)
	_box(root, Vector3(0.16, 0.16, 0.22), Vector3(0.39, 0.72, 0), skin)
	# 머리
	_box(root, Vector3(0.34, 0.34, 0.34), Vector3(0, 1.52, 0), skin)
	# 코 / 눈 (정면 -Z)
	_box(root, Vector3(0.1, 0.1, 0.08), Vector3(0, 1.49, -0.2), skin)
	_box(root, Vector3(0.07, 0.07, 0.04), Vector3(-0.08, 1.56, -0.185), dark)
	_box(root, Vector3(0.07, 0.07, 0.04), Vector3(0.08, 1.56, -0.185), dark)
	# 모자 / 헬멧
	if soldier:
		_box(root, Vector3(0.4, 0.2, 0.4), Vector3(0, 1.75, 0), hat)
	else:
		_box(root, Vector3(0.34, 0.2, 0.34), Vector3(0, 1.76, 0), hat)   # 모자 윗부분
		_box(root, Vector3(0.62, 0.06, 0.62), Vector3(0, 1.71, 0), hat)  # 밀짚모자 챙
	return root

static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	parent.add_child(m)
