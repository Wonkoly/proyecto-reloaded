extends Node2D
## Intro del original (IntroROOM: obj_black + obj_blackIntro): los créditos de copyright aparecen
## mientras se aclara la pantalla, pasan a los de FER Productions y la pantalla se oscurece hasta
## el título. Enter la salta (KeyActionsBlack). Empieza la música del título (BlackConfiguration).

const UI: String = "res://assets/extraido/sprites/ui/"
const RESOLUCION: Vector2i = Vector2i(320, 180)
const PASOS_POR_SEGUNDO: float = 30.0
const ESCENA_TITULO: String = "res://scenes/titulo/titulo.tscn"

var _fondo: Texture2D = load(UI + "fondos/back_intro.png")
var _letras: Texture2D = load(UI + "fondos/back_intro_letras.png")
var _creditos: SpriteOriginal = load(UI + "spr_credits_intro.tres")

var _acumulado: float = 0.0
## obj_black.image_alpha: la cortina del principio (se dibuja con el alfa entre 0 y 1).
var _negro: float = 1.1
## obj_blackIntro: cuadro de los créditos, si ya empezó a cambiar y su cortina del final.
var _cuadro: int = 0
var _sale: bool = false
var _espera_cuadro: int = 0
var _negro_final: float = -0.6
var _terminado: bool = false


func _ready() -> void:
	get_window().content_scale_size = RESOLUCION
	GameState.en_partida = false
	AudioManager.reproducir_intro()


func _process(delta: float) -> void:
	_acumulado += delta * PASOS_POR_SEGUNDO
	while _acumulado >= 1.0 and not _terminado:
		_acumulado -= 1.0
		_paso()
	queue_redraw()


func _paso() -> void:
	# BlackStepAction en IntroROOM: la cortina se aclara; al pasar de -0.3 empiezan los cambios de texto.
	_negro -= 0.01
	if _negro <= -0.3 and not _sale:
		_sale = true
		_espera_cuadro = 1
	# BlackIntroChangeText (alarm[0] cada 3 pasos hasta el cuadro 6).
	if _espera_cuadro > 0:
		_espera_cuadro -= 1
		if _espera_cuadro == 0 and _cuadro <= 5:
			_cuadro += 1
			_espera_cuadro = 3
	# BlackIntroStepAction: con el último cuadro la pantalla se oscurece y pasa al título.
	if _sale and _cuadro >= 6:
		if _negro_final > 1.4:
			_ir_al_titulo()
			return
		_negro_final += 0.01


func _draw() -> void:
	draw_texture_rect(_fondo, Rect2(Vector2.ZERO, RESOLUCION), true)
	draw_texture_rect_region(_letras, Rect2(0, 0, 240, 180), Rect2(0, 0, 240, 180))
	_creditos.dibujar(self, _cuadro, Vector2(RESOLUCION) / 2.0)
	if _sale and _cuadro >= 6:
		draw_rect(Rect2(Vector2.ZERO, RESOLUCION), Color(0, 0, 0, clampf(_negro_final, 0.0, 1.0)))
	draw_rect(Rect2(Vector2.ZERO, RESOLUCION), Color(0, 0, 0, clampf(_negro, 0.0, 1.0)))


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and not evento.echo \
			and evento.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_ir_al_titulo()


func _ir_al_titulo() -> void:
	if _terminado:
		return
	_terminado = true
	get_tree().change_scene_to_file.call_deferred(ESCENA_TITULO)
