class_name MenuPrincipal
## El menú principal (Enter, key_menu_principal, KeyActionsExplorer): las mismas opciones del
## original en su orden; las que aún no existen avisan.


static func abrir(desde: Node, mapa: Mapa) -> void:
	var opciones: Array[int] = []  # valueSelection del original
	if GameState.bandera("fy_002") != 0 and not GameState.equipo.is_empty():
		opciones.append(1)  # Pokémon
	opciones.append(2)  # Mochila
	if not GameState.pokedex.is_empty():
		opciones.append(3)  # Pokédex
	opciones.append_array([5, 8, 9, 13])  # Entrenador, Opciones, Guardar, Salir
	var textos: Dictionary[int, int] = {1: 70, 2: 71, 3: 69, 5: 72, 8: 76, 9: 75, 13: 78}
	var sel: int = await MenuLista.elegir(desde, "", opciones.map(func(o: int) -> Dictionary:
		return {"texto": Textos.linea("txt_menu", textos[o])}))
	if sel < 0:
		return
	match opciones[sel]:
		1: await MenuEquipo.abrir(desde)
		2: await Mochila.abrir(desde)
		3: await Pokedex.abrir(desde)
		5: await _entrenador(desde)
		9: if mapa: await mapa.guardar_partida()
		13:
			if await CuadroOriginal.preguntar(desde, "¿Volver a la pantalla de título?", true):
				desde.get_tree().change_scene_to_file("res://scenes/titulo/titulo.tscn")
		_: await CuadroOriginal.mensaje(desde, "Todavía no está disponible.")


## La ficha de entrenador (room 44): nombre, dinero, Pokédex y tiempo de juego.
static func _entrenador(desde: Node) -> void:
	var t: int = int(GameState.tiempo_juego)
	var capturados: int = GameState.pokedex.values().filter(func(v: int) -> bool: return v >= 2).size()
	await MenuLista.elegir(desde, Textos.linea("txt_menu", 72), [
		{"texto": "Nombre", "derecha": GameState.nombre_jugador},
		{"texto": "Dinero", "derecha": "%d €" % GameState.dinero},
		{"texto": "Pokédex", "derecha": "%d vistos, %d capturados" % [GameState.pokedex.size(), capturados]},
		{"texto": "Tiempo de juego", "derecha": "%d:%02d" % [t / 3600, (t / 60) % 60]},
	])
