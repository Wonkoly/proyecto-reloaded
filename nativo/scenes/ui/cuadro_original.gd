class_name CuadroOriginal
extends CanvasLayer
## Los cuadros modales del original con su aspecto (ShowDialogQuestion, ShowDialogMessage; dibujo en
## DrawModalBase / DrawPriorModalBase): el juego se congela detrás hasta que se responde.
##   if await CuadroOriginal.preguntar(self, Textos.linea("txt_menu", 58)): ...
##   await CuadroOriginal.mensaje(self, "Texto")
## Teclas: ←/→ eligen, Z o Enter aceptan, X o Esc responden No; también con clic.

enum Tipo { PREGUNTA, PREGUNTA_IMPORTANTE, MENSAJE }

const UI: String = "res://assets/extraido/sprites/ui/"
const SPRITES: Dictionary[Tipo, String] = {
	Tipo.PREGUNTA: "spr_bck_confirm",
	Tipo.PREGUNTA_IMPORTANTE: "spr_bck_confirm_important",
	Tipo.MENSAJE: "spr_bck_message",
}
## global.cuadrodialogo: el estilo de cuadro elegido en las opciones (10 = el de por defecto).
const ESTILO: int = 10
## DefaultColorDialog, DefaultColorDialogSelect y DefaultColorDialogCancel del estilo 10.
const COLOR_TEXTO: Color = Color.WHITE
const COLOR_SI: Color = Color8(255, 242, 0)
const COLOR_NO: Color = Color8(255, 0, 0)
## Ancho máximo de línea (AjustarTexto(texto, 150, FuenteDialogo)).
const ANCHO_TEXTO: float = 150.0

signal _respondido(valor: bool)

var _tipo: Tipo
var _texto: String
var _si: bool = true  # global.drawModalSel
var _fuente: Font
var _sprite: SpriteOriginal
var _lienzo: Node2D


## ShowDialogQuestion: true si se elige Sí. `importante` usa el cuadro de Salir/Reiniciar.
static func preguntar(desde: Node, texto: String, importante: bool = false) -> bool:
	return await _abrir(desde, Tipo.PREGUNTA_IMPORTANTE if importante else Tipo.PREGUNTA, texto)


## ShowDialogMessage: espera a que se cierre.
static func mensaje(desde: Node, texto: String) -> void:
	await _abrir(desde, Tipo.MENSAJE, texto)


static func _abrir(desde: Node, tipo: Tipo, texto: String) -> bool:
	var cuadro := CuadroOriginal.new()
	cuadro._tipo = tipo
	cuadro._texto = texto
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(cuadro)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	var valor: bool = await cuadro._respondido
	arbol.paused = pausa_previa
	cuadro.queue_free()
	return valor


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente = load(TextoGM.FUENTE_DIALOGO)
	_sprite = load(UI + SPRITES[_tipo] + ".tres")
	_texto = TextoGM.ajustar(_texto, ANCHO_TEXTO, _fuente)
	_lienzo = Node2D.new()
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)
	AudioManager.efecto_ui("snd_click")


## Esquina del cuadro como el original: centrado en x, 16 px abajo del borde de la vista.
func _desplazamiento() -> Vector2:
	return Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 120.0, 16.0)


func _dibujar() -> void:
	var o: Vector2 = _desplazamiento()
	if _sprite:
		_sprite.dibujar(_lienzo, ESTILO, o + Vector2(120, 68))
	# Más líneas, más arriba (drawModalOffset: 53 con una línea, 7 px menos por cada línea más).
	var lineas: int = _texto.count("#")
	var y: float = 53.0 - 7.0 * lineas if lineas <= 4 else 18.0
	TextoGM.con_sombra(_lienzo, _fuente, o + Vector2(122, y), _texto, COLOR_TEXTO, Color.BLACK, true)
	if _tipo == Tipo.MENSAJE:
		TextoGM.con_sombra(_lienzo, _fuente, o + Vector2(120, 107), Textos.linea("txt_menu", 555), COLOR_SI, Color.BLACK, true)
		return
	TextoGM.con_sombra(_lienzo, _fuente, o + Vector2(69, 107), Textos.linea("txt_menu", 547),
		COLOR_SI if _si else COLOR_TEXTO, Color.BLACK, true)
	TextoGM.con_sombra(_lienzo, _fuente, o + Vector2(170, 107), Textos.linea("txt_menu", 548),
		COLOR_TEXTO if _si else COLOR_NO, Color.BLACK, true)


func _input(evento: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = _lienzo.get_local_mouse_position() - _desplazamiento()
		if _tipo == Tipo.MENSAJE:
			_responder(false)
		elif Rect2(51, 105, 37, 16).has_point(p):
			_responder(true)
		elif Rect2(151, 105, 37, 16).has_point(p):
			_responder(false)
		return
	if not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	match evento.physical_keycode:
		KEY_LEFT, KEY_RIGHT:
			_si = not _si
			_lienzo.queue_redraw()
		KEY_Z, KEY_ENTER, KEY_KP_ENTER:
			_responder(_si and _tipo != Tipo.MENSAJE)
		KEY_X, KEY_ESCAPE:
			_responder(false)


func _responder(valor: bool) -> void:
	set_process_input(false)
	# El original espera 75 ms al cerrar antes de seguir.
	await get_tree().create_timer(0.075, true, false, true).timeout
	_respondido.emit(valor)
