class_name FormulasBatalla
## Fórmulas de batalla del original (docs/referencia_original.md).


## Daño de un ataque (Ataque1GolpeaPokemon2), sin los casos especiales de movimientos,
## habilidades, objetos, clima ni cambios de stats. mf = 1.5 si viene de "Yo primero".
static func calcular_danio(atacante: PokemonInstance, defensor: PokemonInstance, move: MoveData,
		pow_dif: int, mf: float = 1.0, etapa_at: int = 0, etapa_def: int = 0) -> int:
	if move.categoria == MoveData.Categoria.ESTADO or move.poder <= 0:
		return 0
	var fisico: bool = move.categoria == MoveData.Categoria.FISICO
	var stats_at: Dictionary[String, int] = atacante.calcular_stats()
	var stats_def: Dictionary[String, int] = defensor.calcular_stats()
	var at: float = (stats_at["ataque"] if fisico else stats_at["ataque_esp"]) * factor_etapa(etapa_at)
	var df: float = (stats_def["defensa"] if fisico else stats_def["defensa_esp"]) * factor_etapa(etapa_def)
	var stab: float = 1.5 if move.tipo in atacante.especie.tipos else 1.0
	var eff: float = Efectividad.multiplicador(move.tipo, defensor.especie.tipos)
	var danio: float = ((2.0 * atacante.nivel / 5.0 + 2.0) * (mf * at * move.poder / df) / 50.0 + 2.0) \
		* stab * eff * 0.85
	if fisico and atacante.estado == MoveData.Estado.QUEMADO:
		danio -= danio * 0.5  # STD = 2 y ataque físico
	return ceili(danio / pow_dif)


## Ataque1GolpeaPokemon2: stat × (4 + s) / 4 subiendo, stat × 4 / (4 − s) bajando (s de −12 a 12).
static func factor_etapa(s: int) -> float:
	return (4.0 + s) / 4.0 if s >= 0 else 4.0 / (4.0 - s)


## El daño de un golpe entre dos Pokémon en combate, con sus etapas de stats y estados.
static func danio_en_batalla(atacante: BattlePokemon, defensor: BattlePokemon, move: MoveData) -> int:
	var fisico: bool = move.categoria == MoveData.Categoria.FISICO
	var danio: float = calcular_danio(atacante.pokemon, defensor.pokemon, move, GameState.pow_dif(atacante.lado), 1.0,
		atacante.etapa(1 if fisico else 3), defensor.etapa(2 if fisico else 4))
	return roundi(danio * factor_objetos(atacante.pokemon.objeto, defensor.pokemon.objeto, move,
		Efectividad.multiplicador(move.tipo, defensor.pokemon.especie.tipos), atacante.pokemon.especie.id_original)) \
		if danio > 0 else 0


## Número de tipo del original (TipoName: 1 Normal, 2 Fuego...) de cada Tipos.Tipo.
const TIPO_ORIGINAL: Array[int] = [1, 2, 3, 4, 5, 12, 7, 10, 8, 15, 9, 11, 6, 16, 17, 13, 14, 18]
## ObjetoPotenciador: objetos que suben ×1.2 los ataques de un tipo (por número de tipo del original).
const POTENCIADORES: Dictionary[int, Array] = {1: [91, 310], 2: [92, 311], 3: [93, 312, 768, 770],
	4: [94, 313, 769], 5: [95, 314], 6: [96, 60, 767], 7: [97, 59], 8: [98, 315], 9: [99, 58, 773],
	10: [100, 317], 11: [101, 316], 12: [102, 318], 13: [103, 319], 14: [104, 62], 15: [105, 320],
	16: [106, 61], 17: [107, 321], 18: [410, 411]}
## Objetos de una especie que doblan su daño (Bola Luminosa, Bola Hierba... y Hueso Grueso en físicos).
const OBJETOS_ESPECIE: Dictionary[int, Array] = {330: [25, 172], 331: [447],
	333: [1, 152, 252, 387, 518, 745, 901, 2037], 334: [4, 155, 255, 390, 521, 748, 904, 2040],
	335: [7, 158, 258, 393, 524, 751, 907, 2043], 540: [104, 105]}


## GemaPotenciadora: la gema del tipo del ataque (383 + número de tipo) lo sube ×1.5 y se gasta.
static func es_gema_de(objeto: int, move: MoveData) -> bool:
	return objeto == 383 + TIPO_ORIGINAL[move.tipo]


## Ataque1GolpeaPokemon2: lo que cambian el daño los objetos equipados (sobre DANO ya calculado).
## Cinta Elección (358) ×1.5 físicos, Gafas Elección (362) ×1.5 especiales, Gafas Especiales (361)
## ×1.1 especiales, Cinta Experto (359) ×1.2 si es muy eficaz, Vidasfera (377) ×1.3; Chaleco Asalto
## (539) en quien recibe: ÷1.5 los especiales.
static func factor_objetos(objeto_atacante: int, objeto_defensor: int, move: MoveData, eff: float,
		especie_atacante: int = 0) -> float:
	var fisico: bool = move.categoria == MoveData.Categoria.FISICO
	var especial: bool = move.categoria == MoveData.Categoria.ESPECIAL
	var f: float = 1.0
	if objeto_atacante in POTENCIADORES.get(TIPO_ORIGINAL[move.tipo], []):
		f *= 1.2
	if es_gema_de(objeto_atacante, move):
		f *= 1.5
	if especie_atacante in OBJETOS_ESPECIE.get(objeto_atacante, []) and (objeto_atacante != 540 or fisico):
		f *= 2.0
	if objeto_defensor == 539 and especial:
		f /= 1.5
	match objeto_atacante:
		358: if fisico: f *= 1.5
		362: if especial: f *= 1.5
		361: if especial: f *= 1.1
		359: if eff > 1.0: f *= 1.2
		377: f *= 1.3
	return f


## Índice de ball del original (obj_Pokeball.index) según el id del objeto: 1-13 → 0-12,
## 472-483 → 14-25, 522 → 26 (KeyActionsBattle).
static func indice_ball(id_objeto: int) -> int:
	if id_objeto <= 13:
		return id_objeto - 1
	if id_objeto >= 472 and id_objeto <= 483:
		return id_objeto - 458
	return 26 if id_objeto == 522 else 0


## PokeBallProbabilidad: % de captura (0-100). Parte de la rareza (NumRareza), sube con poco PS y baja
## con el nivel; luego el multiplicador de cada ball. La Master Ball (índice 3) captura siempre.
## Sin estados ni objetos equipados todavía (×1.5 con estado, Ultraentes, pesca...: ver docs).
static func probabilidad_captura(rival: PokemonInstance, indice: int, jugador: PokemonInstance,
		segundos_combate: float, capturado_antes: bool) -> float:
	if indice == 3:
		return 100.0
	var sal: float = 100.0 * rival.hp_actual / maxf(1.0, rival.calcular_stats()["hp"])
	var pos: float = rival.especie.ratio_captura
	if sal > 20.0: pos = 20.0 * pos / sal
	elif sal <= 2.0: pos *= 2.0
	elif sal <= 5.0: pos *= 1.75
	elif sal <= 10.0: pos *= 1.5
	if rival.nivel >= 10:
		pos = 10.0 * pos / rival.nivel
	var steps: float = segundos_combate * 30.0  # fight_time cuenta steps
	var tipos: Array[Tipos.Tipo] = rival.especie.tipos
	var ratio: float = 1.0
	match indice:
		1, 4, 13: ratio = 1.5
		2: ratio = 2.0
		6: ratio = 4.0 if Tipos.Tipo.AGUA in tipos or Tipos.Tipo.BICHO in tipos else 1.0  # Malla
		8: ratio = 4.0 if steps > 600 else steps / 150.0  # Turno
		10: ratio = (40 - rival.nivel) / 10.0  # Nido
		11: ratio = 3.0 if capturado_antes else 1.0  # Acopio
		12: ratio = 4.0
		14:  # Rápida
			ratio = 4.0 if rival.especie.velocidad >= 100 else (2.0 if rival.especie.velocidad >= 85 else 1.0)
		15:  # Nivel
			if jugador and rival.nivel < jugador.nivel: ratio = 2.0
			if jugador and rival.nivel * 2 <= jugador.nivel: ratio = 4.0
			if jugador and rival.nivel * 4 <= jugador.nivel: ratio = 8.0
		20:  # Luna
			if rival.especie.id_original in [30, 33, 35, 39, 300, 636, 488] or Tipos.Tipo.HADA in tipos: ratio = 4.0
		23: ratio = 1.0 if steps > 60 else 5.0 - steps / 15.0  # Veloz
		25: ratio = 5.0
	return minf(pos * ratio, 100.0)
