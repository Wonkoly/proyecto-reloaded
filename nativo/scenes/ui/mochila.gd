class_name Mochila
## La mochila (tecla O, key_menu_mochila): los objetos por bolsillo (←/→) con su descripción; los de
## curar se usan sobre un Pokémon del equipo (UseDirectObject).

static func abrir(desde: Node, pestana: int = 0) -> void:
	pestana = maxi(pestana, 0)
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
	if Inventario.bolsillo(id) == "ball":
		# Asigna la ball a la tecla B (global.ball_asign; TextMenu 144 "Ball asignada:").
		GameState.ball_asignada = id
		await CuadroOriginal.mensaje(desde, "%s %s" % [Textos.linea("txt_menu", 144), Inventario.nombre(id)])
		return
	if id == Inventario.CARAMELO_RARO or id in Inventario.VITAMINAS or Inventario.hace_evolucionar(id) \
			or Inventario.movimiento_que_ensena(id):
		var j: int = await MenuLista.elegir(desde, Inventario.nombre(id), GameState.equipo.map(MenuEquipo.fila))
		if j >= 0:
			await _usar_en_pokemon(desde, id, GameState.equipo[j])
		return
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


## UseObject: Caramelo Raro (sube un nivel, aprende el ataque de ese nivel y puede evolucionar) y
## objetos que hacen evolucionar (pregunta y evoluciona).
static func _usar_en_pokemon(desde: Node, id: int, p: PokemonInstance) -> void:
	if p.hp_actual <= 0:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 531))
		return
	if id == Inventario.CARAMELO_RARO:
		if p.nivel >= 100:
			await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 510))
			return
		Inventario.quitar(id)
		p.bajar_iv()  # BajaInstructionValue
		p.nivel += 1
		p.experiencia = p.exp_para_nivel(p.nivel)
		p.hp_actual = mini(p.hp_actual, p.calcular_stats()["hp"])
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 540), Progreso.nombre(p), str(p.nivel)))
		for m: MoveData in p.movimientos_de_nivel(p.nivel):
			await Progreso.aprender(desde, p, m)
		var subido: Array[PokemonInstance] = [p]
		await Evolucion.revisar_equipo(desde, subido)
		return
	if id in Inventario.VITAMINAS:
		var d: int = Inventario.VITAMINAS[id]
		if p.subir_iv(d) < 0:
			await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 510))
			return
		Inventario.quitar(id)
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", Inventario.TEXTO_VITAMINA[d]), Progreso.nombre(p)))
		return
	var move: MoveData = Inventario.movimiento_que_ensena(id)
	if move:
		await _ensenar(desde, id, p, move)
		return
	var nueva: PokemonData = Inventario.evolucion_con(id, p)
	if nueva == null:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 510))
		return
	if await CuadroOriginal.preguntar(desde, Textos.par(Textos.linea("txt_menu", 543), Progreso.nombre(p), Inventario.nombre(id))):
		Inventario.quitar(id)
		await Evolucion.evolucionar(desde, p, nueva, false)  # con objeto no se cancela


## UseObject con una MT o un DT: si la especie lo puede aprender (AprendeAtaquePorMT), confirma (207) y lo
## aprende con el menú para olvidar uno; la MT no se gasta. Ya lo sabe: 559; no puede: 560.
static func _ensenar(desde: Node, id: int, p: PokemonInstance, move: MoveData) -> void:
	var puede: bool = p.especie.movimientos_aprendibles.any(func(m: MovimientoAprendible) -> bool: return m.move == move)
	if not puede:
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 560), Progreso.nombre(p), move.nombre))
		return
	if move in p.movimientos:
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 559), Progreso.nombre(p), move.nombre))
		return
	if await CuadroOriginal.preguntar(desde, Textos.par(Textos.linea("txt_menu", 207), move.nombre)):
		if await Progreso.aprender(desde, p, move) and id > 5000:
			Inventario.quitar(id)  # el DT se gasta solo si lo aprende (ObjetoUsado)
