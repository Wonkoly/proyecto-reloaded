class_name ComandosDev
## Los comandos de la consola dev. Cada uno es una línea de registrar(): nombre, descripción, uso,
## acción (recibe los argumentos y devuelve el texto a mostrar) y, opcional, autocompletado.

const CARPETA_MAPAS: String = "res://assets/extraido/mapas"


static func registrar_todos(c: Node) -> void:
	c.registrar("ayuda", "Lista los comandos o explica uno", "ayuda [comando]", _ayuda.bind(c),
		func(_i: int, t: String) -> PackedStringArray: return _filtrar(c.comandos().map(func(x: Variant) -> String: return x.nombre), t))
	c.registrar("tp", "Va a un mapa (al centro, o a x y)", "tp <mapa> [x y]", _tp.bind(c),
		func(i: int, t: String) -> PackedStringArray: return _filtrar(_mapas(), t) if i == 0 else PackedStringArray())
	c.registrar("mapas", "Lista los mapas extraídos", "mapas [filtro]", _listar_mapas)
	c.registrar("noclip", "Atravesar paredes en el overworld", "noclip", _alternar.bind("dev_noclip", "noclip"))
	c.registrar("velocidad", "Velocidad del juego (1 = normal)", "velocidad <factor>", _velocidad)
	c.registrar("dar", "Agrega un Pokémon al equipo", "dar <especie> <nivel>", _dar,
		func(i: int, t: String) -> PackedStringArray: return _filtrar(_especies(), t) if i == 0 else PackedStringArray())
	c.registrar("curar", "Cura HP y energía del equipo", "curar", _curar)
	c.registrar("nivel", "Cambia el nivel del primer Pokémon del equipo", "nivel <n>", _nivel)
	c.registrar("encuentro", "Batalla ya contra un salvaje", "encuentro <especie> <nivel>", _encuentro.bind(c),
		func(i: int, t: String) -> PackedStringArray: return _filtrar(_especies(), t) if i == 0 else PackedStringArray())
	c.registrar("encuentros", "Activa o desactiva los Pokémon salvajes", "encuentros on|off", _encuentros)
	c.registrar("dificultad", "Fuerza el divisor de daño (PowDif) de los dos lados; 0 = normal", "dificultad <1|2|4|0>", _dificultad)
	c.registrar("historia", "Muestra o cambia banderas de la historia (el mapa se actualiza al momento)", "historia [bandera] [valor]", _historia)
	c.registrar("god", "No recibes daño en batalla", "god", _alternar.bind("dev_god", "god"))
	c.registrar("energia_infinita", "Tu Pokémon tiene la energía siempre llena", "energia_infinita", _alternar.bind("dev_energia_infinita", "energía infinita"))
	c.registrar("pos", "Mapa y posición del jugador", "pos", _pos.bind(c))
	c.registrar("codigo", "Mete un código del original (como Shift+F3)", "codigo <texto>", _codigo.bind(c))
	c.registrar("hora", "Fija la hora del juego (queda quieta) o vuelve a la del sistema", "hora <h>[:mm] | hora real", _hora)
	c.registrar("encuentros_mapa", "Subtablas de encuentros del mapa, cuál vale ahora y la probabilidad de cada especie", "encuentros_mapa", _encuentros_mapa.bind(c))
	c.registrar("simular_encuentros", "Sortea n veces en la posición actual y compara con los pesos esperados", "simular_encuentros <n>", _simular_encuentros.bind(c))
	c.registrar("validar", "Revisa las salidas del mapa actual (destino, llegada, rebote, regreso)", "validar", _validar.bind(c))
	c.registrar("pruebas", "Abre el menú de pruebas (batalla con especies elegidas, overworld)", "pruebas", _escena.bind(c, "res://scenes/debug/menu_pruebas.tscn"))
	c.registrar("titulo", "Vuelve a la pantalla de título", "titulo", _escena.bind(c, "res://scenes/titulo/titulo.tscn"))
	c.registrar("ir", "Ruta más corta hasta un mapa; con tp va al primer mapa de la ruta", "ir <mapa> [tp]", _ir.bind(c),
		func(i: int, t: String) -> PackedStringArray: return _filtrar(ConexionesDev.grafo().get("mapas", {}).keys(), t) if i == 0 else PackedStringArray())


static func _ayuda(args: PackedStringArray, c: Node) -> String:
	if args.size() > 0:
		for x: Variant in c.comandos():
			if x.nombre == args[0].to_lower():
				return "%s — %s\n  uso: %s" % [x.nombre, x.descripcion, x.uso]
		return "No existe el comando \"%s\"" % args[0]
	var lineas: PackedStringArray = []
	for x: Variant in c.comandos():
		lineas.append("[b]%s[/b] — %s" % [x.uso, x.descripcion])
	return "\n".join(lineas)


static func _tp(args: PackedStringArray, c: Node) -> String:
	if args.is_empty():
		return "uso: tp <mapa> [x y]"
	var mapa: String = _resolver_mapa(args[0])
	if mapa == "":
		return "No hay un mapa \"%s\" (mapas para ver la lista)" % args[0]
	var pos: Vector2 = SceneManager.CENTRO
	if args.size() >= 3:
		pos = Vector2(args[1].to_float(), args[2].to_float())
	SceneManager.ir_a_mapa(mapa, pos)
	c.call_deferred("cerrar")
	return "→ %s %s" % [mapa, "" if pos == SceneManager.CENTRO else str(pos)]


static func _hora(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Hora: %s" % Reloj.texto()
	if args[0].to_lower() == "real":
		Reloj.poner_hora_del_sistema()
		return "Hora del sistema: %s" % Reloj.texto()
	var partes: PackedStringArray = args[0].split(":")
	if not partes[0].is_valid_int():
		return "uso: hora <h>[:mm] | hora real"
	Reloj.fijar(partes[0].to_int(), partes[1].to_int() if partes.size() > 1 else 0)
	return "Hora fijada: %s" % Reloj.texto()


const NOMBRES_METODO: PackedStringArray = ["hierba", "surf", "barro", "hierba especial", "caña vieja", "caña buena",
	"supercaña", "hierba invisible", "lava"]
const NOMBRES_HORARIO: PackedStringArray = ["siempre", "día", "noche"]


static func _encuentros_mapa(_args: PackedStringArray, c: Node) -> String:
	var j: Jugador = c.jugador()
	if j == null:
		return "Solo en un mapa del overworld"
	var mapa: Mapa = c.get_tree().current_scene as Mapa
	var tabla: TablaEncuentros = TablaEncuentros.de_mapa(mapa.nombre_original)
	if tabla == null:
		return "%s no tiene encuentros (no hay tabla en el original)" % mapa.nombre_original
	var metodo: int = j.metodo_actual()
	var actual: SubtablaEncuentros = j.subtabla_actual()
	var lineas: PackedStringArray = ["%s, %s, aquí: %s" % [mapa.nombre_original, Reloj.texto(),
		NOMBRES_METODO[metodo] if metodo >= 0 else "sin zona de encuentros"]]
	# Por cada método, la que vale ahora en esta posición (aunque no se esté en esa zona).
	var vigentes: Dictionary = {}
	for m: int in NOMBRES_METODO.size():
		var sub: SubtablaEncuentros = tabla.subtabla(m as SubtablaEncuentros.Metodo, Reloj.es_de_dia(), j.global_position, mapa.cumple)
		if sub:
			vigentes[sub] = true
	for sub: SubtablaEncuentros in tabla.subtablas:
		var marca: String = "[color=#8f8]► AHORA[/color] " if sub == actual else ("[color=#fd8]vale[/color] " if vigentes.has(sub) else "  ")
		var extra: PackedStringArray = []
		if sub.condicion != "":
			extra.append("si " + sub.condicion)
		if sub.zona.has_area():
			extra.append("zona %s" % sub.zona)
		if sub.codigo_muerto:
			extra.append("código muerto del original")
		lineas.append("%s%s, %s, 1/%d %s" % [marca, NOMBRES_METODO[sub.metodo], NOMBRES_HORARIO[sub.horario], sub.frecuencia, " ".join(extra)])
		if vigentes.has(sub):
			lineas.append("    " + _texto_probabilidades(sub.probabilidades(mapa.cumple)))
	return "\n".join(lineas)


static func _texto_probabilidades(prob: Dictionary) -> String:
	var partes: PackedStringArray = []
	for id: int in prob:
		if id != 0:
			var e: PokemonData = Datos.especie(id)
			partes.append("%s %.1f%%" % [e.nombre if e else "#%d" % id, prob[id] * 100.0])
	partes.append("sin encuentro %.1f%%" % (prob.get(0, 0.0) * 100.0))
	return ", ".join(partes)


static func _simular_encuentros(args: PackedStringArray, c: Node) -> String:
	var j: Jugador = c.jugador()
	if j == null:
		return "Solo en un mapa del overworld"
	var n: int = args[0].to_int() if args.size() > 0 and args[0].is_valid_int() else 1000
	var mapa: Mapa = c.get_tree().current_scene as Mapa
	var sub: SubtablaEncuentros = j.subtabla_actual()
	if sub == null:
		var tabla: TablaEncuentros = TablaEncuentros.de_mapa(mapa.nombre_original)
		sub = tabla.subtabla(SubtablaEncuentros.Metodo.HIERBA, Reloj.es_de_dia(), j.global_position, mapa.cumple) if tabla else null
		if sub == null:
			return "No hay subtabla de encuentros aquí"
	var cuenta: Dictionary = {}
	for i: int in n:
		var e: EncuentroSalvaje = sub.sortear(mapa.cumple)
		var id: int = e.id_especie if e else 0
		cuenta[id] = cuenta.get(id, 0) + 1
	var esperado: Dictionary = sub.probabilidades(mapa.cumple)
	var lineas: PackedStringArray = ["%d sorteos en %s (%s, %s):" % [n, NOMBRES_METODO[sub.metodo], NOMBRES_HORARIO[sub.horario], Reloj.texto()]]
	var peor: float = 0.0
	for id: int in esperado:
		var obs: float = float(cuenta.get(id, 0)) / n
		peor = maxf(peor, absf(obs - esperado[id]))
		var e: PokemonData = Datos.especie(id) if id != 0 else null
		lineas.append("  %-14s esperado %5.1f%%  salió %5.1f%%" % ["sin encuentro" if id == 0 else (e.nombre if e else "#%d" % id), esperado[id] * 100.0, obs * 100.0])
	lineas.append("diferencia máxima: %.1f puntos" % (peor * 100.0))
	return "\n".join(lineas)


static func _validar(_args: PackedStringArray, c: Node) -> String:
	var j: Jugador = c.jugador()
	if j == null:
		return "Solo en un mapa del overworld"
	if ConexionesDev.grafo().is_empty():
		return "Falta data/extraido/conexiones.json (python3 tools/extraer.py --solo conexiones)"
	return ConexionesDev.validar(c.get_tree().current_scene as Mapa)


static func _ir(args: PackedStringArray, c: Node) -> String:
	if args.is_empty():
		return "uso: ir <mapa> [tp]"
	var destino: String = ConexionesDev.resolver(args[0])
	if destino == "":
		return "No hay un mapa \"%s\" en el grafo" % args[0]
	var camino: Array[Dictionary] = ConexionesDev.ruta(GameState.mapa_actual, destino)
	if camino.is_empty():
		return "No hay ruta de %s a %s (o ya estás ahí)" % [GameState.mapa_actual, destino]
	var lineas: PackedStringArray = ["%s → %s: %d pasos" % [GameState.mapa_actual, destino, camino.size()]]
	for con: Dictionary in camino:
		var req: Dictionary = con["requisitos"]
		var pide: PackedStringArray = []
		if str(req["historia"]) != "":
			pide.append("historia")
		for r: Variant in req["terreno"]:
			if not str(r).begins_with("no:"):
				pide.append(str(r))
			elif not pide.has("historia"):
				pide.append("historia")
		lineas.append("  %s → %s por %s%s" % [con["origen"], con["destino"], con["salida"]["tipo"],
			(" (requiere " + ", ".join(pide) + ")") if not pide.is_empty() else ""])
	if args.size() > 1 and args[1].to_lower() == "tp":
		var primero: Dictionary = camino[0]
		SceneManager.ir_a_mapa(primero["destino"], ConexionesDev.llegada(primero))
		c.call_deferred("cerrar")
		lineas.append("→ %s" % primero["destino"])
	return "\n".join(lineas)


static func _listar_mapas(args: PackedStringArray) -> String:
	var filtro: String = _normalizar(args[0]) if args.size() > 0 else ""
	var lista: PackedStringArray = []
	for m: String in _mapas():
		if filtro == "" or filtro in _normalizar(m):
			lista.append(m)
	return "%d mapas: %s" % [lista.size(), "  ".join(lista)]


static func _alternar(_args: PackedStringArray, propiedad: String, nombre: String) -> String:
	GameState.set(propiedad, not GameState.get(propiedad))
	return "%s: %s" % [nombre, "sí" if GameState.get(propiedad) else "no"]


static func _velocidad(args: PackedStringArray) -> String:
	if args.size() > 0 and args[0].is_valid_float():
		Engine.time_scale = clampf(args[0].to_float(), 0.1, 16.0)
	return "velocidad: x%s" % Engine.time_scale


static func _dar(args: PackedStringArray) -> String:
	var especie: PokemonData = _especie(args[0] if args.size() > 0 else "")
	if especie == null:
		return "uso: dar <especie> <nivel> (id o nombre)"
	if GameState.equipo.size() >= 6:
		return "El equipo ya tiene 6 Pokémon"
	var p: PokemonInstance = PokemonInstance.crear(especie, clampi(args[1].to_int() if args.size() > 1 else 5, 1, 100))
	GameState.equipo.append(p)
	return "%s nivel %d agregado al equipo (%d/6)" % [especie.nombre, p.nivel, GameState.equipo.size()]


static func _escena(_args: PackedStringArray, c: Node, ruta: String) -> String:
	c.cerrar()
	AudioManager.detener_musica()
	c.get_tree().change_scene_to_file.call_deferred(ruta)
	return "Abriendo " + ruta.get_file().get_basename()


static func _curar(_args: PackedStringArray) -> String:
	for p: PokemonInstance in GameState.equipo:
		p.hp_actual = p.calcular_stats()["hp"]
		p.energia_actual = p.calcular_energia_maxima()
	return "Equipo curado"


static func _nivel(args: PackedStringArray) -> String:
	if GameState.equipo.is_empty() or args.is_empty() or not args[0].is_valid_int():
		return "uso: nivel <n>"
	var p: PokemonInstance = GameState.equipo[0]
	p.nivel = clampi(args[0].to_int(), 1, 100)
	p.hp_actual = p.calcular_stats()["hp"]
	p.energia_actual = p.calcular_energia_maxima()
	return "%s ahora es nivel %d" % [p.especie.nombre, p.nivel]


static func _encuentro(args: PackedStringArray, c: Node) -> String:
	var especie: PokemonData = _especie(args[0] if args.size() > 0 else "")
	if especie == null:
		return "uso: encuentro <especie> <nivel>"
	if not get_tree_static().current_scene is Mapa:
		return "Hay que estar en el overworld"
	if GameState.pokemon_para_combatir() == null:
		return "No tienes Pokémon que puedan combatir (curar)"
	var salvaje: PokemonInstance = PokemonInstance.crear(especie, clampi(args[1].to_int() if args.size() > 1 else 5, 1, 100))
	SceneManager.ir_a_batalla(salvaje, c.jugador())
	c.call_deferred("cerrar")
	return "¡%s salvaje nivel %d!" % [especie.nombre, salvaje.nivel]


static func _encuentros(args: PackedStringArray) -> String:
	if args.size() > 0:
		GameState.dev_encuentros = args[0].to_lower() in ["on", "si", "sí", "1"]
	return "encuentros: %s" % ("sí" if GameState.dev_encuentros else "no")


static func _dificultad(args: PackedStringArray) -> String:
	if args.size() > 0 and args[0].is_valid_int() and args[0].to_int() in [0, 1, 2, 4]:
		GameState.dev_pow_dif = args[0].to_int()
	return "PowDif: %s" % ("el de la dificultad (%d/%d)" % [GameState.pow_dif(1), GameState.pow_dif(2)]
		if GameState.dev_pow_dif == 0 else str(GameState.dev_pow_dif))


static func _historia(args: PackedStringArray) -> String:
	if args.size() >= 2 and args[1].is_valid_int():
		GameState.cambiar_historia(args[0], args[1].to_int())
	elif args.size() == 1:
		return "%s = %d" % [args[0], GameState.bandera(args[0])]
	return "historia: %s" % str(GameState.historia)


static func _codigo(args: PackedStringArray, c: Node) -> String:
	if args.is_empty():
		return "uso: codigo <texto> (los del original: guarderia, cara, mote, cheats, me rindo...)"
	c.call_deferred("cerrar")  # los códigos abren sus propios cuadros
	var trucos: Node = c.get_node("/root/Trucos")
	trucos.call_deferred("ejecutar", " ".join(args))
	return "código %s" % " ".join(args).to_upper()


static func _pos(_args: PackedStringArray, c: Node) -> String:
	var j: Jugador = c.jugador()
	if j == null:
		return "No estás en el overworld (escena %s)" % get_tree_static().current_scene.name
	return "%s %s mira %d" % [GameState.mapa_actual, str(j.global_position.round()), j.mira]


# Ayudantes -----------------------------------------------------------------------------------

static func get_tree_static() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _mapas() -> PackedStringArray:
	var lista: PackedStringArray = []
	for f: String in DirAccess.get_files_at(CARPETA_MAPAS):
		if f.ends_with(".tscn"):
			lista.append(f.get_basename())
	return lista


static func _resolver_mapa(texto: String) -> String:
	var buscado: String = _normalizar(texto)
	var parecidos: PackedStringArray = []
	for m: String in _mapas():
		if _normalizar(m) == buscado:
			return m
		if _normalizar(m).begins_with(buscado):
			parecidos.append(m)
	return parecidos[0] if parecidos.size() == 1 else ""


static func _especies() -> PackedStringArray:
	var lista: PackedStringArray = []
	for f: String in DirAccess.get_files_at(Datos.CARPETA_POKEMON):
		if f.ends_with(".tres"):
			lista.append(f.get_basename().substr(5))  # 0016_pidgey → pidgey
	return lista


## Especie por id (16) o por nombre (pidgey).
static func _especie(texto: String) -> PokemonData:
	if texto.is_valid_int():
		return Datos.especie(texto.to_int())
	var buscado: String = _normalizar(texto)
	for f: String in DirAccess.get_files_at(Datos.CARPETA_POKEMON):
		if f.ends_with(".tres") and _normalizar(f.get_basename().substr(5)) == buscado:
			return load(Datos.CARPETA_POKEMON.path_join(f)) as PokemonData
	return null


static func _normalizar(texto: String) -> String:
	return texto.to_lower().replace("_", "").replace(" ", "")


static func _filtrar(lista: Array, texto: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for x: Variant in lista:
		if _normalizar(str(x)).begins_with(_normalizar(texto)):
			out.append(str(x))
	return out
