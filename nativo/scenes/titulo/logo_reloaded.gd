@tool
class_name LogoReloaded
extends Control
## El logo del título original (InicioROOM) con sus animaciones, a `escala`: el "Pokémon" brilla
## (spr_title, 0.1666 frames/step) y descansa 100 steps, tras cada brillo la estrella da una vuelta
## de -20°/step, y "RELOADED" (spr_title2) late entre alfa 0.7 y 1.3.

const UI: String = "res://assets/extraido/sprites/ui/"
const PASOS_POR_SEGUNDO: float = 30.0
## Posiciones del original (room de 320×180) relativas a la esquina del logo.
const POS_LOGO: Vector2 = Vector2(84, 29)
const POS_RELOADED: Vector2 = Vector2(90, 57)
const POS_ESTRELLA: Vector2 = Vector2(178, 41)
const TAMANO_BASE: Vector2 = Vector2(200, 66)

@export var escala: float = 2.0:
	set(v):
		escala = v
		custom_minimum_size = TAMANO_BASE * v

var _logo: SpriteOriginal
var _reloaded: SpriteOriginal
var _estrella: SpriteOriginal
var _acumulado: float = 0.0
var _frame_logo: float = 0.0
var _brilla: bool = true
var _espera_brillo: int = 0
var _frame_reloaded: float = 0.0
var _alfa_reloaded: float = 1.0
var _sube: bool = false
var _angulo: float = 0.0
var _espera_giro: int = 0


func _ready() -> void:
	custom_minimum_size = TAMANO_BASE * escala
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for par: Array in [["spr_title", "_logo"], ["spr_title2", "_reloaded"], ["spr_title3", "_estrella"]]:
		if ResourceLoader.exists(UI + par[0] + ".tres"):
			set(par[1], load(UI + par[0] + ".tres"))


func _process(delta: float) -> void:
	_acumulado += delta * PASOS_POR_SEGUNDO
	while _acumulado >= 1.0:
		_acumulado -= 1.0
		_paso()
	queue_redraw()


func _paso() -> void:
	if _espera_brillo > 0:
		_espera_brillo -= 1
		if _espera_brillo == 0:
			_brilla = true
	if _espera_giro > 0:
		_espera_giro -= 1
		if _espera_giro == 0:
			_angulo -= 20.0
			if _angulo > -340.0:
				_espera_giro = 1
			else:
				_angulo = 0.0
	_alfa_reloaded += 0.025 if _sube else -0.025
	if _alfa_reloaded > 1.3:
		_sube = false
	if _alfa_reloaded < 0.7:
		_sube = true
	if _reloaded:
		_frame_reloaded = fposmod(_frame_reloaded + 0.1666, _reloaded.frames.size())
	if not _brilla:
		_frame_logo = 0.0
	elif _logo:
		_frame_logo += 0.1666
		if _frame_logo >= _logo.frames.size():
			_frame_logo -= _logo.frames.size()
			_brilla = false
			_espera_brillo = 100
			_espera_giro = 1


func _draw() -> void:
	var e := Vector2(escala, escala)
	if _reloaded:
		_reloaded.dibujar(self, int(_frame_reloaded), POS_RELOADED * escala, e, Color(1, 1, 1, clampf(_alfa_reloaded, 0.0, 1.0)))
	if _logo:
		_logo.dibujar(self, int(_frame_logo), POS_LOGO * escala, e)
	if _estrella:
		_estrella.dibujar(self, 0, POS_ESTRELLA * escala, e, Color.WHITE, _angulo)
