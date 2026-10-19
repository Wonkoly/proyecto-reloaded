class_name DialogoModal
extends CanvasLayer
## Cuadro modal como los del original (GetDialogString, GetDialogNumber, ShowDialogQuestion,
## ShowDialogMessage): pausa el juego hasta que se responde. Se usa con await:
##   var texto: String = await dialogo.pedir_texto("Introduce un Cheat...", 13)

signal _respondido(valor: Variant)

var _caja: PanelContainer
var _texto: Label
var _entrada: LineEdit
var _botones: HBoxContainer
var _modo: String = ""
var _pausa_previa: bool = false


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	_caja = PanelContainer.new()
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.08, 0.09, 0.14, 0.95)
	fondo.border_color = Color(0.85, 0.85, 0.9)
	fondo.set_border_width_all(1)
	fondo.set_content_margin_all(6)
	_caja.add_theme_stylebox_override("panel", fondo)
	centro.add_child(_caja)
	var v := VBoxContainer.new()
	_caja.add_child(v)
	_texto = Label.new()
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_texto)
	_entrada = LineEdit.new()
	_entrada.text_submitted.connect(func(t: String) -> void: _responder(t))
	v.add_child(_entrada)
	_botones = HBoxContainer.new()
	_botones.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_botones)
	visible = false


## ShowDialogMessage: devuelve true si se canceló (para cortar listas largas, como el original).
func mensaje(texto: String) -> bool:
	return await _mostrar("mensaje", texto)


func pedir_texto(titulo: String, maximo: int) -> String:
	_entrada.max_length = maximo
	return str(await _mostrar("texto", titulo))


## Devuelve -1 si se cancela o se deja vacío.
func pedir_numero(titulo: String, minimo: int, maximo: int) -> int:
	_entrada.max_length = str(maximo).length()
	var t: String = str(await _mostrar("numero", titulo))
	return clampi(t.to_int(), minimo, maximo) if t.is_valid_int() else -1


func preguntar(texto: String) -> bool:
	return await _mostrar("pregunta", texto) == true


func _mostrar(modo: String, texto: String) -> Variant:
	_modo = modo
	_texto.text = texto.replace("#", "\n").replace("@", "\n")
	_entrada.visible = modo in ["texto", "numero"]
	_entrada.clear()
	for b: Node in _botones.get_children():
		b.queue_free()
	if modo == "pregunta":
		for par: Array in [["Sí", true], ["No", false]]:
			var b := Button.new()
			b.text = par[0]
			b.pressed.connect(_responder.bind(par[1]))
			_botones.add_child(b)
	var tam: int = maxi(7, int(get_viewport().get_visible_rect().size.y / 18.0))
	for c: Control in [_texto, _entrada]:
		c.add_theme_font_size_override("font_size", tam)
	_caja.custom_minimum_size.x = get_viewport().get_visible_rect().size.x * 0.7
	_pausa_previa = get_tree().paused
	get_tree().paused = true
	visible = true
	await get_tree().process_frame
	if _entrada.visible:
		_entrada.grab_focus()
	elif _botones.get_child_count() > 0:
		(_botones.get_child(0) as Button).grab_focus()
	var valor: Variant = await _respondido
	visible = false
	get_tree().paused = _pausa_previa
	return valor


func _responder(valor: Variant) -> void:
	_respondido.emit(valor)


func _unhandled_input(evento: InputEvent) -> void:
	if not visible:
		return
	if evento.is_action_pressed("ui_cancel"):
		_responder(true if _modo == "mensaje" else (false if _modo == "pregunta" else ""))
		get_viewport().set_input_as_handled()
	elif _modo == "mensaje" and (evento.is_action_pressed("ui_accept") or evento.is_action_pressed("interactuar")):
		_responder(false)
		get_viewport().set_input_as_handled()
