extends Node
## Consola de desarrollo (F1), overlay de estado (F3) y dibujo de colisiones/zonas/salidas (F4).
## Solo existe en builds de depuración: en un export de release se elimina al arrancar.
## Para agregar un comando: DevConsole.registrar(nombre, descripción, uso, callable) — el callable
## recibe los argumentos (PackedStringArray) y devuelve el texto a mostrar.

class Comando:
	var nombre: String
	var descripcion: String
	var uso: String
	var accion: Callable
	## (indice_argumento: int, texto: String) -> PackedStringArray con candidatos para Tab.
	var autocompletar: Callable

const MAX_HISTORIAL: int = 50

var _comandos: Dictionary[String, Comando] = {}
var _historial: PackedStringArray = []
var _pos_historial: int = 0
var _capa: CanvasLayer
var _panel: PanelContainer
var _log: RichTextLabel
var _entrada: LineEdit
var _overlay: Label
var _dibujo: Node2D
var _overlay_activo: bool = false
var _dibujo_activo: bool = false
var _pausa_previa: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crear_interfaz()
	ComandosDev.registrar_todos(self)


func registrar(nombre: String, descripcion: String, uso: String, accion: Callable,
		autocompletar: Callable = Callable()) -> void:
	var c := Comando.new()
	c.nombre = nombre
	c.descripcion = descripcion
	c.uso = uso
	c.accion = accion
	c.autocompletar = autocompletar
	_comandos[nombre] = c


func comandos() -> Array[Comando]:
	var lista: Array[Comando] = []
	lista.assign(_comandos.values())
	lista.sort_custom(func(a: Comando, b: Comando) -> bool: return a.nombre < b.nombre)
	return lista


func imprimir(texto: String) -> void:
	_log.append_text(texto + "\n")


func ejecutar(linea: String) -> void:
	linea = linea.strip_edges()
	if linea == "":
		return
	imprimir("[color=#8cf]> %s[/color]" % linea)
	var partes: PackedStringArray = linea.split(" ", false)
	var nombre: String = partes[0].to_lower()
	if nombre not in _comandos:
		imprimir("[color=#f88]No existe el comando \"%s\". Escribe ayuda.[/color]" % nombre)
		return
	var resultado: Variant = _comandos[nombre].accion.call(partes.slice(1))
	if resultado is String and resultado != "":
		imprimir(resultado)


func abierta() -> bool:
	return _panel.visible


func _input(evento: InputEvent) -> void:
	var tecla: InputEventKey = evento as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_F1:
			_alternar_consola()
		KEY_F3:
			_overlay_activo = not _overlay_activo
			_overlay.visible = _overlay_activo
			_ajustar_tamano()
		KEY_F4:
			_dibujo_activo = not _dibujo_activo
		_:
			if abierta():
				_tecla_consola(tecla)
			return
	get_viewport().set_input_as_handled()


func _tecla_consola(tecla: InputEventKey) -> void:
	match tecla.physical_keycode:
		KEY_UP, KEY_DOWN:
			if _historial.is_empty():
				return
			_pos_historial = clampi(_pos_historial + (-1 if tecla.physical_keycode == KEY_UP else 1), 0, _historial.size())
			_entrada.text = _historial[_pos_historial] if _pos_historial < _historial.size() else ""
			_entrada.caret_column = _entrada.text.length()
		KEY_TAB:
			_autocompletar()
		KEY_ESCAPE:
			_alternar_consola()
		_:
			return
	get_viewport().set_input_as_handled()


func _alternar_consola() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_pausa_previa = get_tree().paused
		get_tree().paused = true
		_ajustar_tamano()
		_entrada.grab_focus()
	else:
		get_tree().paused = _pausa_previa
		_entrada.release_focus()


func _on_entrada(texto: String) -> void:
	_entrada.clear()
	if texto.strip_edges() != "":
		_historial.append(texto)
		if _historial.size() > MAX_HISTORIAL:
			_historial.remove_at(0)
	_pos_historial = _historial.size()
	ejecutar(texto)


## Tab: completa el comando o, si el comando lo permite, su argumento (p. ej. nombres de mapa).
func _autocompletar() -> void:
	var texto: String = _entrada.text
	var partes: PackedStringArray = texto.split(" ")
	var candidatos: PackedStringArray = []
	var actual: String = partes[partes.size() - 1]
	if partes.size() == 1:
		for n: String in _comandos:
			if n.begins_with(actual.to_lower()):
				candidatos.append(n)
	elif partes[0].to_lower() in _comandos and _comandos[partes[0].to_lower()].autocompletar.is_valid():
		candidatos = _comandos[partes[0].to_lower()].autocompletar.call(partes.size() - 2, actual)
	if candidatos.is_empty():
		return
	candidatos.sort()
	var comun: String = candidatos[0]
	for c: String in candidatos:
		while not c.to_lower().begins_with(comun.to_lower()):
			comun = comun.left(comun.length() - 1)
	if candidatos.size() > 1:
		imprimir("  ".join(candidatos.slice(0, 40)) + ("  …" if candidatos.size() > 40 else ""))
	partes[partes.size() - 1] = candidatos[0] + " " if candidatos.size() == 1 else comun
	_entrada.text = " ".join(partes)
	_entrada.caret_column = _entrada.text.length()


func _process(_delta: float) -> void:
	if _overlay_activo:
		_overlay.text = _texto_overlay()
	_actualizar_dibujo()


func _texto_overlay() -> String:
	var j: Jugador = jugador()
	var lineas: PackedStringArray = [
		"FPS %d" % Engine.get_frames_per_second(),
		"Mapa %s" % (GameState.mapa_actual if j else str(get_tree().current_scene.name if get_tree().current_scene else "-")),
		"Pos %s" % (str(j.global_position.round()) if j else "-"),
		"Historia %s" % str(GameState.historia),
		"Equipo %d" % GameState.equipo.size(),
	]
	return "\n".join(lineas)


## El jugador del overworld si la escena actual es un mapa.
func jugador() -> Jugador:
	var escena: Node = get_tree().current_scene
	return escena.get_node_or_null("Objetos/Jugador") as Jugador if escena is Mapa else null


func _actualizar_dibujo() -> void:
	var escena: Node = get_tree().current_scene
	var quiere: bool = _dibujo_activo and escena is Mapa
	if quiere and (_dibujo == null or not is_instance_valid(_dibujo) or _dibujo.get_parent() != escena):
		_dibujo = DibujoDebug.new()
		escena.add_child(_dibujo)
	elif not quiere and _dibujo and is_instance_valid(_dibujo):
		_dibujo.queue_free()
		_dibujo = null


func _crear_interfaz() -> void:
	_capa = CanvasLayer.new()
	_capa.layer = 120
	add_child(_capa)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.anchor_bottom = 0.6
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	fondo.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", fondo)
	_panel.visible = false
	_capa.add_child(_panel)
	var caja := VBoxContainer.new()
	_panel.add_child(caja)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.focus_mode = Control.FOCUS_NONE
	caja.add_child(_log)
	_entrada = LineEdit.new()
	_entrada.placeholder_text = "comando (ayuda, Tab completa, ↑/↓ historial, F1 cierra)"
	_entrada.text_submitted.connect(_on_entrada)
	caja.add_child(_entrada)
	_overlay = Label.new()
	_overlay.position = Vector2(4, 4)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 3)
	_overlay.visible = false
	_capa.add_child(_overlay)
	imprimir("Consola de desarrollo. Escribe [b]ayuda[/b] para ver los comandos.")


## La resolución cambia según la escena (320×180 en el overworld, 576×324 en batalla).
func _ajustar_tamano() -> void:
	var tam: int = maxi(7, int(get_window().content_scale_size.y / 20.0))
	for c: Control in [_log, _entrada, _overlay]:
		c.add_theme_font_size_override("font_size", tam)
		c.add_theme_font_size_override("normal_font_size", tam)
		c.add_theme_font_size_override("bold_font_size", tam)
	_overlay.add_theme_font_size_override("font_size", tam)
