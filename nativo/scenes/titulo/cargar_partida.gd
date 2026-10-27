extends Control
## Cargar partida: los 9 slots (SaveManager). Enter o clic carga, Supr o clic derecho borra (con
## confirmación), Esc vuelve al título.

const RESOLUCION: Vector2i = Vector2i(640, 360)
const ESCENA_TITULO: String = "res://scenes/titulo/titulo.tscn"

var _ocupado: bool = false


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = RESOLUCION
	AudioManager.reproducir_intro()
	%Volver.pressed.connect(_volver)
	for n: int in range(1, SaveManager.SLOTS + 1):
		var b := Button.new()
		b.name = "Slot%d" % n
		b.theme_type_variation = &"BotonSlot"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(_cargar.bind(n))
		b.gui_input.connect(_entrada_slot.bind(n))
		b.mouse_entered.connect(b.grab_focus)
		%Slots.add_child(b)
	_actualizar()
	var primero: Button = %Slots.get_node("Slot%d" % maxi(SaveManager.mas_reciente(), 1))
	(primero if not primero.disabled else %Volver).grab_focus.call_deferred()


func _exit_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT


func _actualizar() -> void:
	for n: int in range(1, SaveManager.SLOTS + 1):
		var b: Button = %Slots.get_node("Slot%d" % n)
		var r: Dictionary = SaveManager.resumen(n)
		if r.is_empty():
			b.text = "SLOT %d\nVacío" % n
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
			continue
		b.disabled = false
		b.focus_mode = Control.FOCUS_ALL
		var lineas: PackedStringArray = [
			"SLOT %d · %s" % [n, str(r.get("nombre", ""))],
			InfoPartida.nombre_mapa(str(r.get("mapa", ""))),
			"%s · %d Pokémon" % [InfoPartida.tiempo(int(r.get("tiempo", 0))), r.get("equipo", []).size()],
			InfoPartida.fecha(int(r.get("guardado", 0))) + (" · respaldo" if r.get("respaldo") else ""),
		]
		b.text = "\n".join(lineas)
		b.tooltip_text = InfoPartida.equipo(r.get("equipo", []))


func _entrada_slot(evento: InputEvent, n: int) -> void:
	var borrar: bool = (evento is InputEventKey and evento.pressed and evento.physical_keycode == KEY_DELETE) \
		or (evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_RIGHT)
	if borrar and not _ocupado:
		get_viewport().set_input_as_handled()
		_borrar(n)


func _unhandled_input(evento: InputEvent) -> void:
	if _ocupado:
		return
	if evento.is_action_pressed("ui_cancel") or (evento is InputEventKey and evento.pressed and evento.physical_keycode == KEY_X):
		get_viewport().set_input_as_handled()
		_volver()
	elif evento is InputEventKey and evento.pressed and evento.physical_keycode == KEY_Z:
		get_viewport().set_input_as_handled()
		var foco: Control = get_viewport().gui_get_focus_owner()
		if foco is Button:
			foco.pressed.emit()


func _cargar(n: int) -> void:
	if _ocupado:
		return
	_ocupado = true
	var r := SaveManager.cargar(n)
	if not r.ok:
		await ModalMenu.mensaje(self, r.error)
		_ocupado = false
		_actualizar()
		return
	if r.de_respaldo:
		await ModalMenu.mensaje(self, "La partida estaba dañada: se cargó su copia de respaldo.")
	if not SceneManager.existe_mapa(GameState.mapa_actual):
		await ModalMenu.mensaje(self, "El mapa %s no está extraído (tools/extraer.py --mapas todos)." % GameState.mapa_actual)
		_ocupado = false
		return
	AudioManager.detener_musica()
	SceneManager.ir_a_mapa(GameState.mapa_actual, GameState.posicion_jugador, GameState.mira)


func _borrar(n: int) -> void:
	_ocupado = true
	if await ModalMenu.preguntar(self, "Slot %d: %s" % [n, Textos.linea("txt_menu", 67)], "Borrar", "Cancelar"):
		SaveManager.borrar(n)
		_actualizar()
	_ocupado = false
	var b: Button = %Slots.get_node("Slot%d" % n)
	if not b.disabled:
		b.grab_focus()
	else:
		var siguiente: int = SaveManager.mas_reciente()
		if siguiente > 0:
			(%Slots.get_node("Slot%d" % siguiente) as Button).grab_focus()
		else:
			%Volver.grab_focus()


func _volver() -> void:
	get_tree().change_scene_to_file(ESCENA_TITULO)
