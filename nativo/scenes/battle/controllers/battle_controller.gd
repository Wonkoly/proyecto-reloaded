class_name BattleController
extends Node
## Base de quien maneja a un BattlePokemon (jugador o IA). Va como hijo del Pokémon y corre
## antes que él en cada frame de física, así la dirección se aplica en el mismo frame.

var pokemon: BattlePokemon


func _ready() -> void:
	pokemon = get_parent() as BattlePokemon
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if pokemon:
		_controlar(delta)


## Le da órdenes al Pokémon (set_direccion, atacar...). Lo implementa cada controlador.
func _controlar(_delta: float) -> void:
	pass
