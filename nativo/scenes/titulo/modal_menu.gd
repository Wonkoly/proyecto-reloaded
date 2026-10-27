class_name ModalMenu
extends Control
## Cuadro modal de los menús nuevos (título, cargar partida), con el tema tema_menu.tres:
##   if await ModalMenu.preguntar(self, "¿Seguro?"): ...
##   await ModalMenu.mensaje(self, "Listo")
##   var nombre: String = await ModalMenu.pedir_texto(self, "Tu nombre", "Texto", "Ash", 12)  # "" si cancela
## Enter acepta el botón elegido, Esc cancela; ←/→ o Tab cambian de botón.

const TEMA: String = "res://scenes/titulo/tema_menu.tres"

signal _respondido(valor: Variant)

var _entrada: LineEdit


static func preguntar(desde: Node, texto: String, si: String = "Sí", no: String = "No") -> bool:
	return await _abrir(desde, "", texto, [[si, true], [no, false]], null) == true


static func mensaje(desde: Node, texto: String, titulo: String = "") -> void:
	await _abrir(desde, titulo, texto, [["Aceptar", true]], null)


## Devuelve el texto escrito (sin espacios de sobra), o "" si se cancela.
static func pedir_texto(desde: Node, titulo: String, texto: String, inicial: String, maximo: int,
		aceptar: String = "Aceptar", cancelable: bool = true) -> String:
	var entrada := LineEdit.new()
	entrada.text = inicial
	entrada.max_length = maximo
	entrada.placeholder_text = "Escribe aquí"
	var botones: Array = [[aceptar, true]]
	if cancelable:
		botones.append(["Cancelar", false])
	var valor: Variant = await _abrir(desde, titulo, texto, botones, entrada)
	return entrada.text.strip_edges() if valor == true else ""


static func _abrir(desde: Node, titulo: String, texto: String, botones: Array, entrada: LineEdit) -> Variant:
	var m := ModalMenu.new()
	m.theme = load(TEMA)
	m._armar(titulo, texto, botones, entrada)
	desde.add_child(m)
	var valor: Variant = await m._respondido
	m.queue_free()
	return valor


func _armar(titulo: String, texto: String, botones: Array, entrada: LineEdit) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(velo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Modal"
	panel.custom_minimum_size.x = 300
	centro.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	if titulo != "":
		var t := Label.new()
		t.text = titulo.to_upper()
		t.theme_type_variation = &"EtiquetaTitulo"
		v.add_child(t)
	var l := Label.new()
	l.text = texto.replace("#", "\n").replace("@", "\n")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	v.add_child(l)
	_entrada = entrada
	if entrada:
		entrada.text_submitted.connect(func(_t: String) -> void: _responder(true))
		v.add_child(entrada)
	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.add_theme_constant_override("separation", 8)
	v.add_child(fila)
	for i: int in botones.size():
		var b := Button.new()
		b.text = botones[i][0]
		b.custom_minimum_size.x = 84
		if i == 0:
			b.theme_type_variation = &"BotonPrincipal"
		b.pressed.connect(_responder.bind(botones[i][1]))
		fila.add_child(b)


func _ready() -> void:
	AudioManager.efecto_ui("snd_click")
	await get_tree().process_frame
	if _entrada:
		_entrada.grab_focus()
		_entrada.caret_column = _entrada.text.length()
	else:
		var fila: Node = find_children("*", "HBoxContainer", true, false)[0]
		(fila.get_child(0) as Button).grab_focus()


func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_responder(false)
	elif evento is InputEventKey or evento is InputEventMouseButton:
		get_viewport().set_input_as_handled()  # nada llega a la pantalla de atrás


func _responder(valor: Variant) -> void:
	_respondido.emit(valor)
