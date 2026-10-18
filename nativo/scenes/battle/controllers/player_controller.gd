class_name PlayerController
extends BattleController
## Controla el Pokémon con el teclado o el control (acciones mover_* del Input Map).


func _controlar(_delta: float) -> void:
	pokemon.set_direccion(Input.get_vector("mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo"))
