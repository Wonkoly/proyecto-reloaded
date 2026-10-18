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


## PowDif del daño que hace un lado de la batalla (1 = jugador, 2 = rival).
func pow_dif(lado: int) -> int:
	return POW_DIF[dificultad].x if lado == 1 else POW_DIF[dificultad].y
