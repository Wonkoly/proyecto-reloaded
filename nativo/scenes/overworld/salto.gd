class_name Salto
extends Area2D
## Un borde que se baja saltando (obj_saltos, obj_saltos_I, obj_saltos_D: ProtaSaltos). Su hijo
## Bloqueo es una colisión de un solo sentido que no deja subirlo; mientras el jugador toca el
## área, lo empuja en la dirección del salto a su velocidad + 1 px/step.

enum Reversible { NO, HORIZONTAL, VERTICAL }

## Hacia dónde se salta: abajo (obj_saltos), izquierda (obj_saltos_I) o derecha (obj_saltos_D).
@export var direccion: Vector2 = Vector2.DOWN
## obj_reversibleHorizontal / obj_reversibleVertical: no bloquea; empuja a través de él en el
## sentido en que se acerca el jugador (ReversibleHorStepActions: SENTIDO).
@export var reversible: Reversible = Reversible.NO


func _ready() -> void:
	add_to_group("saltos")


## Dirección del empuje para un jugador en esa posición.
func direccion_para(posicion: Vector2) -> Vector2:
	match reversible:
		Reversible.HORIZONTAL:
			return Vector2(1 if global_position.x - posicion.x > 0 else -1, 0)
		Reversible.VERTICAL:
			return Vector2(0, 1 if global_position.y - posicion.y > 0 else -1)
	return direccion
