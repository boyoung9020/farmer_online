extends Node3D
## 보구곶리 지적도(GeoJSON)를 읽어 시작 기준점 주변 필지만 3D 바닥 메시로 생성한다.
##
## 좌표계: 한국 투영좌표(미터). 1 유닛 = 1 미터로 그대로 사용한다.
## GeoJSON Y(북쪽, northing)는 3D에서 -Z 로 매핑한다.
## 기준점/반경만 바꾸면 다른 구역이나 전체 로드로 확장 가능(점령전 단계 재사용).

const DATA_PATH := "res://data/parcels.json"
const ParcelScript := preload("res://scripts/parcel.gd")

# 가장 필지가 밀집한 시작 기준점 (분석으로 산출)
const HOME_X := 161025.0
const HOME_Y := 573075.0
const LOAD_RADIUS := 500.0  # 미터. (LOAD_ALL=false일 때) 이 반경 안의 필지만 로드.
const LOAD_ALL := true       # true면 보구곶리 전체 필지(4,409개) 로드

func _ready() -> void:
	_load_parcels()

func _load_parcels() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("지적도 파일을 열 수 없음: " + DATA_PATH)
		return
	var text := f.get_as_text()
	f.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GeoJSON 파싱 실패")
		return

	var features: Array = data.get("features", [])
	var home := Vector2(HOME_X, HOME_Y)
	var loaded := 0

	for feat in features:
		var geom: Dictionary = feat.get("geometry", {})
		if geom.get("type", "") != "Polygon":
			continue
		var rings: Array = geom.get("coordinates", [])
		if rings.is_empty():
			continue
		var outer: Array = rings[0]
		if outer.size() < 4:
			continue

		# 중심점으로 반경 필터링 (LOAD_ALL=false일 때만)
		if not LOAD_ALL:
			var cx := 0.0
			var cy := 0.0
			for p in outer:
				cx += float(p[0])
				cy += float(p[1])
			cx /= outer.size()
			cy /= outer.size()
			if Vector2(cx, cy).distance_to(home) > LOAD_RADIUS:
				continue

		if _build_parcel(feat, outer, home):
			loaded += 1

	var scope := "전체" if LOAD_ALL else "반경 %dm" % int(LOAD_RADIUS)
	print("[ParcelLoader] 로드된 필지 수: %d (%s)" % [loaded, scope])

## 필지 한 개를 평면 메시 + 충돌체로 만들어 씬에 추가. 성공 시 true.
func _build_parcel(feat: Dictionary, outer: Array, home: Vector2) -> bool:
	# 닫힌 링의 마지막 중복점 제거
	var limit := outer.size()
	var first = outer[0]
	var last = outer[limit - 1]
	if float(first[0]) == float(last[0]) and float(first[1]) == float(last[1]):
		limit -= 1

	var poly := PackedVector2Array()
	for i in range(limit):
		var p = outer[i]
		var lx := float(p[0]) - home.x
		var lz := -(float(p[1]) - home.y)  # northing -> -Z
		poly.append(Vector2(lx, lz))

	if poly.size() < 3:
		return false

	var indices := Geometry2D.triangulate_polygon(poly)
	if indices.is_empty():
		return false  # 삼각분할 실패(비단순 폴리곤 등)는 건너뜀

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		var v := poly[idx]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(v.x, 0.0, v.y))
	var mesh := st.commit()

	var parcel = ParcelScript.new()
	var props: Dictionary = feat.get("properties", {})
	parcel.jibun = str(props.get("JIBUN", ""))
	parcel.pnu = str(props.get("PNU", ""))
	parcel.name = "Parcel_" + parcel.pnu

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	# 지번 해시로 흙/밭 느낌의 색을 약간씩 다르게
	var h := float(abs(hash(parcel.pnu)) % 1000) / 1000.0
	mat.albedo_color = Color(0.45 + h * 0.15, 0.32 + h * 0.18, 0.18 + h * 0.08)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 와인딩 무관하게 양면 표시
	mi.material_override = mat
	parcel.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	parcel.add_child(col)

	add_child(parcel)
	return true
