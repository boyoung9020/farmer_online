extends CanvasLayer
## 고용소 UI 패널. 버튼으로 노동자/군사를 고용한다.

var wm       # worker_manager
var farmer

var _panel: Panel
var _money_label: Label
var _font: FontFile

func _ready() -> void:
	layer = 5
	_font = _korean_font()
	_build()
	visible = false

func _build() -> void:
	var screen := get_viewport().get_visible_rect().size
	var size := Vector2(480, 440)

	_panel = Panel.new()
	_panel.size = size
	_panel.position = (screen - size) * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(28, 24)
	vb.size = Vector2(size.x - 56, size.y - 48)
	vb.add_theme_constant_override("separation", 16)
	_panel.add_child(vb)

	_add_label(vb, "🏪  고용소", 30)
	_money_label = _add_label(vb, "", 22)

	_add_button(vb, "농사 노동자 고용  (120원)\n밭을 자동으로 일굽니다", _on_buy_farmer)
	_add_button(vb, "군사 고용  (150원)\n집결지에서 적에 대비합니다", _on_buy_soldier)
	_add_button(vb, "새참 돌리기  (25원)\n막걸리·국수 새참 — 일꾼들이 45초간 빨라집니다", _on_saecham)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vb.add_child(spacer)

	_add_button(vb, "닫기 (ESC)", close)

func _add_label(parent: Node, text: String, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	if _font != null:
		l.add_theme_font_override("font", _font)
	parent.add_child(l)
	return l

func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 19)
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.pressed.connect(cb)
	parent.add_child(b)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if farmer != null:
		farmer.ui_open = true
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if farmer != null:
		farmer.ui_open = false

func _refresh() -> void:
	_money_label.text = "보유: %d원" % GameManager.money

func _on_buy_farmer() -> void:
	if wm != null:
		wm.hire_farmer()
	_refresh()

func _on_buy_soldier() -> void:
	if wm != null:
		wm.hire_soldier()
	_refresh()

func _on_saecham() -> void:
	if wm != null:
		wm.serve_saecham()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

func _korean_font() -> FontFile:
	for path in ["C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/gulim.ttc"]:
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			if f.load_dynamic_font(path) == OK:
				return f
	return null
