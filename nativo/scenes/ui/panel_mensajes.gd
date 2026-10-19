class_name PanelMensajes
extends Control
## Panel de mensajes de batalla del original (obj_panel_informativo): los textos entran desde
## arriba deslizándose y quedan las dos últimas líneas. Corre a 30 steps/s como el original.

const STEP: float = 1.0 / 30.0
const TAM_BUFFER: int = 10
## Steps que una línea queda quieta antes de dejar pasar la siguiente (MINIMO_EN_PANTALLA).
const MINIMO_EN_PANTALLA: int = 2
const COLOR_TEXTO: Color = Color8(0xD0, 0xD0, 0xC8)
const RECT: Rect2 = Rect2(69, 279, 438, 37)

var _buffer: Array[String] = []
var _linea1: String = ""
var _linea2: String = ""
var _movimiento: int = 0
var _espera: int = 0
var _alfa: float = 1.0
var _ocultar: Dictionary[Object, bool] = {}
var _acumulado: float = 0.0
var _fuente: Font = load("res://assets/extraido/fonts/fuente1.fnt")


func agregar(texto: String) -> void:
	if texto != "" and _buffer.size() <= TAM_BUFFER:
		_buffer.append(texto)
		if GameState.guardar_log_batalla:
			# Código LOGBATTLE del original: cada mensaje se agrega a LogBattle.txt.
			var f: FileAccess = FileAccess.open("user://LogBattle.txt", FileAccess.READ_WRITE)
			if f == null:
				f = FileAccess.open("user://LogBattle.txt", FileAccess.WRITE)
			f.seek_end()
			f.store_line(texto)


## Un Pokémon por debajo de y = 270 queda detrás del panel: el panel se vuelve translúcido.
func on_pokemon_movido(posicion: Vector2, quien: Object) -> void:
	_ocultar[quien] = posicion.y > 270.0


func _process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP:
		_acumulado -= STEP
		_step()
	queue_redraw()


func _step() -> void:
	if true in _ocultar.values():
		if _alfa > 0.3:
			_alfa -= 0.02
	elif _alfa < 1.0:
		_alfa = minf(_alfa + 0.02, 1.0)
	if _espera > 0:
		_espera -= 1
	elif _movimiento > 0:
		if _movimiento >= 16:
			_linea2 = _linea1
			_linea1 = _buffer.pop_front()
			_movimiento = 0
			_espera = MINIMO_EN_PANTALLA
		else:
			_movimiento += 4
	elif not _buffer.is_empty():
		_movimiento = 4


func _draw() -> void:
	draw_rect(RECT, Color(0, 0, 0, _alfa - 0.25))
	if _movimiento > 0:
		var t: float = _movimiento / 16.0
		_texto(_buffer[0], 268 + _movimiento, _alfa * t)
		_texto(_linea1, 282 + _movimiento, _alfa)
		_texto(_linea2, 298 + _movimiento, _alfa - _alfa * t)
	else:
		_texto(_linea1, 282, _alfa)
		_texto(_linea2, 298, _alfa)


## draw_text_color del original con su sombra negra 1 px abajo a la derecha.
func _texto(texto: String, y: float, alfa: float) -> void:
	if texto == "" or alfa <= 0.0:
		return
	var base: Vector2 = Vector2(80, y + _fuente.get_ascent())
	draw_string(_fuente, base + Vector2.ONE, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, alfa))
	draw_string(_fuente, base, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(COLOR_TEXTO, alfa))
