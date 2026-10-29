class_name FormulasBatalla
## Fórmulas de batalla del original (docs/referencia_original.md).


## Daño de un ataque (Ataque1GolpeaPokemon2), sin los casos especiales de movimientos,
## habilidades, objetos, clima ni cambios de stats. mf = 1.5 si viene de "Yo primero".
static func calcular_danio(atacante: PokemonInstance, defensor: PokemonInstance, move: MoveData,
		pow_dif: int, mf: float = 1.0) -> int:
	if move.categoria == MoveData.Categoria.ESTADO or move.poder <= 0:
		return 0
	var fisico: bool = move.categoria == MoveData.Categoria.FISICO
	var stats_at: Dictionary[String, int] = atacante.calcular_stats()
	var stats_def: Dictionary[String, int] = defensor.calcular_stats()
	var at: float = stats_at["ataque"] if fisico else stats_at["ataque_esp"]
	var df: float = stats_def["defensa"] if fisico else stats_def["defensa_esp"]
	var stab: float = 1.5 if move.tipo in atacante.especie.tipos else 1.0
	var eff: float = Efectividad.multiplicador(move.tipo, defensor.especie.tipos)
	var danio: float = ((2.0 * atacante.nivel / 5.0 + 2.0) * (mf * at * move.poder / df) / 50.0 + 2.0) \
		* stab * eff * 0.85
	return ceili(danio / pow_dif)


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
