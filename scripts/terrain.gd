extends Node3D
## 완만한 언덕 지형. 노이즈 하이트필드 메시 + 충돌.
## 마을/농지/적 진영 등 플레이 구역은 평평하게 유지하고, 바깥으로 갈수록 굴곡이 생긴다.
## village.gd 등이 height_at()으로 지형 높이를 조회해 나무/바위를 얹는다.

const Visuals := preload("res://scripts/visuals.gd")

const SIZE := 1600.0          # 지형 한 변(m)
const CENTER := Vector2(0.0, -220.0)   # 플레이어(0,0)~적(-520) 모두 덮도록
const RES := 200              # 한 변 분할 수 (8m 간격)
const AMP := 9.0              # 언덕 최대 높이(m)

# 평지로 유지할 구역(월드 XZ 사각형): [min_x, max_x, min_z, max_z]
const FLAT_RECTS := [
	[-48.0, 48.0, -58.0, 48.0],      # 플레이어 마을 + 농지 + 고용소
	[-92.0, -44.0, -64.0, -28.0],    # 마을 서쪽 저수지 터
	[10.0, 110.0, -590.0, -462.0],   # 적 진영(농지+기지)
]
const FLAT_FALLOFF := 70.0    # 평지 경계에서 언덕까지 전환 거리(m)

var _noise: FastNoiseLite

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 20260707
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.2
	_build_mesh()

## 월드 좌표의 지형 높이. 평지 구역은 0.
func height_at(x: float, z: float) -> float:
	var half := SIZE * 0.5
	var lx := x - CENTER.x
	var lz := z - CENTER.y
	if abs(lx) > half or abs(lz) > half:
		return 0.0
	# 지형 가장자리에서 0으로 페이드(바깥 평원과 이음새 없이)
	var edge: float = min(half - abs(lx), half - abs(lz))
	var edge_f := clampf(edge / 120.0, 0.0, 1.0)
	# 플레이 구역 평탄화
	var flat_f := 1.0
	for r in FLAT_RECTS:
		var dx: float = max(max(r[0] - x, x - r[1]), 0.0)
		var dz: float = max(max(r[2] - z, z - r[3]), 0.0)
		var d := Vector2(dx, dz).length()
		flat_f = min(flat_f, smoothstep(0.0, 1.0, d / FLAT_FALLOFF))
	var h := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * AMP

	# 마을 뒷산(배산임수): 마을 북쪽에 숲 우거진 능선
	var rx := x / 180.0
	var rz := (z + 110.0) / 34.0
	var ridge := 27.0 * exp(-(rx * rx + rz * rz) * 1.2)
	ridge *= 0.7 + 0.6 * (_noise.get_noise_2d(x * 1.7 + 999.0, z * 1.7) * 0.5 + 0.5)
	h += ridge

	return h * edge_f * flat_f

func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / float(RES)
	var x0 := CENTER.x - SIZE * 0.5
	var z0 := CENTER.y - SIZE * 0.5

	# 정점 그리드
	var verts: Array = []
	verts.resize((RES + 1) * (RES + 1))
	for iz in range(RES + 1):
		for ix in range(RES + 1):
			var x := x0 + ix * step
			var z := z0 + iz * step
			verts[iz * (RES + 1) + ix] = Vector3(x, height_at(x, z) - 0.02, z)

	for iz in range(RES):
		for ix in range(RES):
			var a: Vector3 = verts[iz * (RES + 1) + ix]
			var b: Vector3 = verts[iz * (RES + 1) + ix + 1]
			var c: Vector3 = verts[(iz + 1) * (RES + 1) + ix]
			var d: Vector3 = verts[(iz + 1) * (RES + 1) + ix + 1]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(d)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)

	st.index()              # 정점 공유 → 부드러운 법선(면 단위 격자 음영 방지)
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Visuals.grass_field_mat()   # 디타일링 풀 셰이더
	add_child(mi)
	mi.create_trimesh_collision()
