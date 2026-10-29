class_name MenuLista
extends CanvasLayer
## Lista para elegir (GetSelection, la tienda, la venta, la mochila), con la fuente y los colores de
## los cuadros del original. El juego queda congelado mientras está abierta.
##   var i: int = await MenuLista.elegir(self, "¿Qué deseas?", [{"texto": "Comprar"}, ...])
## Filas: {"texto", "derecha" (p. ej. el precio), "desc" (abajo), "activo" (false = gris)}.
## Opciones: "pie" (texto arriba a la derecha, p. ej. el dinero), "ancho" (de la lista, en px), "pestanas" (títulos de bolsillos:
## ←/→ cambian y elegir() devuelve IZQUIERDA/DERECHA), "inicial".
## ↑/↓ mueven, Z o Enter eligen (devuelve el índice), X o Esc cancelan (devuelve -1).

const IZQUIERDA: int = -10
const DERECHA: int = -11
const FILAS_VISIBLES: int = 7
const ALTO_FILA: float = 14.0
const COLOR_FONDO: Color = Color(0.06, 0.06, 0.1, 0.92)
const COLOR_BORDE: Color = Color(0.85, 0.85, 0.9)
const COLOR_TEXTO: Color = Color.WHITE
const COLOR_ELEGIDO: Color = Color8(255, 242, 0)
const COLOR_GRIS: Color = Color(0.55, 0.55, 0.6)

signal _respondido(valor: int)

var _titulo: String = ""
var _filas: Array = []
var _opciones: Dictionary = {}
var _sel: int = 0
var _inicio: int = 0
var _fuente: Font
var _lienzo: Node2D
# Selector de cantidad: _maximo > 0 lo activa.
var _maximo: int = 0
var _cantidad: int = 1
var _precio: int = 0


static func elegir(desde: Node, titulo: String, filas: Array, opciones: Dictionary = {}) -> int:
	var m := MenuLista.new()
	m._titulo = titulo
	m._filas = filas
	m._opciones = opciones
	m._sel = clampi(int(opciones.get("inicial", 0)), 0, maxi(0, filas.size() - 1))
	return await m._abrir(desde)


## Cuántas unidades (1..maximo): ↑/↓ de a 1, ←/→ de a 10. 0 si se cancela.
static func cantidad(desde: Node, titulo: String, maximo: int, precio_unidad: int = 0) -> int:
	if maximo <= 0:
		return 0
	var m := MenuLista.new()
	m._titulo = titulo
	m._maximo = maximo
	m._precio = precio_unidad
	return await m._abrir(desde)


func _abrir(desde: Node) -> int:
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(self)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	var valor: int = await _respondido
	arbol.paused = pausa_previa
	queue_free()
	return valor


func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente = load(TextoGM.FUENTE_DIALOGO)
	_lienzo = Node2D.new()
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)
	AudioManager.efecto_ui("snd_click")
	_ajustar_inicio()


func _tam() -> Vector2:
	return get_viewport().get_visible_rect().size


func _caja(r: Rect2) -> void:
	_lienzo.draw_rect(r, COLOR_FONDO)
	_lienzo.draw_rect(r, COLOR_BORDE, false, 1.0)


func _dibujar() -> void:
	var t: Vector2 = _tam()
	if _maximo > 0:
		var texto: String = TextoGM.ajustar(_titulo, 204, _fuente)
		var alto_texto: float = (texto.count("#") + 1) * _fuente.get_height(TextoGM.TAMANO)
		var r := Rect2(t.x / 2 - 110, t.y / 2 - (alto_texto + 34) / 2, 220, alto_texto + 34)
		_caja(r)
		TextoGM.dibujar(_lienzo, _fuente, r.position + Vector2(8, 6), texto, COLOR_TEXTO)
		var linea: String = "x %d" % _cantidad + ("   %d €" % (_cantidad * _precio) if _precio > 0 else "")
		TextoGM.dibujar(_lienzo, _fuente, r.position + Vector2(r.size.x / 2, alto_texto + 14), linea, COLOR_ELEGIDO, true)
		return
	# Con dinero a la izquierda, la lista es un poco más angosta para que no se tapen.
	var ancho: float = minf(float(_opciones.get("ancho", 166.0 if _opciones.has("pie") else 190.0)), t.x - 16)
	var x: float = t.x - ancho - 6
	var y: float = 6.0
	# Pestañas (bolsillos) y título.
	if _opciones.has("pestanas"):
		var pest: Array = _opciones.pestanas
		var actual: int = int(_opciones.get("pestana", 0))
		_caja(Rect2(x, y, ancho, 16))
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + ancho / 2, y + 2), "< %s >" % pest[actual], COLOR_ELEGIDO, true)
		y += 20
	if _titulo != "":
		_caja(Rect2(x, y, ancho, 16))
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + 6, y + 2), _titulo, COLOR_TEXTO)
		y += 20
	if _opciones.has("pie"):
		var pie: String = _opciones.pie
		var w: float = _fuente.get_string_size(pie, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x + 12
		_caja(Rect2(6, 6, w, 16))
		TextoGM.dibujar(_lienzo, _fuente, Vector2(12, 8), pie, COLOR_TEXTO)
	var visibles: int = mini(FILAS_VISIBLES, maxi(1, _filas.size()))
	var con_desc: bool = _filas.any(func(f: Dictionary) -> bool: return f.get("desc", "") != "")
	var alto_lista: float = visibles * ALTO_FILA + 6
	_caja(Rect2(x, y, ancho, alto_lista))
	if _filas.is_empty():
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + 8, y + 3), "—", COLOR_GRIS)
	for k: int in visibles:
		var i: int = _inicio + k
		if i >= _filas.size():
			break
		var f: Dictionary = _filas[i]
		var col: Color = COLOR_ELEGIDO if i == _sel else (COLOR_TEXTO if f.get("activo", true) else COLOR_GRIS)
		var fy: float = y + 3 + k * ALTO_FILA
		if i == _sel:
			TextoGM.dibujar(_lienzo, _fuente, Vector2(x + 3, fy), ">", COLOR_ELEGIDO)
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + 12, fy), str(f.get("texto", "")), col)
		var der: String = str(f.get("derecha", ""))
		if der != "":
			var w: float = _fuente.get_string_size(der, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x
			TextoGM.dibujar(_lienzo, _fuente, Vector2(x + ancho - 6 - w, fy), der, col)
	# Flechas si hay más filas arriba o abajo.
	if _inicio > 0:
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + ancho / 2, y - 9), "^", COLOR_TEXTO, true)
	if _inicio + visibles < _filas.size():
		TextoGM.dibujar(_lienzo, _fuente, Vector2(x + ancho / 2, y + alto_lista - 6), "v", COLOR_TEXTO, true)
	if con_desc and _sel < _filas.size():
		var r := Rect2(6, t.y - 46, t.x - 12, 40)
		_caja(r)
		TextoGM.dibujar(_lienzo, _fuente, r.position + Vector2(8, 4), TextoGM.ajustar(str(_filas[_sel].get("desc", "")), r.size.x - 16, _fuente), COLOR_TEXTO)


func _ajustar_inicio() -> void:
	if _sel < _inicio:
		_inicio = _sel
	elif _sel >= _inicio + FILAS_VISIBLES:
		_inicio = _sel - FILAS_VISIBLES + 1


func _input(evento: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not (evento is InputEventKey and evento.pressed):
		return
	var k: Key = evento.physical_keycode
	if _maximo > 0:
		match k:
			KEY_UP: _cantidad = _cantidad % _maximo + 1
			KEY_DOWN: _cantidad = (_cantidad - 2 + _maximo) % _maximo + 1
			KEY_RIGHT: _cantidad = mini(_maximo, _cantidad + 10)
			KEY_LEFT: _cantidad = maxi(1, _cantidad - 10)
			KEY_Z, KEY_ENTER, KEY_KP_ENTER: _responder(_cantidad)
			KEY_X, KEY_ESCAPE: _responder(0)
		_lienzo.queue_redraw()
		return
	match k:
		KEY_UP:
			if not _filas.is_empty():
				_sel = (_sel - 1 + _filas.size()) % _filas.size()
		KEY_DOWN:
			if not _filas.is_empty():
				_sel = (_sel + 1) % _filas.size()
		KEY_LEFT:
			if _opciones.has("pestanas") and not evento.echo:
				_responder(IZQUIERDA)
		KEY_RIGHT:
			if _opciones.has("pestanas") and not evento.echo:
				_responder(DERECHA)
		KEY_Z, KEY_ENTER, KEY_KP_ENTER:
			if not evento.echo and not _filas.is_empty() and _filas[_sel].get("activo", true):
				_responder(_sel)
		KEY_X, KEY_ESCAPE:
			if not evento.echo:
				_responder(-1)
	_ajustar_inicio()
	_lienzo.queue_redraw()


func _responder(valor: int) -> void:
	set_process_input(false)
	_respondido.emit(valor)
