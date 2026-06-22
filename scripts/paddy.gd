extends RefCounted
## 논배미 한 개(벼농사 사실 모델).
## 생육 단계 + 물(수문) + 질소 + 병해충 + 도복 + 품질을 관리하고,
## 수확 시 품질에 따라 돈을 번다. 셀 메시들은 rice_field가 만들어 넘겨준다.

# 생육 단계
enum { FALLOW, PLOWED, TRANSPLANTED, TILLERING, HEADING, RIPENING, MATURE }
# 날씨 (rice_field가 update로 넘김)
const W_SUNNY := 0
const W_CLOUDY := 1
const W_RAIN := 2

const N_HIGH := 60.0          # 질소 과다(도복 위험) 기준
const BASE_PER_CELL := 7      # 셀당 기본 수익
const OVERRIPE := 28.0        # 완숙 후 이 시간 지나면 과숙(품질↓)

# 단계 소요 시간(초)
const T_TRANSPLANT := 14.0
const T_TILLER := 26.0
const T_HEADING := 18.0
const T_RIPEN := 24.0

# 품종: 0=조생종, 1=중만생종
const VARIETY_NAME := ["조생종", "중만생종"]
const VARIETY_PRICE := [0.9, 1.25]

var index := 0
var center := Vector3.ZERO
var min_x := 0.0
var max_x := 0.0
var min_z := 0.0
var max_z := 0.0
var grounds: Array = []   # MeshInstance3D
var crops: Array = []     # MeshInstance3D

var stage: int = FALLOW
var flooded := false
var nitrogen := 0.0
var fert_basal := false
var fert_tiller := false
var fert_panicle := false
var middry_done := false
var pest := false
var lodged := false
var variety := 1
var quality := 1.0
var stage_timer := 0.0

func contains(p: Vector3) -> bool:
	return p.x >= min_x and p.x <= max_x and p.z >= min_z and p.z <= max_z

# --- 매 프레임 갱신 ---
func update(delta: float, weather: int) -> void:
	if stage == FALLOW or stage == PLOWED:
		return

	stage_timer += delta

	# 물 스트레스: 이앙~출수~등숙 초반엔 담수 필요
	if (stage == TRANSPLANTED or stage == HEADING or stage == RIPENING) and not flooded:
		quality -= 0.02 * delta

	# 병해충: 방치하면 품질 하락 / 분얼·출수기 발생
	if pest:
		quality -= 0.015 * delta
	elif stage == TILLERING or stage == HEADING:
		if randf() < 0.05 * delta:   # 약 5%/초
			pest = true
			_paint()

	# 등숙기 맑은 날 = 품질 상승
	if stage == RIPENING and weather == W_SUNNY:
		quality += 0.012 * delta

	# 단계 전이
	match stage:
		TRANSPLANTED:
			if stage_timer >= T_TRANSPLANT:
				_advance(TILLERING)
		TILLERING:
			if stage_timer >= T_TILLER:
				_enter_heading()
		HEADING:
			if stage_timer >= T_HEADING:
				_advance(RIPENING)
		RIPENING:
			if stage_timer >= T_RIPEN:
				_advance(MATURE)
		MATURE:
			if stage_timer >= OVERRIPE:
				quality -= 0.01 * delta   # 과숙

	quality = clampf(quality, 0.15, 1.4)

func _advance(s: int) -> void:
	stage = s
	stage_timer = 0.0
	_paint()

func _enter_heading() -> void:
	# 분얼비 누락 패널티 / 도복 판정(질소 과다 + 중간물떼기 누락)
	if not fert_tiller:
		quality -= 0.08
	if nitrogen >= N_HIGH and not middry_done:
		lodged = true
		quality *= 0.5
	_advance(HEADING)

# --- 상황별 가능한 액션 목록 ({id,label}) ---
func actions() -> Array:
	var a: Array = []
	if pest:
		a.append({"id": "spray", "label": "방제 (병해충 제거)"})
	match stage:
		FALLOW:
			a.append({"id": "till", "label": "써레질(경운)"})
		PLOWED:
			if not flooded:
				a.append({"id": "water_on", "label": "물대기(담수)"})
			else:
				a.append({"id": "plant1", "label": "이앙: 중만생종 (수량↑)"})
				a.append({"id": "plant0", "label": "이앙: 조생종 (빠름)"})
		TRANSPLANTED:
			if not flooded:
				a.append({"id": "water_on", "label": "물대기(담수)"})
		TILLERING:
			if not fert_tiller:
				a.append({"id": "fert_t", "label": "분얼비 주기"})
			if not middry_done:
				a.append({"id": "water_off", "label": "중간물떼기"})
			elif not flooded:
				a.append({"id": "water_on", "label": "다시 물대기"})
		HEADING:
			if not fert_panicle:
				a.append({"id": "fert_p", "label": "이삭거름 주기"})
			if not flooded:
				a.append({"id": "water_on", "label": "물대기(담수)"})
		RIPENING:
			if flooded:
				a.append({"id": "water_off", "label": "낙수(물빼기) 준비"})
		MATURE:
			if flooded:
				a.append({"id": "water_off", "label": "낙수(물빼기)"})
			else:
				a.append({"id": "harvest", "label": "수확!"})
	return a

# 노동자 자동 관리: 지금 할 액션 id, 없으면 ""
func auto_next() -> String:
	if pest:
		return "spray"
	match stage:
		FALLOW:
			return "till"
		PLOWED:
			return "water_on" if not flooded else "plant1"
		TRANSPLANTED:
			return "water_on" if not flooded else ""
		TILLERING:
			if not fert_tiller:
				return "fert_t"
			if not middry_done:
				return "water_off"
			if not flooded and stage_timer > 12.0:
				return "water_on"
			return ""
		HEADING:
			if not fert_panicle:
				return "fert_p"
			if not flooded:
				return "water_on"
			return ""
		MATURE:
			return "water_off" if flooded else "harvest"
	return ""

# 액션 실행 → 결과 메시지
func do_action(id: String) -> String:
	match id:
		"till":
			_advance(PLOWED)
			return "써레질 완료 — 물을 대세요"
		"water_on":
			flooded = true
			_paint()
			return "물을 댔습니다 (담수)"
		"water_off":
			flooded = false
			if stage == TILLERING:
				middry_done = true
			_paint()
			return "물을 뺐습니다"
		"plant0", "plant1":
			variety = 0 if id == "plant0" else 1
			stage = TRANSPLANTED
			stage_timer = 0.0
			nitrogen += 30.0   # 밑거름
			fert_basal = true
			quality = 1.0
			_paint()
			return "모내기 완료! (%s, 밑거름)" % VARIETY_NAME[variety]
		"fert_t":
			fert_tiller = true
			nitrogen += 22.0
			return "분얼비 시비 완료"
		"fert_p":
			fert_panicle = true
			nitrogen += 10.0
			quality += 0.08
			return "이삭거름 시비 완료 (품질↑)"
		"spray":
			pest = false
			_paint()
			return "방제 완료"
		"harvest":
			var cells := grounds.size()
			var amount := int(round(cells * BASE_PER_CELL * quality * VARIETY_PRICE[variety]))
			GameManager.add_money(amount)
			var q := int(round(quality * 100.0))
			_reset()
			return "수확! 품질 %d%% → +%d원" % [q, amount]
	return ""

func _reset() -> void:
	stage = FALLOW
	flooded = false
	nitrogen = 0.0
	fert_basal = false
	fert_tiller = false
	fert_panicle = false
	middry_done = false
	pest = false
	lodged = false
	quality = 1.0
	stage_timer = 0.0
	_paint()

func stage_name() -> String:
	match stage:
		FALLOW: return "미경작"
		PLOWED: return "경운(써레질)"
		TRANSPLANTED: return "이앙·활착"
		TILLERING: return "분얼"
		HEADING: return "유수형성·출수"
		RIPENING: return "등숙"
		MATURE: return "완숙(수확 가능)"
	return "?"

func status_text() -> String:
	var lines := []
	lines.append("[논 %d] %s%s" % [index + 1, stage_name(), "  ⚠도복" if lodged else ""])
	lines.append("물: %s    질소: %.0f%s" % ["담수" if flooded else "마름", nitrogen, "  ⚠과다" if nitrogen >= N_HIGH else ""])
	lines.append("병해충: %s    품질: %d%%" % ["발생!" if pest else "정상", int(round(quality * 100.0))])
	if stage == TRANSPLANTED or stage == TILLERING or stage == HEADING or stage == RIPENING or stage == MATURE:
		lines.append("품종: %s" % VARIETY_NAME[variety])
	return "\n".join(lines)

# --- 시각 갱신 ---
func _paint() -> void:
	var gcol: Color
	var show_crop := false
	var grow := 0.3
	var ccol := Color(0.3, 0.8, 0.3)

	if flooded and stage != FALLOW:
		gcol = Color(0.28, 0.34, 0.42)   # 물 댄 논
	elif stage == FALLOW:
		gcol = Color(0.30, 0.45, 0.22)   # 미경작(풀)
	else:
		gcol = Color(0.38, 0.25, 0.14)   # 마른 흙

	match stage:
		TRANSPLANTED:
			show_crop = true; grow = 0.25; ccol = Color(0.4, 0.8, 0.35)
		TILLERING:
			show_crop = true; grow = 0.55; ccol = Color(0.25, 0.7, 0.25)
		HEADING:
			show_crop = true; grow = 0.9; ccol = Color(0.4, 0.7, 0.25)
		RIPENING:
			show_crop = true; grow = 1.0; ccol = Color(0.75, 0.7, 0.25)
		MATURE:
			show_crop = true; grow = 1.0; ccol = Color(0.92, 0.8, 0.2)
	if pest and show_crop:
		ccol = ccol.lerp(Color(0.7, 0.2, 0.15), 0.5)

	for g in grounds:
		(g.material_override as StandardMaterial3D).albedo_color = gcol
	for c in crops:
		c.visible = show_crop
		if show_crop:
			c.scale = Vector3(1.0, grow, 1.0)
			c.position.y = 0.1 + grow * 0.5
			c.rotation.z = 0.5 if lodged else 0.0   # 도복 시 쓰러짐
			(c.material_override as StandardMaterial3D).albedo_color = ccol
