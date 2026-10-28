class_name Mochila
## La mochila (tecla O, key_menu_mochila): los objetos por bolsillo (←/→) con su descripción; los de
## curar se usan sobre un Pokémon del equipo (UseDirectObject).

static func abrir(desde: Node) -> void:
	var pestana: int = 0
	var sel: int = 0
	var titulos: Array = Inventario.BOLSILLOS.map(func(x: String) -> String: return Inventario.NOMBRES_BOLSILLO[x])
	while true:
		var ids: Array[int] = Inventario.de_bolsillo(Inventario.BOLSILLOS[pestana])
		var filas: Array = ids.map(func(id: int) -> Dictionary: return {"texto": Inventario.nombre(id),
			"derecha": "x%d" % Inventario.cantidad(id), "desc": Inventario.descripcion(id)})
		sel = await MenuLista.elegir(desde, "", filas,
			{"pie": "%s: %d €" % [Textos.linea("txt_menu", 852), GameState.dinero], "pestanas": titulos, "pestana": pestana, "inicial": sel})
		if sel == MenuLista.IZQUIERDA or sel == MenuLista.DERECHA:
			pestana = (pestana + (1 if sel == MenuLista.DERECHA else -1) + titulos.size()) % titulos.size()
			sel = 0
			continue
		if sel < 0:
			return
		await _usar(desde, ids[sel])


static func _usar(desde: Node, id: int) -> void:
	if not Inventario.es_de_curar(id):
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 291))
		return
	var filas: Array = GameState.equipo.map(func(p: PokemonInstance) -> Dictionary:
		var nombre: String = p.apodo if p.apodo != "" else p.especie.nombre
		return {"texto": "%s Nv.%d" % [nombre, p.nivel], "derecha": "%d/%d" % [p.hp_actual, p.calcular_stats()["hp"]]})
	var i: int = await MenuLista.elegir(desde, Inventario.nombre(id), filas)
	if i < 0:
		return
	var p: PokemonInstance = GameState.equipo[i]
	var curado: int = Inventario.usar_en(id, p)
	if curado <= 0:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 291))
		return
	Inventario.quitar(id)
	AudioManager.efecto_ui("snd_curar")
	await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 511), p.apodo if p.apodo != "" else p.especie.nombre, str(curado)))
