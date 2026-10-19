class_name NumeroDanio
extends Node2D
## Número de daño flotante sobre un Pokémon (obj_Number del original: CreateNumberEffect,
## NumberStepActions, DrawNumber). Sube 1 px y pierde 0.05 de alfa por step (30 steps/s).

const STEP: float = 1.0 / 30.0
## Distancia sobre el centro del Pokémon (DIF: media máscara + 6).
const DIF: float = 14.0

var objetivo: Node2D
var numero: int = 0
var color: Color = Color.RED
var _altura: float = 0.0
var _alfa: float = 1.0
var _acumulado: float = 0.0
var _fuente: Font = load("res://assets/extraido/fonts/fuente1.fnt")


func _process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP:
		_acumulado -= STEP
		_altura -= 1.0
		_alfa -= 0.05
		if _alfa <= 0.0 or not is_instance_valid(objetivo):
			queue_free()
			return
	global_position = objetivo.global_position + Vector2(0, -DIF + _altura)
	queue_redraw()


func _draw() -> void:
	var texto: String = str(numero) if numero < 0 else "+" + str(numero)
	var ancho: float = _fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var base: Vector2 = Vector2(-ancho / 2.0, -_fuente.get_height(16) / 2.0 + _fuente.get_ascent(16))
	draw_string(_fuente, base + Vector2.ONE, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, _alfa))
	draw_string(_fuente, base, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(color, _alfa))
