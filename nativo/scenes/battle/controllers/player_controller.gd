class_name PlayerController
extends BattleController
## Controla el Pokémon con el teclado o el control (acciones mover_* y atacar_* del Input Map).


func _controlar(_delta: float) -> void:
	pokemon.set_direccion(Input.get_vector("mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo"))
	for i: int in 4:
		if Input.is_action_just_pressed("atacar_%d" % (i + 1)):
			pokemon.atacar(i)
