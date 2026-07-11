extends Node
## 아군 고용 관리. 상점 UI에서 hire_farmer / hire_soldier 호출.

const UnitScript := preload("res://scripts/unit.gd")

const FARMER_COST := 120
const SOLDIER_COST := 150
const SAECHAM_COST := 25                  # 새참(막걸리+국수) 값
const SAECHAM_TIME := 45.0                # 새참 효과 시간(초)
const SAECHAM_SPEED := 6.8                # 새참 먹은 일꾼 속도(기본 4.2)
const RALLY := Vector3(60, 0, 40)        # 군사 집결지
const SPAWN_BASE := Vector3(-10, 1.0, 30) # 고용 시 등장 위치

var field
var hud

var _total := 0
var _saecham_t := 0.0                     # 남은 새참 효과 시간

func _process(delta: float) -> void:
	if hud != null:
		hud.set_workers(
			get_tree().get_nodes_in_group("player_farmers").size(),
			get_tree().get_nodes_in_group("player_soldiers").size())

	# 새참 효과 — 걸려 있는 동안 모든 농사 일꾼이 빠르게 움직인다(새 고용자 포함)
	if _saecham_t > 0.0:
		_saecham_t -= delta
		var boosted := _saecham_t > 0.0
		for u in get_tree().get_nodes_in_group("player_farmers"):
			u.move_speed = SAECHAM_SPEED if boosted else u.SPEED
		if not boosted and hud != null:
			hud.flash("새참 시간이 끝났습니다. 일꾼들이 평소 속도로 돌아갑니다.")

## 새참 돌리기(두레 풍습) — 막걸리와 국수를 내면 일꾼들이 신나게 일한다.
func serve_saecham() -> bool:
	if get_tree().get_nodes_in_group("player_farmers").is_empty():
		if hud != null:
			hud.flash("새참을 먹을 일꾼이 없습니다 (먼저 고용하세요)")
		return false
	if not GameManager.spend_money(SAECHAM_COST):
		if hud != null:
			hud.flash("돈 부족 — 새참 %d원" % SAECHAM_COST)
		return false
	_saecham_t = SAECHAM_TIME
	if hud != null:
		hud.flash("새참 돌렸습니다! 막걸리 한 사발에 일꾼들이 신났어요 (%d초)" % int(SAECHAM_TIME))
	return true

func hire_farmer() -> bool:
	return _hire(UnitScript.ROLE_FARMER, FARMER_COST, "농사 노동자")

func hire_soldier() -> bool:
	return _hire(UnitScript.ROLE_SOLDIER, SOLDIER_COST, "군사")

func _hire(role: int, cost: int, label: String) -> bool:
	if not GameManager.spend_money(cost):
		if hud != null:
			hud.flash("돈 부족 — %s %d원" % [label, cost])
		return false

	var u := UnitScript.new()
	u.faction = UnitScript.FACTION_PLAYER
	u.role = role
	u.field = field
	u.rally = RALLY
	@warning_ignore("integer_division")
	var row := _total / 5
	u.position = SPAWN_BASE + Vector3((_total % 5) * 1.6, 0, row * 1.6)
	add_child(u)
	_total += 1

	if hud != null:
		hud.flash("%s 고용! (-%d원)" % [label, cost])
	return true
