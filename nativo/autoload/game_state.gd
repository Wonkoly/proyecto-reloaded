extends Node
## Estado global de la partida (equipo, flags, posición del jugador...).

## Dificultad del original (global.dificultad). Los nombres siguen el orden de las opciones del
## menú (txt_menu: Fácil, Normal, Difícil, Maestro, Extrema); el original tiene un sexto valor.
enum Dificultad { FACIL = 1, NORMAL, DIFICIL, MAESTRO, EXTREMA, SEXTA }

## Divisor del daño (PowDif) por dificultad: x = daño que hace el jugador, y = el que hace el rival.
const POW_DIF: Dictionary[Dificultad, Vector2i] = {
	Dificultad.FACIL: Vector2i(2, 4),
	Dificultad.NORMAL: Vector2i(4, 4),
	Dificultad.DIFICIL: Vector2i(4, 2),
	Dificultad.MAESTRO: Vector2i(2, 2),
	Dificultad.EXTREMA: Vector2i(1, 1),
	Dificultad.SEXTA: Vector2i(4, 1),
}

var dificultad: Dificultad = Dificultad.NORMAL

## El equipo del jugador (el primero que no esté debilitado sale a combatir).
var equipo: Array[PokemonInstance] = []
## Room del original donde está el jugador y su posición (global.lugar, global.xx/yy, global.mira).
var mapa_actual: String = "PuebloAlba"
var posicion_jugador: Vector2 = Vector2(417, 214)
var mira: int = 2
## Al entrar por una puerta: a dónde vuelve la salida del interior (global.room_out, outx/outy).
var mapa_salida: String = ""
var posicion_salida: Vector2 = Vector2.ZERO
## El Pokémon salvaje de la batalla en curso (null si la batalla no viene del overworld).
var salvaje: PokemonInstance


func _ready() -> void:
	if equipo.is_empty():
		var charmander: PokemonData = Datos.especie(4)
		if charmander:
			equipo.append(PokemonInstance.crear(charmander, 5))


## El primero del equipo que puede combatir, o null si todos están debilitados.
func pokemon_para_combatir() -> PokemonInstance:
	for p: PokemonInstance in equipo:
		if p.hp_actual > 0:
			return p
	return null


## PowDif del daño que hace un lado de la batalla (1 = jugador, 2 = rival).
func pow_dif(lado: int) -> int:
	return POW_DIF[dificultad].x if lado == 1 else POW_DIF[dificultad].y
