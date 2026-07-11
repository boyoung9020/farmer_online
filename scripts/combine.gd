extends "res://scripts/transplanter.gd"
## 콤바인(수확기) — 이앙기 베이스를 상속. 익은 벼 위로 달리면 전방 헤더 폭만큼 수확한다.

func _init() -> void:
	model_path = "res://assets/models/combine.glb"
	max_speed = 6.5
	work_width = 4.5
	work_mode = 3            # FarmField.MODE_HARVEST
	work_offset = -1.6       # 전방 예취부에서 벤다
	mode_label = "콤바인 — 익은 벼 위로 달리면 수확합니다"
