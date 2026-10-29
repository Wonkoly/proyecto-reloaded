class_name CajaPC
## El PC de los Centros (obj_PC, PCKeyActions): "Cajas Pokémon" para dejar y sacar Pokémon de las
## cajas (la sala de cajas del original, room 8, todavía con listas). El PC de ítems está pendiente.


## PCKeyActions: "Has encendido el PC." y el sistema a elegir.
static func usar(desde: Node) -> void:
	if GameState.bandera("fy_002") == 0:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_dialog", 4479))
		return
	await CuadroOriginal.mensaje(desde, Textos.linea("txt_dialog", 4480))
	var q: int = await MenuLista.elegir(desde, Textos.linea("txt_dialog", 4481), [
		{"texto": Textos.linea("txt_dialog", 4482)}, {"texto": Textos.linea("txt_dialog", 4483)},
		{"texto": Textos.linea("txt_dialog", 4484)}])
	if q == 0:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_dialog", 4485))
		await cajas(desde)
	elif q == 1:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 291))


static func cajas(desde: Node) -> void:
	while true:
		var accion: int = await MenuLista.elegir(desde, Textos.linea("txt_dialog", 4482),
			[{"texto": "Sacar Pokémon"}, {"texto": "Dejar Pokémon"}])
		if accion < 0:
			return
		if accion == 0:
			await _sacar(desde)
		else:
			await _dejar(desde)


static func _sacar(desde: Node) -> void:
	var c: int = 0
	while true:
		var filas: Array = []
		for k: int in GameState.cajas.size():
			var n: int = GameState.cajas[k].filter(func(p: Variant) -> bool: return p != null).size()
			filas.append({"texto": GameState.nombres_cajas[k], "derecha": "%d/%d" % [n, GameState.POKEMON_POR_CAJA]})
		c = await MenuLista.elegir(desde, "Cajas", filas, {"inicial": c})
		if c < 0:
			return
		while true:
			var huecos: Array[int] = []
			for i: int in GameState.POKEMON_POR_CAJA:
				if GameState.cajas[c][i] != null:
					huecos.append(i)
			if huecos.is_empty():
				break
			var i: int = await MenuLista.elegir(desde, GameState.nombres_cajas[c],
				huecos.map(func(h: int) -> Dictionary: return MenuEquipo.fila(GameState.cajas[c][h])))
			if i < 0:
				break
			var p: PokemonInstance = GameState.cajas[c][huecos[i]]
			var op: int = await MenuLista.elegir(desde, Progreso.nombre(p), [{"texto": "Sacar"}, {"texto": "Datos"}, {"texto": "Liberar"}])
			if op == 0:
				if GameState.equipo.size() >= 6:
					await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 245))
				else:
					GameState.equipo.append(p)
					GameState.cajas[c][huecos[i]] = null
			elif op == 1:
				await MenuEquipo.ficha(desde, p)
			elif op == 2 and await CuadroOriginal.preguntar(desde, "¿Liberar a %s?" % Progreso.nombre(p)):
				GameState.cajas[c][huecos[i]] = null
				await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 249))


static func _dejar(desde: Node) -> void:
	while true:
		if GameState.equipo.size() <= 1:
			return  # no se puede quedar sin Pokémon
		var i: int = await MenuLista.elegir(desde, "Dejar Pokémon", GameState.equipo.map(MenuEquipo.fila))
		if i < 0:
			return
		var p: PokemonInstance = GameState.equipo[i]
		var hueco: Array[int] = GameState.guardar_en_pc(p)
		if hueco.is_empty():
			await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 248))
			return
		GameState.equipo.remove_at(i)
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 246), GameState.nombres_cajas[hueco[0]], str(hueco[1] + 1)))
