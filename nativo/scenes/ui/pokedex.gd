class_name Pokedex
## La Pokédex (F12, key_menu_pokedex): las especies hasta la última vista, con las vistas por su
## nombre y las capturadas marcadas con * (arriba: capturadas/vistas); al elegir una vista, su ficha (categoría y descripción).

const VISTO: int = 1
const CAPTURADO: int = 2


static func abrir(desde: Node) -> void:
	if GameState.pokedex.is_empty():
		return
	var ultimo: int = GameState.pokedex.keys().max()
	var vistos: int = GameState.pokedex.values().filter(func(v: int) -> bool: return v >= VISTO).size()
	var capturados: int = GameState.pokedex.values().filter(func(v: int) -> bool: return v >= CAPTURADO).size()
	var filas: Array = []
	for n: int in range(1, ultimo + 1):
		var estado: int = GameState.pokedex.get(n, 0)
		var entrada: Array = Datos.por_pokedex(n)
		filas.append({"texto": "%03d  %s" % [n, entrada[1] if not entrada.is_empty() and estado >= VISTO else "----------"],
			"derecha": "*" if estado >= CAPTURADO else "", "activo": estado >= VISTO})
	var sel: int = 0
	while true:
		sel = await MenuLista.elegir(desde, Textos.linea("txt_menu", 69), filas,
			{"inicial": sel, "pie": "%d/%d" % [capturados, vistos]})
		if sel < 0:
			return
		var entrada: Array = Datos.por_pokedex(sel + 1)
		if entrada.is_empty() or GameState.pokedex.get(sel + 1, 0) < VISTO:
			continue
		var e: PokemonData = Datos.especie(int(entrada[0]))
		if e == null:
			continue
		var tipos: String = " / ".join(e.tipos.map(func(t: int) -> String: return Tipos.Tipo.keys()[t].capitalize()))
		await MenuLista.elegir(desde, "%03d %s" % [sel + 1, e.nombre], [
			{"texto": "Pokémon %s" % Textos.linea("dex_espec", sel + 1), "derecha": tipos,
				"desc": Textos.linea("dex_info", sel + 1)},
		])
