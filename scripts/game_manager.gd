extends Node
## 전역 게임 상태 (autoload 싱글톤).
## 돈과 추후 점령전 상태를 보관한다.

signal money_changed(amount: int)

var money: int = 300  # 초기 자금 (대규모 농지에서 씨앗을 충분히 살 수 있게)

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

## 돈이 충분하면 차감하고 true, 부족하면 false.
func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true
