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
	opciones.append(5)  # Entrenador
	if GameState.tiene_medalla(1):
		opciones.append(6)  # Habilidades
	if GameState.bandera("movil") == 1 or GameState.objetos.has(Vuelo.OBJETO_MAPA):
		opciones.append(7)  # Usar Item
	opciones.append_array([8, 9, 13])  # Opciones, Guardar, Salir
	var textos: Dictionary[int, int] = {1: 70, 2: 71, 3: 69, 5: 72, 6: 77, 7: 73, 8: 76, 9: 75, 13: 78}
	var sel: int = await MenuLista.elegir(desde, "", opciones.map(func(o: int) -> Dictionary:
		return {"texto": Textos.linea("txt_menu", textos[o])}))
	if sel < 0:
		return
	match opciones[sel]:
		1: await MenuEquipo.abrir(desde)
		2: await Mochila.abrir(desde)
		3: await Pokedex.abrir(desde)
		5: await _entrenador(desde)
		6: await habilidades(desde)
		7: await usar_item(desde)
		9: if mapa: await mapa.guardar_partida()
		13:
			if await CuadroOriginal.preguntar(desde, "¿Volver a la pantalla de título?", true):
				desde.get_tree().change_scene_to_file("res://scenes/titulo/titulo.tscn")
		_: await CuadroOriginal.mensaje(desde, "Todavía no está disponible.")


## Habilidades (key_ex_hab_externas): las habilidades de campo que permiten las medallas, en el orden
## del original (valueSelection, TextMenu 79-96). Cada una hace lo mismo que su tecla.
const HABILIDADES: Array[Array] = [  # [valueSelection, medalla, TextMenu]
	[1, 2, 79], [2, 4, 80], [3, 6, 81], [4, 5, 82], [5, 3, 83], [6, 1, 84], [7, 7, 85], [8, 8, 87],
	[9, 5, 88], [10, 1, 89], [11, 3, 90], [12, 2, 91], [13, 4, 92], [14, 7, 93], [15, 6, 94],
	[16, 8, 95], [17, 8, 96]]


static func habilidades(desde: Node) -> void:
	var lista: Array = HABILIDADES.filter(func(h: Array) -> bool: return GameState.tiene_medalla(h[1]))
	var sel: int = await MenuLista.elegir(desde, Textos.linea("txt_menu", 77), lista.map(func(h: Array) -> Dictionary:
		return {"texto": Textos.linea("txt_menu", h[2])}))
	var j: Jugador = DevConsole.jugador()
	if sel < 0 or j == null:
		return
	match int(lista[sel][0]):
		1, 4, 6:  # Corte, Fuerza, Golpe Roca: el obstáculo de enfrente
			var obs: Obstaculo = j.obstaculo_delante({1: KEY_1, 4: KEY_4, 6: KEY_6}[int(lista[sel][0])])
			if obs:
				await obs.usar(j)
		2: await Vuelo.intentar(j)
		3, 16: await j.intentar_surf()  # Surf u Ola Lava, según lo que haya enfrente
		5:
			var m: Mapa = j._mapa()
			if m and m.has_node("Oscuridad"):
				await (m.get_node("Oscuridad") as Oscuridad).usar_destello(j)
		7: await j.intentar_buceo()
		9: await j.alternar_montura()
		14:
			if j._roca_trepable():
				await j.intentar_treparrocas()
		17:
			if j.surfeando() and j._toca(Jugador.CASCADAS, Vector2.ZERO, 5.0):
				await j.intentar_cascada()
		_: await CuadroOriginal.mensaje(desde, "Todavía no está disponible.")


## Usar Item (key_ex_use_items): los objetos clave que se usan desde el menú.
static func usar_item(desde: Node) -> void:
	var opciones: Array[int] = []
	if GameState.bandera("movil") == 1:
		opciones.append(2303)  # SmartPhone
	if GameState.objetos.has(Vuelo.OBJETO_MAPA):
		opciones.append(2304)  # Mapa
	if opciones.is_empty():
		return
	var sel: int = await MenuLista.elegir(desde, Textos.linea("txt_menu", 73), opciones.map(func(o: int) -> Dictionary:
		return {"texto": Textos.linea("txt_menu", o)}))
	if sel < 0:
		return
	match opciones[sel]:
		2304: await PantallaVuelo.abrir(desde, false)
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
