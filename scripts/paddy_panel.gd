extends CanvasLayer
## 논 관리 패널. 논 안에서 E로 열며, 현재 단계에 맞는 액션 버튼을 보여준다.

var farmer
var hud

var _paddy
var _panel: Panel
var _status: Label
var _btns: VBoxContainer
var _font: FontFile

func _ready() -> void:
	layer = 5
	_font = _korean_font()
	_build()
	visible = false

func _build() -> void:
	var screen := get_viewport().get_visible_rect().size
	var size := Vector2(520, 420)

	_panel = Panel.new()
	_panel.size = size
	_panel.position = (screen - size) * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(28, 24)
	vb.size = Vector2(size.x - 56, size.y - 48)
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	_add_label(vb, "🌾  논 관리", 28)
	_status = _add_label(vb, "", 19)

	_btns = VBoxContainer.new()
	_btns.add_theme_constant_override("separation", 8)
	vb.add_child(_btns)

func open(paddy) -> void:
	_paddy = paddy
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if farmer != null:
		farmer.ui_open = true
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if farmer != null:
		farmer.ui_open = false

func _refresh() -> void:
	if _paddy == null:
		return
	_status.text = _paddy.status_text()

	for ch in _btns.get_children():
		ch.queue_free()

	for act in _paddy.actions():
		_add_button(_btns, act["label"], act["id"])

	var close_btn := Button.new()
	close_btn.text = "닫기 (ESC)"
	close_btn.custom_minimum_size = Vector2(0, 44)
	if _font != null:
		close_btn.add_theme_font_override("font", _font)
	close_btn.pressed.connect(close)
	_btns.add_child(close_btn)

func _on_action(id: String) -> void:
	if _paddy == null:
		return
	var msg: String = _paddy.do_action(id)
	if hud != null and msg != "":
		hud.flash(msg)
	_refresh()

func _add_label(parent: Node, text: String, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	if _font != null:
		l.add_theme_font_override("font", _font)
	parent.add_child(l)
	return l

func _add_button(parent: Node, text: String, id: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 18)
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.pressed.connect(_on_action.bind(id))
	parent.add_child(b)

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
