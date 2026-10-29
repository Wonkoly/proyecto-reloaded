class_name PantallaVuelo
extends CanvasLayer
## El mapa de la región con los lugares visitados (obj_pantallavuelo: DefinePantallaVuelo,
## DrawPantallaVuelo, CheckMousePantallaVuelo, KeyActionsPantallaVuelo, ConfirmaVuelo) y la marca de
## dónde está el jugador (MapaDondeEstoy). Se dibuja en las coordenadas del original (320×180).
##   var lugar: Dictionary = await PantallaVuelo.abrir(self, true)  # {} si se cancela
## Teclas: ↑/↓ recorren los lugares (FlyScreenNext), ←/→ cambian de región (con el GPS), Z o Enter
## eligen, X, Esc o 2 cancelan, P oculta al jugador, V cambia el estilo del mapa, C + flechas mueve el
## cursor. También con el ratón.

const UI: String = "res://assets/extraido/sprites/ui/"
const TAMANO: Vector2 = Vector2(320, 180)
## x_offset / y_offset de cada región.
const DESPLAZAMIENTO: Array[Vector2] = [Vector2(40, 5), Vector2(40, 0), Vector2(40, 0), Vector2(0, 0)]
## draw_set_color(4471868) y draw_text_color(..., 52235, c_green, ...) del nombre elegible.
const COLOR_TEXTO: int = 4471868
const COLOR_LUGAR: int = 52235
## Zonas de las flechas de región y del botón de cancelar (CheckMousePantallaVuelo).
const ZONA_IZQUIERDA: Rect2 = Rect2(0, 81, 14, 18)
const ZONA_DERECHA: Rect2 = Rect2(306, 81, 14, 18)
const ZONA_CANCELAR: Rect2 = Rect2(2, 151, 24, 24)
## Nombres de las regiones (text_rg1..4; la primera cambia con mapa2).
const TEXTO_REGION: Array[int] = [97, 98, 99, 1140]

## global.mapa_style: 1 normal, 2 y 3 los otros dibujos.
static var estilo: int = 1

signal _cerrada(lugar: Dictionary)

var _volar: bool = true
var _region: int = 0
var _cursor: Vector2 = Vector2(160, 90)
var _lugar: String = ""
var _texto: String = ""
var _seleccion: int = -1
var _oculto: bool = false
var _pasos: float = 0.0
var _preguntando: bool = false
var _lienzo: Node2D
var _fuente: Font
var _sprite_jugador: SpriteOriginal
var _sprites: Dictionary[String, SpriteOriginal] = {}
## Spr_Objeto frame 0 (el botón de cancelar): extraído como frames sueltos en efectos/spr_objeto.
var _cancelar: Texture2D


## Abre el mapa; con `volar` se elige un destino (devuelve su lugar de vuelo.json, o {}).
static func abrir(desde: Node, volar: bool) -> Dictionary:
	var p := PantallaVuelo.new()
	p._volar = volar
	var jugador: Jugador = desde as Jugador if desde is Jugador else DevConsole.jugador()
	if jugador:
		p._sprite_jugador = jugador.sprite_abajo
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(p)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	var lugar: Dictionary = await p._cerrada
	arbol.paused = pausa_previa
	p.queue_free()
	return lugar


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente = load("res://assets/extraido/fonts/fuente_dex.fnt")
	for n: String in ["spr_mapa", "spr_mapa_v2", "spr_mapa_v3", "spr_cambiarmapa_l", "spr_cambiarmapa_r",
			"spr_map_selector", "obj_aquisivuelo"]:
		_sprites[n] = load(UI + n + ".tres")
	_cancelar = load("res://assets/extraido/sprites/efectos/spr_objeto/0.png")
	# DefinePantallaVuelo: INDEX = MapaLugar(global.lugar).
	_region = Vuelo.region(Vuelo.afuera())
	if _region not in Vuelo.regiones_abiertas():
		_region = 0
	_lienzo = Node2D.new()
	_lienzo.scale = get_viewport().get_visible_rect().size / TAMANO
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)
	AudioManager.efecto_ui("snd_click")


func _process(delta: float) -> void:
	_pasos += delta * 30.0
	_lienzo.queue_redraw()


func _lugares_de_region() -> Dictionary:
	var r: Dictionary = {}
	var lugares: Dictionary = Vuelo.datos().get("lugares", {})
	for k: String in lugares:
		if int(lugares[k].region) == _region and Vuelo.visitado(int(k)):
			r[k] = lugares[k]
	return r


func _dibujar() -> void:
	var o: Vector2 = DESPLAZAMIENTO[_region]
	_sprites["spr_mapa"].dibujar(_lienzo, _region, Vector2.ZERO)
	if estilo == 2:
		_sprites["spr_mapa_v2"].dibujar(_lienzo, _region, Vector2.ZERO)
	elif estilo == 3:
		_sprites["spr_mapa_v3"].dibujar(_lienzo, _region, Vector2.ZERO)
	if _cancelar:
		_lienzo.draw_texture(_cancelar, Vector2(2, 151), Color(1, 1, 1, 0.75))
	TextoGM.dibujar(_lienzo, _fuente, Vector2(40, 164), Textos.linea("txt_menu", 102), TextoGM.color(COLOR_TEXTO))
	TextoGM.dibujar(_lienzo, _fuente, Vector2(154, 164), _texto,
		TextoGM.color(COLOR_LUGAR) if _lugar != "" else TextoGM.color(COLOR_TEXTO))
	# Los lugares visitados (sprite obj_aquisivuelo, image_speed 0.05).
	var lugares: Dictionary = _lugares_de_region()
	for k: String in lugares:
		_sprites["obj_aquisivuelo"].dibujar(_lienzo, int(_pasos * 0.05) % 2,
			o + Vector2(lugares[k].marca[0], lugares[k].marca[1]))
	_dibujar_jugador(o)
	if GameState.objetos.has(Vuelo.OBJETO_GPS):
		_sprites["spr_cambiarmapa_l"].dibujar(_lienzo, int(_pasos * 0.05) % 2, Vector2(10, 90))
		_sprites["spr_cambiarmapa_r"].dibujar(_lienzo, int(_pasos * 0.05) % 2, Vector2(310, 90))
	_sprites["spr_map_selector"].dibujar(_lienzo, int(_pasos / 2.0) % maxi(_sprites["spr_map_selector"].frames.size(), 1),
		_cursor, Vector2.ONE, Color(1, 1, 1, 0.7))


## MapaDondeEstoy: el jugador (su sprite de frente) donde está, parpadeando (9 steps sí, 9 no) y
## transparente sobre el mapa de vuelo.
func _dibujar_jugador(o: Vector2) -> void:
	var mapa: String = Vuelo.afuera()
	var u: Variant = Vuelo.datos().get("ubicaciones", {}).get(mapa)
	if _oculto or u == null or _sprite_jugador == null or Vuelo.region(mapa) != _region:
		return
	if int(_pasos) % 18 >= 9:
		return
	_sprite_jugador.dibujar(_lienzo, 1, o + Vector2(u[0], u[1]), Vector2.ONE, Color(1, 1, 1, 0.4))


## CheckMousePantallaVuelo: qué hay bajo el cursor (un lugar visitado, una flecha o cancelar).
func _revisar_cursor() -> void:
	_lugar = ""
	_texto = ""
	if GameState.objetos.has(Vuelo.OBJETO_GPS) and (ZONA_IZQUIERDA.has_point(_cursor) or ZONA_DERECHA.has_point(_cursor)):
		_texto = _nombre_region(_otra_region(-1 if ZONA_IZQUIERDA.has_point(_cursor) else 1))
		return
	if ZONA_CANCELAR.has_point(_cursor):
		_texto = Textos.linea("txt_menu", 100)
		return
	var o: Vector2 = DESPLAZAMIENTO[_region]
	var lugares: Dictionary = _lugares_de_region()
	for k: String in lugares:
		var z: Array = lugares[k].zona
		# Mouse_Position: los bordes cuentan.
		if Rect2(o.x + z[0], o.y + z[1], z[2] - z[0] + 1, z[3] - z[1] + 1).has_point(_cursor):
			_lugar = k
			_texto = Textos.linea("txt_places", int(lugares[k].texto))
			return


func _nombre_region(r: int) -> String:
	if r == 0 and GameState.bandera("mapa2") == 1:
		return Textos.linea("txt_menu", 870)
	return Textos.linea("txt_menu", TEXTO_REGION[r])


func _otra_region(paso: int) -> int:
	var abiertas: Array[int] = Vuelo.regiones_abiertas()
	var i: int = abiertas.find(_region)
	return abiertas[(i + paso + abiertas.size()) % abiertas.size()]


func _cambiar_region(paso: int) -> void:
	if not GameState.objetos.has(Vuelo.OBJETO_GPS):
		return
	_region = _otra_region(paso)
	_seleccion = -1
	_revisar_cursor()


## FlyScreenNext / FlyScreenPrevious: el siguiente lugar visitado de la región, y el cursor encima.
func _recorrer(paso: int) -> void:
	var orden: Array = Vuelo.datos().get("orden", {}).get(str(_region), [])
	var visitados: Array = orden.map(func(n: Variant) -> int: return int(n)).filter(Vuelo.visitado)
	if visitados.is_empty():
		return
	var i: int = visitados.find(_seleccion)
	i = (i + paso) % visitados.size() if i >= 0 else (0 if paso > 0 else visitados.size() - 1)
	_seleccion = int(visitados[i])
	var marca: Array = Vuelo.datos().lugares[str(_seleccion)].marca
	_cursor = DESPLAZAMIENTO[_region] + Vector2(marca[0], marca[1])
	_revisar_cursor()


## ConfirmaVuelo: en una flecha cambia de región, en cancelar cierra y en un lugar pregunta.
func _confirmar() -> void:
	if GameState.objetos.has(Vuelo.OBJETO_GPS) and ZONA_IZQUIERDA.has_point(_cursor):
		_cambiar_region(-1)
		return
	if GameState.objetos.has(Vuelo.OBJETO_GPS) and ZONA_DERECHA.has_point(_cursor):
		_cambiar_region(1)
		return
	if ZONA_CANCELAR.has_point(_cursor):
		_cerrar({})
		return
	if _lugar == "" or not _volar:
		return
	_preguntando = true
	var lugar: Dictionary = Vuelo.datos().lugares[_lugar]
	var si: bool = await CuadroOriginal.preguntar(self, Textos.par(Textos.linea("txt_menu", 101), _texto))
	_preguntando = false
	if si:
		_cerrar(lugar)


func _cerrar(lugar: Dictionary) -> void:
	set_process_input(false)
	_cerrada.emit(lugar)


func _input(evento: InputEvent) -> void:
	if _preguntando:
		return
	get_viewport().set_input_as_handled()
	if evento is InputEventMouseMotion:
		_cursor = _lienzo.get_local_mouse_position()
		_seleccion = -1
		_revisar_cursor()
		return
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		_cursor = _lienzo.get_local_mouse_position()
		_revisar_cursor()
		_confirmar()
		return
	if not (evento is InputEventKey and evento.pressed):
		return
	var tecla: Key = evento.physical_keycode
	if Input.is_physical_key_pressed(KEY_C) and tecla in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var d: Dictionary[Key, Vector2] = {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}
		_cursor = (_cursor + d[tecla] * 10.0).clamp(Vector2.ZERO, TAMANO)
		_revisar_cursor()
		return
	if evento.echo:
		return
	match tecla:
		KEY_Z, KEY_ENTER, KEY_KP_ENTER:
			_confirmar()
		KEY_X, KEY_ESCAPE, KEY_2:
			_cerrar({})
		KEY_P:
			_oculto = not _oculto
		KEY_V:
			estilo = estilo % 3 + 1
		KEY_RIGHT:
			_cambiar_region(1)
		KEY_LEFT:
			_cambiar_region(-1)
		KEY_DOWN:
			_recorrer(1)
		KEY_UP:
			_recorrer(-1)
