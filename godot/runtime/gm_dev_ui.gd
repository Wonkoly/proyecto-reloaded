## Developer window (main thread): game info, forced save, turbo, room warp and a command console.
## Runs as a separate OS window so it isn't scaled down with the 320x180 game viewport.
extends Window

var _info: Label
var _turbo: OptionButton
var _filter: LineEdit
var _rooms: ItemList
var _wx: SpinBox
var _wy: SpinBox
var _log: TextEdit
var _cmd: LineEdit
var _history: PackedStringArray = []
var _hist_i := 0
var _log_cursor := 0

const TURBOS := [1.0, 2.0, 4.0, 8.0]

func _init() -> void:
	title = "Proyecto Reloaded — Developer"
	size = Vector2i(460, 640)
	position = Vector2i(40, 40)
	close_requested.connect(hide)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 8)
	add_child(root)
	var box := VBoxContainer.new()
	root.add_child(box)

	_info = Label.new()
	_info.text = "cargando..."
	box.add_child(_info)

	var row := HBoxContainer.new()
	box.add_child(row)
	var save := Button.new()
	save.text = "Guardar ahora"
	save.tooltip_text = "Guarda sin las restricciones del juego (también: comando 'guardar')"
	save.pressed.connect(func(): GMDev.push("guardar"))
	row.add_child(save)
	var tl := Label.new()
	tl.text = "   Turbo:"
	row.add_child(tl)
	_turbo = OptionButton.new()
	for t in TURBOS:
		_turbo.add_item("x%d" % t)
	_turbo.tooltip_text = "Velocidad del juego. Mantener Tab en el juego = x4"
	_turbo.item_selected.connect(func(i): GMDev.push("turbo %s" % TURBOS[i]))
	row.add_child(_turbo)

	box.add_child(HSeparator.new())
	var wl := Label.new()
	wl.text = "Ir a un mapa (doble clic o «Ir»):"
	box.add_child(wl)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filtrar mapas…"
	_filter.text_changed.connect(func(_t): _fill_rooms())
	box.add_child(_filter)
	_rooms = ItemList.new()
	_rooms.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms.custom_minimum_size.y = 160
	_rooms.item_activated.connect(func(_i): _warp())
	box.add_child(_rooms)
	var wrow := HBoxContainer.new()
	box.add_child(wrow)
	_wx = _spin(wrow, "x")
	_wy = _spin(wrow, "y")
	var go := Button.new()
	go.text = "Ir"
	go.pressed.connect(_warp)
	wrow.add_child(go)
	var hint := Label.new()
	hint.text = "(x/y = -1: centro del mapa)"
	wrow.add_child(hint)

	box.add_child(HSeparator.new())
	_log = TextEdit.new()
	_log.editable = false
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 160
	_log.text = "Escribe «ayuda» para ver los comandos.\n"
	box.add_child(_log)
	_cmd = LineEdit.new()
	_cmd.placeholder_text = "comando (escribe ayuda)"
	_cmd.text_submitted.connect(_submit)
	_cmd.gui_input.connect(_cmd_input)
	box.add_child(_cmd)

func _spin(parent: Control, label: String) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = -1
	s.max_value = 100000
	s.value = -1
	parent.add_child(s)
	return s

func _fill_rooms() -> void:
	_rooms.clear()
	var f := _filter.text.to_lower()
	var names: Array = GMAssets.room_names
	for i in names.size():
		if names[i] != null and (f == "" or str(names[i]).to_lower().contains(f)):
			_rooms.add_item("%d  %s" % [i, names[i]])
			_rooms.set_item_metadata(_rooms.item_count - 1, i)

func _warp() -> void:
	var sel := _rooms.get_selected_items()
	if sel.is_empty():
		return
	var r: int = _rooms.get_item_metadata(sel[0])
	if _wx.value >= 0 and _wy.value >= 0:
		GMDev.push("tp %d %d %d" % [r, _wx.value, _wy.value])
	else:
		GMDev.push("tp %d" % r)

func _submit(t: String) -> void:
	if t.strip_edges() == "":
		return
	GMDev.push(t)
	_history.append(t)
	_hist_i = _history.size()
	_cmd.clear()

func _cmd_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed) or _history.is_empty():
		return
	if e.keycode == KEY_UP:
		_hist_i = maxi(_hist_i - 1, 0)
	elif e.keycode == KEY_DOWN:
		_hist_i = mini(_hist_i + 1, _history.size())
	else:
		return
	_cmd.text = _history[_hist_i] if _hist_i < _history.size() else ""
	_cmd.caret_column = _cmd.text.length()
	_cmd.accept_event()

func _process(_delta: float) -> void:
	if _rooms.item_count == 0 and not GMAssets.room_names.is_empty():
		_fill_rooms()
	var r := GMDev.lines_since(_log_cursor)
	_log_cursor = r[1]
	for line in r[0]:
		_log.text += line + "\n"
		_log.scroll_vertical = _log.get_line_count()
	var d := GMDev.info()
	if not d.is_empty():
		var pos := "x=%d y=%d" % [d.x, d.y] if not is_nan(d.x) else "sin protagonista"
		_info.text = "Mapa: %s (%d)\n%s   instancias: %d\n%.0f fps   turbo x%s" % [
			d.room_name, d.room, pos, d.instances, d.fps, GMDev.turbo]
