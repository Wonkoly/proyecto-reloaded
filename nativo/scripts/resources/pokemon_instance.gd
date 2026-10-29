class_name PokemonInstance
extends Resource
## Un Pokémon concreto (de una especie).
## iv y ntv guardan un dígito (0-9) por stat, de las unidades hacia arriba:
## hp, ataque, defensa, ataque_esp, defensa_esp, velocidad. Más alto es mejor: iv = ntv = 999999 es
## "perfecto" (los líderes y la liga: IV2 = 999999 y GenerarPerfectoSelue).

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


## Un Pokémon nuevo como los salvajes del original (IniciaSalvaje): iv y ntv al azar, movimientos
## por nivel y HP y energía llenos.
static func crear(especie_: PokemonData, nivel_: int) -> PokemonInstance:
	var p := PokemonInstance.new()
	p.especie = especie_
	p.nivel = nivel_
	p.iv = randi_range(0, 999999)
	p.ntv = randi_range(0, 999999)
	p.asignar_movimientos_por_nivel()
	p.experiencia = p.exp_para_nivel(nivel_)
	p.hp_actual = p.calcular_stats()["hp"]
	p.energia_actual = p.calcular_energia_maxima()
	return p


## El Pokémon como datos para la partida guardada (SaveManager): especie y movimientos por id_original.
func a_dict() -> Dictionary:
	return {
		"especie": especie.id_original if especie else 0,
		"apodo": apodo,
		"nivel": nivel,
		"experiencia": experiencia,
		"hp": hp_actual,
		"energia": energia_actual,
		"iv": iv,
		"ntv": ntv,
		"movimientos": movimientos.filter(func(m: MoveData) -> bool: return m != null).map(
			func(m: MoveData) -> int: return m.id_original),
	}


## Lo contrario de a_dict(); null si la especie no existe en los datos extraídos.
static func desde_dict(d: Dictionary) -> PokemonInstance:
	var datos_especie: PokemonData = Datos.especie(int(d.get("especie", 0)))
	if datos_especie == null:
		return null
	var p := PokemonInstance.new()
	p.especie = datos_especie
	p.apodo = str(d.get("apodo", ""))
	p.nivel = int(d.get("nivel", 1))
	# Partidas viejas guardaban 0: como mínimo, la experiencia del nivel que tiene.
	p.experiencia = maxi(int(d.get("experiencia", 0)), p.exp_para_nivel(p.nivel))
	p.iv = int(d.get("iv", 0))
	p.ntv = int(d.get("ntv", 0))
	for id: Variant in d.get("movimientos", []):
		var m: MoveData = Datos.movimiento(int(id))
		if m:
			p.movimientos.append(m)
	p.hp_actual = clampi(int(d.get("hp", 0)), 0, p.calcular_stats()["hp"])
	p.energia_actual = clampi(int(d.get("energia", 0)), 0, p.calcular_energia_maxima())
	return p


## Pone los movimientos como ColocaAtaques del original: los 4 últimos distintos aprendidos por
## nivel hasta el nivel actual (el más reciente primero). Si no hay ninguno, el primero que
## aprendería al subir de nivel.
func asignar_movimientos_por_nivel() -> void:
	var por_nivel: Array[MovimientoAprendible] = especie.movimientos_aprendibles.filter(
		func(m: MovimientoAprendible) -> bool: return m.metodo == MovimientoAprendible.Metodo.NIVEL and m.move != null)
	por_nivel.sort_custom(func(a: MovimientoAprendible, b: MovimientoAprendible) -> bool: return a.nivel > b.nivel)
	movimientos.clear()
	for m: MovimientoAprendible in por_nivel:
		if m.nivel <= nivel and m.move not in movimientos:
			movimientos.append(m.move)
			if movimientos.size() == 4:
				return
	if movimientos.is_empty() and not por_nivel.is_empty():
		movimientos.append(por_nivel.back().move)


## Experiencia total para estar en el nivel n (CrecimientoPokemon); el nivel 1 vale 1.
func exp_para_nivel(n: int) -> int:
	return PokemonInstance.exp_curva(especie.crecimiento, n)


static func exp_curva(curva: PokemonData.Crecimiento, n: int) -> int:
	if n <= 1:
		return 1
	var c: float = float(n) * n * n
	var e: float = c
	match curva:
		PokemonData.Crecimiento.RAPIDO:
			e = 0.8 * c
		PokemonData.Crecimiento.LENTO:
			e = 1.25 * c
		PokemonData.Crecimiento.PARABOLICO:
			e = 1.2 * c - 15.0 * n * n + 100.0 * n - 140.0
		PokemonData.Crecimiento.ERRATICO:
			var a: float = [0.0, 0.008, 0.014][n % 3]
			if n <= 50: e = c * (100 - n) / 50.0
			elif n <= 68: e = c * (150 - n) / 100.0
			elif n <= 98: e = c * (1.274 - n / 150.0 - a)
			else: e = c * (160 - n) / 100.0
		PokemonData.Crecimiento.FLUCTUANTE:
			if n <= 15: e = c * (24 + (n + 1) / 3.0) / 50.0
			elif n <= 35: e = c * (14 + n) / 50.0
			else: e = c * (32 + n / 2.0) / 50.0
	return _round_gm(e)


## ExpGana: suma experiencia (tope: la del nivel 100) y sube de nivel lo que corresponda. Al subir,
## el HP actual crece lo mismo que el máximo (AjusteStatsLevelUp). Devuelve los niveles nuevos.
func ganar_experiencia(cantidad: int) -> Array[int]:
	var nuevos: Array[int] = []
	experiencia = mini(experiencia + maxi(cantidad, 0), exp_para_nivel(100))
	while nivel < 100 and exp_para_nivel(nivel + 1) <= experiencia:
		var hp_antes: int = calcular_stats()["hp"]
		nivel += 1
		hp_actual += calcular_stats()["hp"] - hp_antes
		nuevos.append(nivel)
	return nuevos


## Los movimientos que la especie aprende justo en ese nivel (Ataque_Nivel).
func movimientos_de_nivel(n: int) -> Array[MoveData]:
	var lista: Array[MoveData] = []
	for m: MovimientoAprendible in especie.movimientos_aprendibles:
		if m.metodo == MovimientoAprendible.Metodo.NIVEL and m.nivel == n and m.move and m.move not in lista:
			lista.append(m.move)
	return lista


## AprendeAtaque sin preguntar: si hay hueco lo agrega. 0 = aprendido, 1 = ya lo sabía, 2 = sin hueco.
func aprender(move: MoveData) -> int:
	if move in movimientos:
		return 1
	if movimientos.size() >= 4:
		return 2
	movimientos.append(move)
	return 0


## CheckEvolution (solo por nivel): si con este nivel evoluciona y en qué especie.
func evolucion_pendiente() -> PokemonData:
	if hp_actual <= 0 or especie.nivel_evolucion <= 0 or nivel < especie.nivel_evolucion:
		return null
	return Datos.especie(especie.evoluciona_a)


## EvolutionSetPokemon / EvolutionSetStats: cambia la especie; el HP actual sube lo que sube el máximo.
func evolucionar(nueva: PokemonData) -> void:
	var hp_antes: int = calcular_stats()["hp"]
	especie = nueva
	hp_actual = maxi(1, hp_actual + calcular_stats()["hp"] - hp_antes)
	energia_actual = mini(energia_actual, calcular_energia_maxima())


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
