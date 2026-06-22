extends Node
## 아군 고용 관리. 상점 UI에서 hire_farmer / hire_soldier 호출.

const UnitScript := preload("res://scripts/unit.gd")

const FARMER_COST := 120
const SOLDIER_COST := 150
const RALLY := Vector3(60, 0, 40)        # 군사 집결지
const SPAWN_BASE := Vector3(-10, 1.0, 30) # 고용 시 등장 위치

var rice
var hud

var _total := 0

func _process(_delta: float) -> void:
	if hud != null:
		hud.set_workers(
			get_tree().get_nodes_in_group("player_farmers").size(),
			get_tree().get_nodes_in_group("player_soldiers").size())

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
	u.rice = rice
	u.rally = RALLY
	@warning_ignore("integer_division")
	var row := _total / 5
	u.position = SPAWN_BASE + Vector3((_total % 5) * 1.6, 0, row * 1.6)
	add_child(u)
	_total += 1

	if hud != null:
		hud.flash("%s 고용! (-%d원)" % [label, cost])
	return true
