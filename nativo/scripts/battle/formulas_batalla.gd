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
