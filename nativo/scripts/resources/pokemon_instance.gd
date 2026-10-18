class_name PokemonInstance
extends Resource
## Un Pokémon concreto (de una especie).

@export var especie: PokemonData
@export var apodo: String = ""
@export_range(1, 100) var nivel: int = 1
@export var experiencia: int = 0
@export var hp_actual: int = 0
@export var movimientos: Array[MoveData] = []


## Stats según el nivel (fórmula de la 3.ª gen. sin IV, EV ni naturaleza).
func calcular_stats() -> Dictionary[String, int]:
	var stats: Dictionary[String, int] = {
		"hp": floori(2.0 * especie.hp * nivel / 100.0) + nivel + 10,
	}
	for stat: String in ["ataque", "defensa", "ataque_esp", "defensa_esp", "velocidad"]:
		var base: int = especie.get(stat)
		stats[stat] = floori(2.0 * base * nivel / 100.0) + 5
	return stats
