class_name Decorado
extends Node2D
## Una instancia del original que solo se dibuja (árboles, edificios, flores, hierba...): su
## sprite con el origen de GM8, la escala y la animación (image_speed en frames por step, a 30/s).

const STEP: float = 1.0 / 30.0

@export var sprite: SpriteOriginal
@export var image_speed: float = 0.0
@export var image_alpha: float = 1.0
@export var escala: Vector2 = Vector2.ONE

var _frame: float = 0.0
var _acumulado: float = 0.0


func _ready() -> void:
	set_process(image_speed != 0.0 and sprite != null and sprite.frames.size() > 1)


func _process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP:
		_acumulado -= STEP
		_frame = fmod(_frame + image_speed, sprite.frames.size())
	queue_redraw()


## La caja de la instancia en el mapa (su máscara: el primer frame con el origen y la escala), para
## los place_meeting del original.
func caja() -> Rect2:
	if sprite == null or sprite.frames.is_empty():
		return Rect2(global_position, Vector2.ZERO)
	return Rect2(global_position - sprite.origen * escala, sprite.frames[0].get_size() * escala).abs()


func _draw() -> void:
	if sprite:
		sprite.dibujar(self, int(_frame), Vector2.ZERO, escala, Color(1, 1, 1, image_alpha))
