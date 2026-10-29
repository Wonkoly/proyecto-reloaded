class_name MenuEquipo
## El equipo (tecla Espacio, key_menu_pokemon): cada Pokémon con su nivel y PS; al elegir uno, su
## ficha o cambiarlo de lugar. La pantalla del original (con sus páginas de datos) está pendiente.


static func fila(p: PokemonInstance) -> Dictionary:
	return {"texto": "%s  Nv.%d" % [Progreso.nombre(p), p.nivel],
		"derecha": "%d/%d" % [p.hp_actual, p.calcular_stats()["hp"]], "activo": p.hp_actual > 0}


static func abrir(desde: Node) -> void:
	var sel: int = 0
	while not GameState.equipo.is_empty():
		sel = await MenuLista.elegir(desde, Textos.linea("txt_menu", 70), GameState.equipo.map(fila), {"inicial": sel})
		if sel < 0:
			return
		var accion: int = await MenuLista.elegir(desde, Progreso.nombre(GameState.equipo[sel]),
			[{"texto": "Datos"}, {"texto": "Mover"}])
		if accion == 0:
			await ficha(desde, GameState.equipo[sel])
		elif accion == 1:
			var otro: int = await MenuLista.elegir(desde, "¿A qué lugar?", GameState.equipo.map(fila), {"inicial": sel})
			if otro >= 0 and otro != sel:
				var p: PokemonInstance = GameState.equipo[sel]
				GameState.equipo[sel] = GameState.equipo[otro]
				GameState.equipo[otro] = p
				sel = otro


## LoadInfoPokemon*: especie, tipos, experiencia, stats y ataques (con su energía).
static func ficha(desde: Node, p: PokemonInstance) -> void:
	var stats: Dictionary[String, int] = p.calcular_stats()
	var tipos: String = " / ".join(p.especie.tipos.map(func(t: int) -> String: return Tipos.Tipo.keys()[t].capitalize()))
	var falta: int = p.exp_para_nivel(p.nivel + 1) - p.experiencia if p.nivel < 100 else 0
	var filas: Array = [
		{"texto": "N.º %03d %s" % [p.especie.numero_pokedex, p.especie.nombre]},
		{"texto": "Tipo", "derecha": tipos},
		{"texto": "Nivel %d" % p.nivel, "derecha": "Exp. %d" % p.experiencia},
		{"texto": "Para subir", "derecha": str(falta)},
		{"texto": "PS", "derecha": "%d/%d" % [p.hp_actual, stats["hp"]]},
		{"texto": "Energía", "derecha": "%d/%d" % [p.energia_actual, p.calcular_energia_maxima()]},
		{"texto": "Ataque", "derecha": str(stats["ataque"])},
		{"texto": "Defensa", "derecha": str(stats["defensa"])},
		{"texto": "At. Esp.", "derecha": str(stats["ataque_esp"])},
		{"texto": "Def. Esp.", "derecha": str(stats["defensa_esp"])},
		{"texto": "Velocidad", "derecha": str(stats["velocidad"])},
	]
	for m: MoveData in p.movimientos:
		filas.append({"texto": m.nombre, "derecha": "%s %s E%d" % [Tipos.Tipo.keys()[m.tipo].capitalize(),
			str(m.poder) if m.poder > 0 else "-", m.costo_energia], "desc": m.descripcion})
	await MenuLista.elegir(desde, Progreso.nombre(p), filas, {"ancho": 300})
