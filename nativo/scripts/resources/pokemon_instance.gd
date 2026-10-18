class_name PokemonInstance
extends Resource
## Un Pokémon concreto (de una especie).
## iv y ntv guardan un dígito (0-9) por stat, de las unidades hacia arriba:
## hp, ataque, defensa, ataque_esp, defensa_esp, velocidad. Ej.: iv = 0 y ntv = 999999 es "perfecto".

const DIGITO_STAT: Dictionary[String, int] = {
	"hp": 0, "ataque": 1, "defensa": 2, "ataque_esp": 3, "defensa_esp": 4, "velocidad": 5,
}

@export var especie: PokemonData
@export var apodo: String = ""
@export_range(1, 100, 1, "or_greater") var nivel: int = 1
@export var experiencia: int = 0
@export var hp_actual: int = 0
@export var energia_actual: int = 0
## Valores individuales: 6 dígitos de 0 a 9 (aleatorios al nacer).
@export_range(0, 999999) var iv: int = 0
## Talento natural: 6 dígitos de 0 a 9; el juego usa dígito + 1 (1-10). Se puede subir con objetos.
@export_range(0, 999999) var ntv: int = 0
@export var movimientos: Array[MoveData] = []


## Stats según el nivel, con las fórmulas del original (PSPokemon, ATPokemon... ShowStatVel).
func calcular_stats() -> Dictionary[String, int]:
	var stats: Dictionary[String, int] = {}
	for stat: String in DIGITO_STAT:
		var base: int = especie.get(stat)
		var d: int = DIGITO_STAT[stat]
		if stat == "hp":
			stats[stat] = _calcular_hp(base, _digito(iv, d), _digito(ntv, d) + 1)
		else:
			stats[stat] = floori(_formula_stat(base, nivel, _digito(iv, d), _digito(ntv, d) + 1))
	return stats


## Velocidad de movimiento en batalla, en px/s (VELPokemon: px/step × 30).
func calcular_velocidad_batalla() -> float:
	var d: int = DIGITO_STAT["velocidad"]
	var nv: float = 23.0 + nivel * 35.0 / 100.0
	var v: float = _formula_stat(especie.velocidad, nv, _digito(iv, d), _digito(ntv, d) + 1)
	return (3.0 + 11.0 * v / 504.0) * 30.0


## Energía máxima (PPMPokemon): usa el promedio de los 6 dígitos de iv y ntv.
func calcular_energia_maxima() -> int:
	var suma_iv: int = 0
	var suma_ntv: int = 0
	for d: int in 6:
		suma_iv += _digito(iv, d)
		suma_ntv += _digito(ntv, d) + 1
	var e: float = 40.0 + _formula_stat(especie.energia, nivel, _round_gm(suma_iv / 6.0), _round_gm(suma_ntv / 6.0))
	if nivel > 100:
		e += (nivel - 100) * e * 0.02
	return ceili(e)


func _calcular_hp(base: int, iv_stat: int, ntv_stat: int) -> int:
	if base == 1:
		return 1
	var hp: float = 10.0 + nivel / 100.0 * (2.0 * base + (ntv_stat - 1) * 31.0 / 9.0 + iv_stat * 63.0 / 9.0 + 100.0)
	if nivel > 100:
		hp += (nivel - 100) * hp * 0.2
	return floori(hp)


static func _formula_stat(base: int, nv: float, iv_stat: int, ntv_stat: int) -> float:
	return (0.9 + (ntv_stat - 1 + iv_stat) / 90.0) \
		* (5.0 + nv / 100.0 * (base * 2.0 + iv_stat * 31.0 / 9.0 + (ntv_stat - 1) * 63.0 / 9.0))


static func _digito(valor: int, posicion: int) -> int:
	return floori(valor / pow(10.0, posicion)) % 10


## round() de GM8: redondeo bancario (x.5 va al par más cercano).
static func _round_gm(x: float) -> int:
	var r: float = roundf(x)
	if absf(x - floorf(x) - 0.5) < 1e-9 and int(r) % 2 != 0:
		r -= signf(x)
	return int(r)
