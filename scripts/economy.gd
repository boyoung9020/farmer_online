extends RefCounted
## 독립 경제(돈) 객체. 적 진영처럼 GameManager(플레이어)와 분리된 자금이 필요할 때 사용.
## farm_field가 기대하는 인터페이스(money / add_money / spend_money)를 그대로 따른다.

var money: int = 0

func _init(start_money: int = 0) -> void:
	money = start_money

func add_money(amount: int) -> void:
	money += amount

## 돈이 충분하면 차감하고 true, 부족하면 false.
func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	return true
