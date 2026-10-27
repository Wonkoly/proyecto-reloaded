extends Node
## Ejecuta los eventos de la historia (archivos .evento; formato en docs/eventos.md).
##
## Un NPC tiene evento si existe <carpeta>/<mapa>/<nombre del nodo>.evento, buscando primero en
## data/eventos/ (los tuyos, versionados) y luego en data/extraido/eventos/ (los que genera
## tools/extraer.py desde el original). Para cambiar la historia se copia el generado a data/eventos/ y
## se edita: el extractor nunca toca esa carpeta.
## Mientras un evento corre, el jugador no se mueve (como global.wait en el original).

const PROPIOS: String = "res://data/eventos"
const GENERADOS: String = "res://data/extraido/eventos"
## Palabras de las condiciones que no son banderas.
const PALABRAS: Dictionary[String, String] = {"y": "and", "o": "or", "no": "not", "verdadero": "true",
	"falso": "false", "and": "and", "or": "or", "not": "not", "true": "true", "false": "false"}
const DIRECCIONES: Dictionary[String, Vector2] = {"izquierda": Vector2.LEFT, "derecha": Vector2.RIGHT,
	"arriba": Vector2.UP, "abajo": Vector2.DOWN}

## Termina un combate pedido por un evento (SceneManager lo emite al volver al mapa).
signal combate_terminado(gano: bool)

var en_curso: bool = false
## Resultado del último combate (la condición "gano").
var gano: bool = false
var _cache: Dictionary[String, Evento] = {}
## El NPC del evento en curso: mapa y nombre del nodo (se vuelve a buscar tras un combate).
var _npc_nombre: String = ""
var _detener: bool = false


## El evento de un nodo del mapa, o null si no tiene.
func de_nodo(mapa: String, nodo: String) -> Evento:
	var archivo: String = "%s/%s.evento" % [SceneManager.snake(mapa), nodo]
	for base: String in [PROPIOS, GENERADOS]:
		var ruta: String = base.path_join(archivo)
		if FileAccess.file_exists(ruta):
			if not _cache.has(ruta):
				_cache[ruta] = Evento.desde_archivo(ruta)
			return _cache[ruta]
	return null


## Corre el evento con `npc` como quien habla. Devuelve false si tenía errores.
func ejecutar(evento: Evento, npc: Npc = null) -> bool:
	if not evento.errores.is_empty():
		for e: String in evento.errores:
			push_error("Evento: " + e)
		return false
	en_curso = true
	_detener = false
	_npc_nombre = String(npc.name) if npc else ""
	await _bloque(evento.ordenes, evento.ruta)
	en_curso = false
	return true


func _bloque(ordenes: Array, ruta: String) -> void:
	for o: Dictionary in ordenes:
		if _detener:
			return
		if o.orden == "si":
			await _si(o, ruta)
		else:
			await _orden(o, ruta)


func _si(o: Dictionary, ruta: String) -> void:
	for rama: Array in o.ramas:
		if await condicion(rama[0], ruta, o.linea):
			await _bloque(rama[1], ruta)
			return
	await _bloque(o.sino, ruta)


## Una condición: banderas por nombre (trainer_2 == 0), números, y/o/no, "gano" (el último combate)
## y pregunta "¿texto?" (pregunta Sí/No).
func condicion(texto: String, ruta: String = "", linea: int = 0) -> bool:
	if texto.begins_with("pregunta "):
		var partes: PackedStringArray = Evento.partir(texto)
		return await CuadroOriginal.preguntar(self, _texto(partes.slice(1)))
	var e := Expression.new()
	if e.parse(_expresion(texto), ["h", "gano"]) != OK:
		_aviso(ruta, linea, "condición inválida: " + texto)
		return false
	var v: Variant = e.execute([GameState.historia, gano])
	if e.has_execute_failed():
		_aviso(ruta, linea, "no se pudo evaluar: " + texto)
		return false
	return bool(v)


## Una condición sin pregunta (no espera): para los datos (MiembroEquipo.condicion).
func condicion_simple(texto: String) -> bool:
	var e := Expression.new()
	if e.parse(_expresion(texto), ["h", "gano"]) != OK:
		return false
	return bool(e.execute([GameState.historia, gano]))


## La condición como expresión de Godot: cada palabra que no es número ni palabra clave es una bandera.
static func _expresion(texto: String) -> String:
	var r := RegEx.create_from_string("\"[^\"]*\"|[A-Za-z_áéíóúñÁÉÍÓÚÑ][A-Za-z0-9_áéíóúñÁÉÍÓÚÑ\\[\\]]*")
	var out: String = ""
	var pos: int = 0
	for m: RegExMatch in r.search_all(texto):
		out += texto.substr(pos, m.get_start() - pos)
		var w: String = m.get_string()
		if w.begins_with("\""):
			out += w
		elif w == "gano":
			out += "gano"
		elif PALABRAS.has(w):
			out += " %s " % PALABRAS[w]
		else:
			out += 'h.get("%s", 0)' % w.replace("[", "_").replace("]", "")
		pos = m.get_end()
	return out + texto.substr(pos)


func _orden(o: Dictionary, ruta: String) -> void:
	var a: PackedStringArray = o.args
	var npc: Npc = _npc()
	var jugador: Jugador = _jugador()
	match o.orden:
		"decir":
			if npc:
				await CajaDialogo.decir(npc, _texto(a), npc.sprindex, npc.nombre)
			else:
				await CajaDialogo.decir(self, _texto(a))
		"narrar":
			await CajaDialogo.decir(self, _texto(a))
		"exclamacion":
			if npc:
				await npc.exclamacion()
		"mirar_jugador":
			if npc and jugador:
				npc.mirar_a(jugador.global_position)
		"jugador_mira_npc":
			if npc and jugador:
				jugador.mirar_a(npc.global_position)
		"bandera":
			_bandera(a, ruta, o.linea)
		"dinero":  # dinero +100 | dinero -50 | dinero = 1000
			var texto_v: String = "".join(a).replace(" ", "")
			if texto_v.begins_with("="):
				GameState.dinero = maxi(0, int(texto_v.substr(1)))
			else:
				GameState.dinero = maxi(0, GameState.dinero + int(texto_v))
		"curar":
			for p: PokemonInstance in GameState.equipo:
				p.hp_actual = p.calcular_stats()["hp"]
				p.energia_actual = p.calcular_energia_maxima()
		"dar_pokemon":
			var e: PokemonData = Datos.especie(int(a[0])) if a.size() > 0 else null
			if e and GameState.equipo.size() < 6:
				GameState.equipo.append(PokemonInstance.crear(e, int(a[1]) if a.size() > 1 else 5))
		"esperar":
			await get_tree().create_timer(float(a[0]) if a.size() > 0 else 0.5).timeout
		"empujar":
			if jugador and a.size() > 0 and DIRECCIONES.has(a[0]):
				var pasos: float = float(a[1]) if a.size() > 1 else 10.0
				jugador.empujar(DIRECCIONES[a[0]], 120.0, pasos / 30.0)
				await get_tree().create_timer(pasos / 30.0).timeout
		"combate":
			if a.size() > 0:
				SceneManager.ir_a_combate(int(a[0]), jugador)
				gano = await combate_terminado
		"ir_a":
			if a.size() >= 3:
				SceneManager.ir_a_mapa(a[0], Vector2(float(a[1]), float(a[2])), int(a[3]) if a.size() > 3 else -1)
				await SceneManager.mapa_cargado
		"fin":
			_detener = true
		_:
			_aviso(ruta, o.linea, "orden desconocida: " + o.orden)


## decir/narrar: un número es una línea de txt_dialog; lo demás, el texto tal cual. Lo que sigue son
## los $par1$, $par2$...
func _texto(a: PackedStringArray) -> String:
	if a.is_empty():
		return ""
	var t: String = Textos.linea("txt_dialog", int(a[0])) if a[0].is_valid_int() else a[0]
	return CajaDialogo.preparar(t, a.slice(1))


## bandera nombre = valor | += valor | -= valor (el valor puede ser otra condición o cuenta).
func _bandera(a: PackedStringArray, ruta: String, linea: int) -> void:
	if a.size() < 3 or not a[1] in ["=", "+=", "-="]:
		_aviso(ruta, linea, "se esperaba: bandera nombre = valor")
		return
	var nombre: String = a[0].replace("[", "_").replace("]", "")
	var e := Expression.new()
	if e.parse(_expresion(" ".join(a.slice(2))), ["h", "gano"]) != OK:
		_aviso(ruta, linea, "valor inválido")
		return
	var v: int = int(e.execute([GameState.historia, gano]))
	if a[1] == "+=":
		v = GameState.bandera(nombre) + v
	elif a[1] == "-=":
		v = GameState.bandera(nombre) - v
	GameState.cambiar_historia(nombre, v)


func _npc() -> Npc:
	var mapa: Node = get_tree().current_scene
	return mapa.get_node_or_null("Objetos/" + _npc_nombre) as Npc if mapa and _npc_nombre != "" else null


func _jugador() -> Jugador:
	var mapa: Node = get_tree().current_scene
	return mapa.get_node_or_null("Objetos/Jugador") as Jugador if mapa else null


func _aviso(ruta: String, linea: int, que: String) -> void:
	push_warning("Evento %s:%d: %s" % [ruta, linea, que])
