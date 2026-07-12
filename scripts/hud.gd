extends CanvasLayer
class_name HUD
## 화면 UI: 돈, 상태(도보/작업 모드), 노동자 수, 메시지, 조작 안내.
## 한글 표시를 위해 시스템 폰트(맑은 고딕)를 불러와 적용한다.

var _money_label: Label
var _mode_label: Label
var _workers_label: Label
var _enemies_label: Label
var _msg_label: Label
var _help_label: Label
var _time_label: Label
var _msg_timer := 0.0
var _font: FontFile

func _ready() -> void:
	_load_korean_font()

	_money_label = _make_label(Vector2(20, 16), 30)
	_mode_label = _make_label(Vector2(20, 56), 22)
	_workers_label = _make_label(Vector2(20, 90), 22)
	_enemies_label = _make_label(Vector2(20, 122), 22)
	_msg_label = _make_label(Vector2(20, 158), 20)
	_time_label = _make_label(Vector2(20, 190), 18)
	_help_label = _make_label(Vector2(20, 690), 16)
	_help_label.text = "WASD: 이동   휠: 줌   우클릭: 회전   C: 물길   B: 논   R: 허수아비   V: 비닐하우스   F: 탈것(트랙터/이앙기)   E: 고용소(새참)   1~4: 작업모드   M: 지도"

	set_mode("도보")
	set_workers(0, 0)
	set_enemies(0)
	GameManager.money_changed.connect(_on_money_changed)
	_update_money(GameManager.money)

func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""

func set_mode(mode_name: String) -> void:
	_mode_label.text = "상태: %s" % mode_name

func set_time(t: String) -> void:
	_time_label.text = "🕐 %s" % t

func set_workers(farmers: int, soldiers: int) -> void:
	_workers_label.text = "아군  농사 %d / 군사 %d" % [farmers, soldiers]

func set_enemies(n: int) -> void:
	_enemies_label.text = "적군: %d" % n
	_enemies_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5) if n > 0 else Color.WHITE)

func flash(text: String) -> void:
	_msg_label.text = text
	_msg_timer = 3.0

func _on_money_changed(amount: int) -> void:
	_update_money(amount)

func _update_money(amount: int) -> void:
	_money_label.text = "돈: %d원" % amount

func _make_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	if _font != null:
		l.add_theme_font_override("font", _font)
	add_child(l)
	return l

func _load_korean_font() -> void:
	var candidates := [
		"C:/Windows/Fonts/malgun.ttf",
		"C:/Windows/Fonts/malgunbd.ttf",
		"C:/Windows/Fonts/gulim.ttc",
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			var err := f.load_dynamic_font(path)
			if err == OK:
				_font = f
				return
	push_warning("한글 폰트를 찾지 못했습니다. 한글이 깨질 수 있습니다.")
