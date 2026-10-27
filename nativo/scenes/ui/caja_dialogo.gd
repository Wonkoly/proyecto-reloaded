class_name CajaDialogo
extends CanvasLayer
## El cuadro de diálogo del original (Dialogo / DialogoSimple; dibujo en DrawModalBase 6937 y 6949):
##   await CajaDialogo.decir(self, texto, sprindex, nombre)
## Con nombre (el dado, el que trae el texto como "Nombre: texto" o el del sprINDEX) usa el cuadro con
## retrato; si no, el simple. El texto se parte en diálogos por "@" y en páginas de dos líneas de
## 290 px, se escribe letra a letra (global.vel_text = 35 ms) y cada página espera Z, X o Enter.
## El juego queda congelado detrás, como en el original.

const UI: String = "res://assets/extraido/sprites/ui/"
const DATOS_PERSONAJES: String = "res://data/extraido/dialogo_personajes.json"
## global.cuadrodialogo, colordialogo y colorpersonaje por defecto.
const ESTILO: int = 10
const COLOR_TEXTO: Color = Color.WHITE
const COLOR_NOMBRE: Color = Color.YELLOW
## Milisegundos por letra (global.vel_text).
const MS_POR_LETRA: float = 35.0
const ANCHO_LINEA: float = 290.0
const MAX_LETRAS_LINEA: int = 40

static var _personajes: Dictionary = {}

signal _siguiente

var _pagina: String = ""
var _visibles: int = 0
var _nombre: String = ""
var _retrato: Dictionary = {}
var _fuente: Font
var _lienzo: Node2D
var _caja_simple: SpriteOriginal
var _caja_cara: SpriteOriginal
var _textura_retrato: Texture2D
var _esperando: bool = false


## Muestra el texto como TalkHabla: sprindex < 0 = sin retrato.
static func decir(desde: Node, texto: String, sprindex: float = -1.0, nombre: String = "") -> void:
	texto = preparar(texto)
	# DialogAdjustments: "Nombre: texto" pone el nombre.
	var dos_puntos: int = texto.find(":")
	if dos_puntos > 0 and nombre == "":
		nombre = texto.left(dos_puntos)
		texto = texto.substr(dos_puntos + 2)
	nombre = preparar(nombre)
	var datos: Dictionary = personaje(sprindex)
	if nombre == "":
		nombre = str(datos.get("nombre", ""))
	var caja := CajaDialogo.new()
	caja._nombre = nombre
	caja._retrato = datos.get("retrato", {}) if datos.get("retrato") is Dictionary else {}
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(caja)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	for parte: String in texto.split("@", false):
		for pagina: String in caja._paginas(parte.strip_edges()):
			await caja._mostrar(pagina)
	arbol.paused = pausa_previa
	caja.queue_free()


## TextDialog: $prota$ (SayMyName), $rival$ y "..." como un solo carácter.
static func preparar(texto: String, parametros: PackedStringArray = PackedStringArray()) -> String:
	var prota: String = GameState.apodo_jugador if GameState.apodo_jugador != "" else GameState.nombre_jugador
	texto = texto.replace("$prota$", prota).replace("$rival$", GameState.nombre_rival).replace("...", "…")
	for i: int in parametros.size():
		texto = texto.replace("$par%d$" % (i + 1), parametros[i])
	return texto


## {nombre, retrato} de un sprINDEX (data/extraido/dialogo_personajes.json).
static func personaje(sprindex: float) -> Dictionary:
	if _personajes.is_empty() and FileAccess.file_exists(DATOS_PERSONAJES):
		_personajes = JSON.parse_string(FileAccess.get_file_as_string(DATOS_PERSONAJES))
	if sprindex < 0.0:
		return {}
	var clave: String = str(int(sprindex)) if is_equal_approx(sprindex, roundf(sprindex)) else str(sprindex)
	return _personajes.get(clave, {})


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente = load(TextoGM.FUENTE_DIALOGO)
	_caja_simple = load(UI + "spr_dialogo.tres")
	_caja_cara = load(UI + "spr_dialogo_face.tres")
	if _nombre != "" and not _retrato.is_empty():
		if _retrato.has("archivo") and ResourceLoader.exists(_retrato.archivo):
			_textura_retrato = load(_retrato.archivo)
		elif _retrato.has("sprite") and ResourceLoader.exists(_retrato.sprite):
			var s: SpriteOriginal = load(_retrato.sprite)
			if not s.frames.is_empty():
				_textura_retrato = s.frames[clampi(int(_retrato.get("cuadro", 0)), 0, s.frames.size() - 1)]
	_lienzo = Node2D.new()
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)


## Páginas de dos líneas de como mucho 290 px y 40 letras (cortando en espacios).
func _paginas(texto: String) -> PackedStringArray:
	var lineas: PackedStringArray = []
	for parrafo: String in texto.split("#"):
		var actual: String = ""
		for palabra: String in parrafo.split(" ", false):
			var prueba: String = palabra if actual == "" else actual + " " + palabra
			var ancho: float = _fuente.get_string_size(prueba, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x
			if actual != "" and (ancho > ANCHO_LINEA or prueba.length() > MAX_LETRAS_LINEA):
				lineas.append(actual)
				actual = palabra
			else:
				actual = prueba
		if actual != "":
			lineas.append(actual)
	var paginas: PackedStringArray = []
	for i: int in range(0, lineas.size(), 2):
		paginas.append("#".join(lineas.slice(i, i + 2)))
	return paginas


func _mostrar(pagina: String) -> void:
	_pagina = pagina
	_visibles = 0
	_esperando = false
	AudioManager.efecto_ui("snd_click")
	while _visibles < _pagina.length():
		_visibles += 1
		_lienzo.queue_redraw()
		await get_tree().create_timer(MS_POR_LETRA / 1000.0, true, false, true).timeout
	_esperando = true
	await _siguiente
	_esperando = false


func _dibujar() -> void:
	var con_cara: bool = _nombre != ""
	var caja: SpriteOriginal = _caja_cara if con_cara else _caja_simple
	if caja:
		caja.dibujar(_lienzo, ESTILO, Vector2.ZERO)
	if con_cara:
		if _textura_retrato:
			_dibujar_retrato()
		TextoGM.dibujar(_lienzo, _fuente, Vector2(57, 118), _nombre, COLOR_NOMBRE)
	TextoGM.dibujar(_lienzo, _fuente, Vector2(15, 142), _pagina.left(_visibles), COLOR_TEXTO)


## drawBigTrainerExt: un recorte de 32×32 del retrato (en x, y del cuadro), dibujado volteado con su
## borde derecho en x = 39 (draw_sprite_part_ext con xscale -1).
func _dibujar_retrato() -> void:
	var frames: int = maxi(1, int(_retrato.get("frames", 1)))
	var ancho_cuadro: float = _textura_retrato.get_width() / float(frames) if _retrato.has("archivo") else 0.0
	var origen := Vector2(float(_retrato.get("x", 0)) + ancho_cuadro * int(_retrato.get("cuadro", 0)), float(_retrato.get("y", 0)))
	_lienzo.draw_set_transform(Vector2(39, 100), 0.0, Vector2(-1, 1))
	_lienzo.draw_texture_rect_region(_textura_retrato, Rect2(0, 0, 32, 32), Rect2(origen, Vector2(32, 32)))
	_lienzo.draw_set_transform(Vector2.ZERO)


func _input(evento: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if _esperando and evento is InputEventKey and evento.pressed and not evento.echo \
			and evento.physical_keycode in [KEY_Z, KEY_X, KEY_ENTER, KEY_KP_ENTER]:
		_siguiente.emit()
