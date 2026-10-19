extends Node
## Estado global de la partida (equipo, flags, posición del jugador...).

## Cambió una bandera de la historia (los mapas activan o desactivan lo que depende de ella).
signal historia_cambiada

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
## Banderas de la historia (las del objeto "variables" del original; las que no están valen 0).
## Empieza tras recibir el primer Pokémon y el móvil (igual que ESTADO_HISTORIA en
## tools/mapas_original.py, con el que se toman los valores iniciales de los mapas).
var historia: Dictionary[String, int] = {"fy_002": 1, "movil": 1}
## global.index_place: el INDEX de la última puerta usada (los interiores compartidos lo usan para
## saber a qué isla o calle devolver al jugador).
var indice_lugar: int = 0

var dinero: int = 0
## Identificador del jugador (global.prota_ID): el código SELUE depende de él.
var prota_id: int = randi_range(0, 99999)
## Apodo del protagonista (código MOTE) y personaje (código CARA: 0-9, 10 = sprite de entrenador).
var apodo_jugador: String = ""
var personaje: int = 0
var personaje_entrenador: int = 1
# Opciones del original que cambian algunos códigos (global.numcheats, saveLogBattle, vel_text...).
var trucos_usados: int = 0
var guardar_log_batalla: bool = false
var velocidad_texto: int = 1
var transicion_especial: bool = false

# Opciones de desarrollo (las cambia la consola dev).
var dev_god: bool = false
var dev_energia_infinita: bool = false
var dev_noclip: bool = false
var dev_encuentros: bool = true
## PowDif forzado para los dos lados (0 = el de la dificultad).
var dev_pow_dif: int = 0


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
	if dev_pow_dif > 0:
		return dev_pow_dif
	return POW_DIF[dificultad].x if lado == 1 else POW_DIF[dificultad].y


func bandera(nombre: String) -> int:
	return historia.get(nombre, 0)


func cambiar_historia(nombre: String, valor: int) -> void:
	historia[nombre] = valor
	historia_cambiada.emit()
