extends Object
## 공용 시각 리소스(셰이더/PBR 재질/메시). 전 씬에서 공유해 드로우콜·메모리를 아낀다.
## 텍스처: Poly Haven CC0 (assets/textures/). 박스 지오메트리가 많아
## 월드 트라이플레이너 매핑으로 이음새 없이 입힌다.

const TEX_DIR := "res://assets/textures/"

# ---------- 물 셰이더 (부드러운 노멀맵 물결 + 프레넬 반사) ----------
# 내려다보면 물 아래 흙탕이 보이고, 비스듬히 보면 하늘이 반사되는 실제 물 거동.
# 인공적인 반짝이 점(이미션 글린트)은 쓰지 않는다.
const WATER_SHADER := "
shader_type spatial;
uniform vec3 shallow: source_color = vec3(0.30, 0.58, 0.72);
uniform vec3 deep: source_color = vec3(0.06, 0.26, 0.44);
uniform float ripple: hint_range(0.0, 1.0) = 1.0;   // 물결 세기(0=거울)
uniform float mirror: hint_range(0.0, 1.0) = 0.3;   // 기본 반사 세기
uniform sampler2D nmap: hint_normal;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// 크고 느린 물결 두 겹(점 패턴이 생기지 않게 저주파만)
	vec2 uv1 = wpos.xz * 0.055 + vec2(TIME * 0.014, TIME * 0.009);
	vec2 uv2 = wpos.xz * 0.105 - vec2(TIME * 0.010, TIME * 0.016);
	NORMAL_MAP = mix(texture(nmap, uv1).rgb, texture(nmap, uv2).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.35 * ripple;
	// 프레넬: 수직으로 볼수록 바닥색, 눕혀 볼수록 하늘 반사
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, 0.35 + 0.30 * fres);
	METALLIC = clamp(mirror + fres * 0.55, 0.0, 1.0);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
}
"

# ---------- 초목 흔들림 셰이더 (잔디/벼 공용, MultiMesh 인스턴스 색 사용) ----------
const SWAY_SHADER := "
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col: source_color = vec3(0.27, 0.43, 0.17);
uniform float sway_amp: hint_range(0.0, 0.5) = 0.10;
uniform float tip_light: hint_range(0.0, 1.0) = 0.18;
varying float vh;
void vertex() {
	vh = clamp(VERTEX.y + 0.5, 0.0, 1.0);   // 메시 아래 -0.5 ~ 위 0.5 기준
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.9 + wp.x * 0.7 + wp.z * 0.5) + 0.4 * sin(TIME * 3.7 + wp.z * 1.3);
	VERTEX.x += w * sway_amp * vh;
	VERTEX.z += w * sway_amp * 0.6 * vh;
}
void fragment() {
	ALBEDO = base_col * (1.0 - tip_light * 0.5 + tip_light * vh);
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"

static var _water: ShaderMaterial
static var _sway_cache: Dictionary = {}
static var _pbr_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _water_noise: NoiseTexture2D

# ---------- 텍스처 로딩 ----------
## jpg를 런타임에 직접 읽어 밉맵 포함 텍스처로. (에디터 임포트 불필요)
static func tex(file: String) -> Texture2D:
	if _tex_cache.has(file):
		return _tex_cache[file]
	var path := ProjectSettings.globalize_path(TEX_DIR + file)
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("텍스처 로드 실패: " + path)
		return null
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[file] = t
	return t

## PBR 재질: diff/nor/rough 3종 + 월드 트라이플레이너. scale은 텍스처 반복 크기(m).
## tint로 톤 보정(곱연산).
static func pbr(slug: String, scale: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%.3f|%s" % [slug, scale, tint.to_html()]
	if _pbr_cache.has(key):
		return _pbr_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = tex(slug + "_diff.jpg")
	m.normal_enabled = true
	m.normal_texture = tex(slug + "_nor_gl.jpg")
	m.roughness_texture = tex(slug + "_rough.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / scale
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pbr_cache[key] = m
	return m

# ---------- 지형/농지 ----------
static func grass_mat(_seed_i: int = 0) -> StandardMaterial3D:
	return pbr("leafy_grass", 3.0, Color(0.80, 0.95, 0.68))   # 살짝 초록 보정

static func dirt_mat() -> StandardMaterial3D:
	return pbr("dirt", 4.0)

## tint: 필지별 색조 차이(실제 논은 필지마다 톤이 다르다).
## 스케일을 크게 잡아 타일 반복이 눈에 띄지 않게 한다.
static func dry_mud_mat(tint := Color.WHITE) -> StandardMaterial3D:
	return pbr("dry_mud_field_001", 5.0, tint)

static func wet_mud_mat(tint := Color.WHITE) -> StandardMaterial3D:
	return pbr("brown_mud_02", 4.5, Color(0.75 * tint.r, 0.75 * tint.g, 0.75 * tint.b))

# ---------- 건축 ----------
static func plaster_mat() -> StandardMaterial3D:
	return pbr("clay_plaster", 2.2)

static func roof_mat() -> StandardMaterial3D:
	return pbr("grey_roof_tiles", 2.4)

static func wood_mat() -> StandardMaterial3D:
	return pbr("brown_planks_07", 1.8)

static func stone_mat() -> StandardMaterial3D:
	return pbr("gray_rocks", 2.0)

static func bark_mat() -> StandardMaterial3D:
	return pbr("knotted_pine_bark", 1.4)

static func rock_mat() -> StandardMaterial3D:
	return pbr("gray_rocks", 1.6)

# ---------- 물 ----------
static func _water_normal() -> NoiseTexture2D:
	if _water_noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.03          # 저주파 — 크고 완만한 물결(점 패턴 방지)
		n.fractal_octaves = 2
		_water_noise = NoiseTexture2D.new()
		_water_noise.noise = n
		_water_noise.seamless = true
		_water_noise.as_normal_map = true
		_water_noise.bump_strength = 4.0
		_water_noise.width = 512
		_water_noise.height = 512
	return _water_noise

## 연못/물길 물(파란 담수).
static func water_mat() -> ShaderMaterial:
	if _water == null:
		_water = _make_water()
	return _water

static var _paddy_waters: Dictionary = {}
## 논에 댄 물 — 위에서 보면 흙탕 갈색, 눕혀 보면 하늘 반사(실제 모내기 논).
## bucket: 필지별 물색 변화(0~2).
static func paddy_water_mat(bucket: int = 0) -> ShaderMaterial:
	if not _paddy_waters.has(bucket):
		var m := _make_water()
		var f := 1.0 - 0.08 * float(bucket)
		m.set_shader_parameter("shallow", Color(0.40 * f, 0.34 * f, 0.26 * f))
		m.set_shader_parameter("deep", Color(0.24 * f, 0.19 * f, 0.14 * f))
		m.set_shader_parameter("ripple", 0.15)
		m.set_shader_parameter("mirror", 0.25)
		_paddy_waters[bucket] = m
	return _paddy_waters[bucket]

static var _muddy_water: ShaderMaterial
## 물길 도랑의 흙탕물(약한 흐름).
static func muddy_water_mat() -> ShaderMaterial:
	if _muddy_water == null:
		_muddy_water = _make_water()
		_muddy_water.set_shader_parameter("shallow", Color(0.42, 0.35, 0.26))
		_muddy_water.set_shader_parameter("deep", Color(0.26, 0.20, 0.15))
		_muddy_water.set_shader_parameter("ripple", 0.4)
		_muddy_water.set_shader_parameter("mirror", 0.18)
	return _muddy_water

static func _make_water() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("nmap", _water_normal())
	return m

# ---------- 초목 ----------
## 잔디/벼 공용 흔들림 재질. 색은 유니폼(고정) — 같은 색은 캐시 공유.
static func sway_mat(col: Color = Color(0.27, 0.43, 0.17)) -> ShaderMaterial:
	var key := col.to_html()
	if _sway_cache.has(key):
		return _sway_cache[key]
	var sh := Shader.new()
	sh.code = SWAY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", col)
	_sway_cache[key] = m
	return m

# ---------- 벼 포기 메시 ----------
static var _rice_clump: ArrayMesh
static var _rice_ear: ArrayMesh

## 벼 포기: 밑동에서 여러 갈래로 퍼지며 휘는 잎 다발.
## 높이 1(로컬 y -0.5~0.45) 기준 — 인스턴스 스케일로 생육 표현.
## 성능: 논 전체(수만 포기)가 그려지므로 잎 5장/2세그먼트로 가볍게 유지.
static func rice_clump_mesh() -> ArrayMesh:
	if _rice_clump != null:
		return _rice_clump
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blades := 4
	for i in range(blades):
		var yaw := TAU * float(i) / float(blades) + rng.randf_range(-0.3, 0.3)
		var tilt := rng.randf_range(0.05, 0.22)          # 밑동 기울기
		var curl := rng.randf_range(0.35, 0.85)          # 끝으로 갈수록 휘는 정도
		var length := rng.randf_range(0.85, 1.1)
		_strip(st, yaw, tilt, curl, length, 0.06, 0.01, -0.5)
	# 가운데 곧은 잎 1장
	_strip(st, rng.randf() * TAU, 0.03, 0.15, 1.0, 0.05, 0.01, -0.5)
	st.generate_normals()
	_rice_clump = st.commit()
	return _rice_clump

## 익은 벼 이삭: 포기 끝에서 바깥으로 고개 숙인 줄기 다발. 원점이 포기 상단.
static func rice_ear_mesh() -> ArrayMesh:
	if _rice_ear != null:
		return _rice_ear
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(3):
		var yaw := TAU * float(i) / 3.0 + rng.randf_range(-0.4, 0.4)
		var tilt := rng.randf_range(0.25, 0.45)
		var curl := rng.randf_range(1.6, 2.2)            # 고개를 푹 숙인다
		var length := rng.randf_range(0.32, 0.42)
		_strip(st, yaw, tilt, curl, length, 0.04, 0.022, 0.0)
	st.generate_normals()
	_rice_ear = st.commit()
	return _rice_ear

## 휘어지는 띠(잎/이삭) 하나를 SurfaceTool에 추가.
## yaw: 뻗는 방향, tilt: 시작 기울기, curl: 진행할수록 눕는 각, y0: 시작 높이.
static func _strip(st: SurfaceTool, yaw: float, tilt: float, curl: float,
		length: float, w0: float, w1: float, y0: float) -> void:
	# 흰색 버텍스 컬러 — 메시에 COLOR 속성이 있어야 MultiMesh 인스턴스 색이 적용된다.
	st.set_color(Color.WHITE)
	var r := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-sin(yaw), 0, cos(yaw))
	var segs := 2
	var p := Vector3(0, y0, 0) + r * 0.02
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for s in range(segs + 1):
		var t := float(s) / float(segs)
		var theta := tilt + curl * t
		if s > 0:
			p += (length / float(segs)) * (Vector3.UP * cos(theta) + r * sin(theta))
		var w := lerpf(w0, w1, t) * 0.5
		var vl := p - side * w
		var vr := p + side * w
		if s > 0:
			st.add_vertex(prev_l); st.add_vertex(prev_r); st.add_vertex(vl)
			st.add_vertex(prev_r); st.add_vertex(vr); st.add_vertex(vl)
		prev_l = vl
		prev_r = vr

# ---------- glTF 모델 로딩 ----------
static var _glb_cache: Dictionary = {}

## Blender에서 만든 .glb를 런타임에 로드(에디터 임포트 불필요). 실패 시 null.
## 같은 파일은 한 번만 파싱하고 복제본을 돌려준다.
static func load_glb(res_path: String) -> Node3D:
	if _glb_cache.has(res_path):
		return (_glb_cache[res_path] as Node3D).duplicate()
	var path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(path):
		push_warning("glb 없음: " + path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("glb 로드 실패: " + path)
		return null
	var scene := doc.generate_scene(state)
	_glb_cache[res_path] = scene
	return scene.duplicate()

# ---------- 카메라(플레이어 시점 전용 DOF) ----------
static var _cam_attrs: CameraAttributesPractical
static func camera_attrs() -> CameraAttributesPractical:
	if _cam_attrs == null:
		_cam_attrs = CameraAttributesPractical.new()
		_cam_attrs.dof_blur_far_enabled = true
		_cam_attrs.dof_blur_far_distance = 160.0
		_cam_attrs.dof_blur_far_transition = 120.0
		_cam_attrs.dof_blur_amount = 0.06
	return _cam_attrs
