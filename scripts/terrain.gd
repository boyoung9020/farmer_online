extends Node3D
## Terrain3D(GDExtension) 기반 지형.
## 기존 노이즈 수식(완만한 언덕 + 플레이 구역 평탄화 + 마을 뒷산 능선)을
## 하이트맵 이미지로 구워 Terrain3D에 임포트한다 — 클립맵 LOD/충돌/
## 경사면 자동 텍스처(풀→바위)/디타일링은 Terrain3D가 처리.
## village.gd 등은 기존처럼 height_at()으로 지형 높이를 조회한다.

const Visuals := preload("res://scripts/visuals.gd")

const SIZE := 1600.0          # 굴곡이 있는 지형 한 변(m) — 바깥은 평원으로 페이드
const CENTER := Vector2(0.0, -220.0)   # 플레이어(0,0)~적(-520) 모두 덮도록
const AMP := 9.0              # 언덕 최대 높이(m)

# 평지로 유지할 구역(월드 XZ 사각형): [min_x, max_x, min_z, max_z]
const FLAT_RECTS := [
	[-48.0, 48.0, -58.0, 48.0],      # 플레이어 마을 + 농지 + 고용소
	[-92.0, -44.0, -64.0, -28.0],    # 마을 서쪽 저수지 터
	[10.0, 110.0, -590.0, -462.0],   # 적 진영(농지+기지)
]
const FLAT_FALLOFF := 70.0    # 평지 경계에서 언덕까지 전환 거리(m)

const MAP_HALF := 1024.0      # Terrain3D 커버 반경(m) — 2x2 리전(리전 1024)
const BAKE_RES := 512         # 하이트맵 계산 해상도(4m 간격) → 2048로 업샘플

var _noise: FastNoiseLite
var terrain   # Terrain3D

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 20260707
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.2
	_build_terrain3d()

## 월드 좌표의 지형 높이. 평지 구역은 0. (게임 로직의 단일 기준 — 하이트맵도 이걸로 굽는다)
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

func _build_terrain3d() -> void:
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain, true)

	# 재질: 경사면 자동 텍스처(평지=풀, 급경사=바위), 하늘 배경 지형 없음
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	# 주의: 이 셰이더는 평지=overlay, 급경사=base 방향으로 블렌딩된다(소스 확인)
	terrain.material.set_shader_param("auto_base_texture", 1)      # 급경사 = 바위
	terrain.material.set_shader_param("auto_overlay_texture", 0)   # 평지 = 풀
	terrain.material.set_shader_param("auto_slope", 4.0)
	terrain.material.set_shader_param("blend_sharpness", 0.92)

	# 텍스처 에셋: 기존 PBR 텍스처를 채널 패킹해 등록
	terrain.assets = Terrain3DAssets.new()
	var grass_ta = _texture_asset("풀", "leafy_grass", 0.16)
	grass_ta.albedo_color = Color(0.82, 1.0, 0.70)   # 이전 들판 톤(초록) 유지
	terrain.assets.set_texture(0, grass_ta)
	terrain.assets.set_texture(1, _texture_asset("바위", "gray_rocks", 0.10))
	terrain.assets.set_texture(2, _texture_asset("흙", "dirt", 0.20))
	# 원거리 매크로 색 변화도 녹색 계열로(기본값은 갈색끼가 돈다)
	terrain.material.set_shader_param("macro_variation1", Color(0.92, 0.97, 0.86))
	terrain.material.set_shader_param("macro_variation2", Color(0.80, 0.88, 0.72))

	# 하이트맵: height_at()을 4m 간격으로 계산 → 2048²로 업샘플 → 임포트
	var img := Image.create_empty(BAKE_RES, BAKE_RES, false, Image.FORMAT_RF)
	var step := MAP_HALF * 2.0 / float(BAKE_RES)
	for py in range(BAKE_RES):
		var z := -MAP_HALF + (py + 0.5) * step
		for px in range(BAKE_RES):
			var x := -MAP_HALF + (px + 0.5) * step
			img.set_pixel(px, py, Color(height_at(x, z), 0.0, 0.0, 1.0))
	img.resize(int(MAP_HALF) * 2, int(MAP_HALF) * 2, Image.INTERPOLATE_CUBIC)
	terrain.region_size = 1024
	terrain.data.import_images([img, null, null], Vector3(-MAP_HALF, 0, -MAP_HALF), 0.0, 1.0)
	print("[Terrain3D] 텍스처 %d개: " % terrain.assets.get_texture_count(),
		terrain.assets.texture_list.map(func(t): return t.name))

## PBR jpg 3장(diff/nor_gl/rough)을 Terrain3D 텍스처 에셋으로.
## 알베도 A=높이(상수), 노멀 A=러프니스(상수 1) — 우리 재질은 전부 거친 표면이라 충분.
func _texture_asset(asset_name: String, slug: String, uv_scale: float):
	var alb: Image = Visuals.tex(slug + "_diff.jpg").get_image()
	alb.decompress()
	alb.convert(Image.FORMAT_RGBA8)
	alb.resize(1024, 1024)
	alb.generate_mipmaps()
	var nrm: Image = Visuals.tex(slug + "_nor_gl.jpg").get_image()
	nrm.decompress()
	nrm.convert(Image.FORMAT_RGBA8)
	nrm.resize(1024, 1024)
	nrm.generate_mipmaps()
	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = ImageTexture.create_from_image(alb)
	ta.normal_texture = ImageTexture.create_from_image(nrm)
	ta.uv_scale = uv_scale
	ta.detiling_rotation = 0.12
	return ta
