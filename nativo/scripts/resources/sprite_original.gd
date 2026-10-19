class_name SpriteOriginal
extends Resource
## Un sprite del juego original (GM8): sus frames y su origen, para dibujarlo con las mismas
## coordenadas que el original (draw_sprite / draw_sprite_ext).

@export var frames: Array[Texture2D] = []
## Punto del sprite que queda en la posición donde se dibuja.
@export var origen: Vector2 = Vector2.ZERO


## draw_sprite_ext del original sobre un CanvasItem (dentro de su _draw).
## angulo: grados en sentido antihorario, como image_angle.
func dibujar(lienzo: CanvasItem, frame: int, posicion: Vector2, escala: Vector2 = Vector2.ONE,
		color: Color = Color.WHITE, angulo: float = 0.0) -> void:
	if frames.is_empty():
		return
	lienzo.draw_set_transform(posicion, deg_to_rad(-angulo), escala)
	lienzo.draw_texture(frames[clampi(frame, 0, frames.size() - 1)], -origen, color)
	lienzo.draw_set_transform(Vector2.ZERO)
