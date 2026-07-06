extends Object
## 공용 시각 리소스(셰이더/PBR 재질/메시). 전 씬에서 공유해 드로우콜·메모리를 아낀다.
## 텍스처: Poly Haven CC0 (assets/textures/). 박스 지오메트리가 많아
## 월드 트라이플레이너 매핑으로 이음새 없이 입힌다.

const TEX_DIR := "res://assets/textures/"

# ---------- 물 셰이더 (노멀맵 물결 + 반짝임, SSR로 반사) ----------
const WATER_SHADER := "
shader_type spatial;
uniform vec3 shallow: source_color = vec3(0.30, 0.58, 0.72);
uniform vec3 deep: source_color = vec3(0.06, 0.26, 0.44);
uniform float sparkle: hint_range(0.0, 1.0) = 0.5;
uniform float ripple: hint_range(0.0, 1.0) = 1.0;   // 물결 세기(0=거울)
uniform float mirror: hint_range(0.0, 1.0) = 0.25;  // 하늘 반사 세기
uniform sampler2D nmap: hint_normal;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float a = sin(wpos.x * 1.9 + TIME * 1.3) + cos(wpos.z * 2.3 + TIME * 0.9);
	float m = clamp(0.5 + 0.25 * a * ripple, 0.0, 1.0);
	ALBEDO = mix(deep, shallow, m);
	vec2 uv1 = wpos.xz * 0.14 + vec2(TIME * 0.025, TIME * 0.017);
	vec2 uv2 = wpos.xz * 0.23 - vec2(TIME * 0.019, TIME * 0.031);
	vec3 n = mix(texture(nmap, uv1).rgb, texture(nmap, uv2).rgb, 0.5);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.6 * ripple;
	float glint = pow(max(0.0, sin(wpos.x * 7.3 + TIME * 2.1) * cos(wpos.z * 6.7 - TIME * 1.6)), 8.0);
	EMISSION = vec3(0.9, 0.95, 1.0) * glint * 0.2 * sparkle;
	ROUGHNESS = 0.02;
	METALLIC = mirror;
	SPECULAR = 0.9;
}
"

# ---------- 초목 흔들림 셰이더 (잔디/벼 공용, MultiMesh 인스턴스 색 사용) ----------
const SWAY_SHADER := "
shader_type spatial;
render_mode cull_disabled;
uniform float sway_amp: hint_range(0.0, 0.5) = 0.10;
uniform float tip_light: hint_range(0.0, 1.0) = 0.35;
varying float vh;
varying vec4 vcol;
void vertex() {
	vh = clamp(VERTEX.y + 0.5, 0.0, 1.0);   // 메시 아래 -0.5 ~ 위 0.5 기준
	vcol = COLOR;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.9 + wp.x * 0.7 + wp.z * 0.5) + 0.4 * sin(TIME * 3.7 + wp.z * 1.3);
	VERTEX.x += w * sway_amp * vh;
	VERTEX.z += w * sway_amp * 0.6 * vh;
}
void fragment() {
	ALBEDO = vcol.rgb * (1.0 - tip_light * 0.5 + tip_light * vh);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
"

static var _water: ShaderMaterial
static var _paddy_water: ShaderMaterial
static var _sway: ShaderMaterial
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
	return pbr("dirt", 2.5)

static func dry_mud_mat() -> StandardMaterial3D:
	return pbr("dry_mud_field_001", 2.0)

static func wet_mud_mat() -> StandardMaterial3D:
	return pbr("brown_mud_02", 2.0, Color(0.75, 0.75, 0.75))

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
		n.frequency = 0.06
		n.fractal_octaves = 3
		_water_noise = NoiseTexture2D.new()
		_water_noise.noise = n
		_water_noise.seamless = true
		_water_noise.as_normal_map = true
		_water_noise.bump_strength = 6.0
		_water_noise.width = 256
		_water_noise.height = 256
	return _water_noise

## 연못/물길 물(파란 담수).
static func water_mat() -> ShaderMaterial:
	if _water == null:
		_water = _make_water()
	return _water

## 논에 댄 물 — 흙탕 갈색 + 잔잔한 거울 반사(실제 모내기 논).
static func paddy_water_mat() -> ShaderMaterial:
	if _paddy_water == null:
		_paddy_water = _make_water()
		_paddy_water.set_shader_parameter("shallow", Color(0.38, 0.31, 0.24))
		_paddy_water.set_shader_parameter("deep", Color(0.20, 0.16, 0.12))
		_paddy_water.set_shader_parameter("sparkle", 0.05)
		_paddy_water.set_shader_parameter("ripple", 0.12)
		_paddy_water.set_shader_parameter("mirror", 0.75)
	return _paddy_water

static var _muddy_water: ShaderMaterial
## 물길 도랑의 흙탕물(약한 흐름).
static func muddy_water_mat() -> ShaderMaterial:
	if _muddy_water == null:
		_muddy_water = _make_water()
		_muddy_water.set_shader_parameter("shallow", Color(0.44, 0.36, 0.27))
		_muddy_water.set_shader_parameter("deep", Color(0.26, 0.20, 0.15))
		_muddy_water.set_shader_parameter("sparkle", 0.1)
		_muddy_water.set_shader_parameter("ripple", 0.35)
		_muddy_water.set_shader_parameter("mirror", 0.45)
	return _muddy_water

static func _make_water() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("nmap", _water_normal())
	return m

# ---------- 초목 ----------
## 잔디/벼 공용 흔들림 재질(인스턴스 색 그대로 사용).
static func sway_mat() -> ShaderMaterial:
	if _sway == null:
		var sh := Shader.new()
		sh.code = SWAY_SHADER
		_sway = ShaderMaterial.new()
		_sway.shader = sh
	return _sway

## 벼 재질 — 잔디와 같은 셰이더 공유.
static func rice_mat() -> ShaderMaterial:
	return sway_mat()

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
