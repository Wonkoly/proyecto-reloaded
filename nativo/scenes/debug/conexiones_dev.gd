class_name ConexionesDev
## Comandos "validar" e "ir" de la consola dev. Usan el grafo de data/extraido/conexiones.json (lo
## genera tools/extraer.py) y, para validar, las escenas de los mapas con la historia actual: es la
## misma revisión que tools/validar_conexiones.py pero sobre el mapa en el que se está.

const RUTA_GRAFO: String = "res://data/extraido/conexiones.json"
## Máscara del protagonista respecto a su posición (ProtaMaskSprite).
const CAJA: Rect2 = Rect2(-7, -8, 15, 20)
## Hasta cuántos px se puede meter en una pared al llegar y salir caminando.
const SALE_SOLO: float = 4.0
const CON_REGRESO: Array[String] = ["puerta", "entrada", "borde", "escalera"]

static var _grafo: Dictionary = {}


static func grafo() -> Dictionary:
	if _grafo.is_empty():
		var f: FileAccess = FileAccess.open(RUTA_GRAFO, FileAccess.READ)
		if f:
			_grafo = JSON.parse_string(f.get_as_text())
	return _grafo


## validar: cada salida del mapa actual con su estado (ok / error / requiere X).
static func validar(mapa: Mapa) -> String:
	var lineas: PackedStringArray = []
	var requisitos: Dictionary = {}
	for con: Dictionary in grafo().get("conexiones", []):
		if con["origen"] == mapa.nombre_original:
			requisitos[con["salida"]["nodo"]] = con["requisitos"]
	var cache: Dictionary = {}
	var errores: int = 0
	for nodo: Node in mapa.get_tree().get_nodes_in_group("salidas"):
		var s: Salida = nodo as Salida
		if s == null or not mapa.is_ancestor_of(s):
			continue
		var problemas: PackedStringArray = _problemas(mapa, s, cache)
		var req: Dictionary = requisitos.get(String(s.name), {})
		var pide: PackedStringArray = []
		for r: Variant in req.get("terreno", []):
			pide.append(str(r))
		var condicion: String = str(req.get("historia", ""))
		var estado: String = "[color=#8f8]ok[/color]"
		if not problemas.is_empty():
			estado = "[color=#f88]error[/color]"
			errores += 1
		elif condicion != "" and not mapa.cumple(condicion):
			estado = "[color=#aaa]inactiva ahora (%s)[/color]" % condicion
		elif not pide.is_empty():
			estado = "[color=#fd8]requiere %s[/color]" % ", ".join(pide)
		var destino: String = "regreso" if s.volver else s.destino
		lineas.append("%s %s → %s %s" % [estado, s.tipo, destino, "; ".join(problemas)])
	for d: Variant in cache.values():
		if d is Node:
			(d as Node).free()
	lineas.insert(0, "%s: %d salidas, %d con error" % [mapa.nombre_original, lineas.size(), errores])
	return "\n".join(lineas)


static func _problemas(mapa: Mapa, s: Salida, cache: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if s.volver:
		if GameState.mapa_salida == "":
			out.append("sin regreso guardado (se entró sin puerta)")
		return out
	if s.destino == "":
		out.append("sin destino (ROOM = -1)")
		return out
	if not SceneManager.existe_mapa(s.destino):
		out.append("%s no existe" % s.destino)
		return out
	if not cache.has(s.destino):
		cache[s.destino] = (load(SceneManager.ruta_mapa(s.destino)) as PackedScene).instantiate()
	var destino: Mapa = cache[s.destino]
	# Las relativas copian la coordenada del jugador: se prueba cada 8 px a lo largo de la salida y
	# basta con que se pueda llegar a alguna.
	var r: Rect2 = s.rect_global().intersection(Rect2(Vector2.ZERO, Vector2(mapa.tamano)))
	if not r.has_area():
		r = s.rect_global()
	var puntos: Array[Vector2] = []
	if s.relativa_x or s.relativa_y:
		var x: float = r.position.x if s.relativa_x else r.get_center().x
		while x <= (r.end.x if s.relativa_x else r.get_center().x):
			var y: float = r.position.y if s.relativa_y else r.get_center().y
			while y <= (r.end.y if s.relativa_y else r.get_center().y):
				puntos.append(s.posicion_destino(Vector2(x, y)))
				y += 8.0
			x += 8.0
	else:
		puntos.append(s.posicion_destino(r.get_center()))
	var bien: Array[Vector2] = []
	var motivo: String = ""
	for p: Vector2 in puntos:
		var m: String = _llegada_mala(destino, p)
		if m == "":
			bien.append(p)
		elif motivo == "":
			motivo = m
	if bien.is_empty():
		out.append(motivo)
		return out
	# Rebote: solo si todas las llegadas caen sobre otra salida (si no, son esquinas).
	var rebota: String = ""
	for llegada: Vector2 in bien:
		var aqui: String = _salida_en(destino, llegada)
		if aqui == "":
			rebota = ""
			break
		rebota = aqui
	if rebota != "" and s.tipo not in ["teletransporte", "conducto", "brecha"]:
		out.append("rebota: llega sobre la salida a %s" % rebota)
	if s.tipo in CON_REGRESO and s.destino != mapa.nombre_original:
		var vuelve: bool = false
		for otra: Node in destino.get_node("Salidas").get_children() + destino.objetos().get_children():
			var s2: Salida = otra as Salida
			if s2 and (s2.destino == mapa.nombre_original or (s2.volver and s.regreso != Salida.Regreso.NADA)):
				vuelve = true
		if not vuelve:
			out.append("%s no tiene salida de vuelta" % s.destino)
	return out


## El destino de una salida que se activa sola con el jugador en `p` ("" si ninguna).
static func _salida_en(destino: Mapa, p: Vector2) -> String:
	var caja := Rect2(p + CAJA.position, CAJA.size)
	for otra: Node in destino.get_node("Salidas").get_children() + destino.objetos().get_children():
		var s2: Salida = otra as Salida
		if s2 and s2.activacion == Salida.Activacion.AL_ENTRAR and (s2.destino != "" or s2.volver):
			if (s2.rect_global().has_point(p) if s2.por_punto else s2.rect_global().intersects(caja)):
				return s2.destino if s2.destino != "" else "regreso"
	return ""


## "" si el jugador puede aparecer en `p`; si no, por qué.
static func _llegada_mala(destino: Mapa, p: Vector2) -> String:
	if not Rect2(Vector2.ZERO, Vector2(destino.tamano)).grow(0.5).has_point(p):
		return "llega fuera del mapa %s" % p
	var caja := Rect2(p + CAJA.position, CAJA.size)
	for forma: Node in destino.get_node("Paredes").get_children():
		var hueco: Rect2 = _rect(forma as CollisionShape2D)
		var activa: bool = not forma.has_meta("condicion") or destino.cumple(str(forma.get_meta("condicion")))
		if activa and hueco.intersects(caja):
			var solape: Rect2 = hueco.intersection(caja)
			if minf(solape.size.x, solape.size.y) > SALE_SOLO:
				return "llega dentro de una pared en %s" % hueco.position
	return ""


static func _rect(forma: CollisionShape2D) -> Rect2:
	if forma == null or not forma.shape is RectangleShape2D:
		return Rect2()
	var tam: Vector2 = (forma.shape as RectangleShape2D).size
	return Rect2(forma.position - tam / 2.0, tam)


## ir: la ruta con menos cambios de mapa entre el actual y `destino` (nombres originales). Devuelve
## las conexiones del camino en orden ([] si no hay).
static func ruta(origen: String, destino: String) -> Array[Dictionary]:
	var salidas: Dictionary = {}
	for con: Dictionary in grafo().get("conexiones", []):
		if con["destino"] != "@regreso" and con["destino"] != "" and con["destino"] != con["origen"] \
				and not (con["zonas"] as Array).is_empty():
			if not salidas.has(con["origen"]):
				salidas[con["origen"]] = []
			(salidas[con["origen"]] as Array).append(con)
	# Desde un interior, la salida de regreso lleva a donde se entró (global.room_out).
	if GameState.mapa_salida != "" and GameState.mapa_salida != origen:
		var regreso: Dictionary = {"origen": origen, "destino": GameState.mapa_salida, "regreso_guardado": true,
			"salida": {"tipo": "salida_interior"}, "requisitos": {"historia": "", "terreno": []}}
		if not salidas.has(origen):
			salidas[origen] = []
		(salidas[origen] as Array).push_front(regreso)
	var previo: Dictionary = {origen: {}}
	var cola: Array[String] = [origen]
	while not cola.is_empty() and not previo.has(destino):
		var m: String = cola.pop_front()
		for con: Dictionary in salidas.get(m, []):
			if not previo.has(con["destino"]):
				previo[con["destino"]] = con
				cola.append(con["destino"])
	var camino: Array[Dictionary] = []
	if not previo.has(destino) or origen == destino:
		return camino
	var actual: String = destino
	while actual != origen:
		var con: Dictionary = previo[actual]
		camino.push_front(con)
		actual = con["origen"]
	return camino


## Nombre original de un mapa a partir de lo que se escriba (pueblo_alba, PuebloAlba, puebloal...).
static func resolver(texto: String) -> String:
	var buscado: String = texto.to_lower().replace("_", "")
	var parecidos: PackedStringArray = []
	for m: String in grafo().get("mapas", {}):
		var n: String = m.to_lower().replace("_", "")
		if n == buscado:
			return m
		if n.begins_with(buscado):
			parecidos.append(m)
	return parecidos[0] if parecidos.size() == 1 else ""


## Dónde aparece el jugador al usar una conexión (las relativas, desde el centro de la salida).
static func llegada(con: Dictionary) -> Vector2:
	if con.get("regreso_guardado", false):
		return GameState.posicion_salida
	var r: Array = con["salida"]["rect"]
	var g: Dictionary = grafo()["mapas"][con["origen"]]
	var centro := Vector2((clampf(r[0], 0, g["ancho"]) + clampf(r[2], 0, g["ancho"])) / 2.0,
		(clampf(r[1], 0, g["alto"]) + clampf(r[3], 0, g["alto"])) / 2.0)
	var l: Array = con["llegada"]
	var rel: Array = con["relativa"]
	var d: Dictionary = grafo()["mapas"].get(con["destino"], {"ancho": 9999, "alto": 9999})
	return Vector2(clampf(centro.x + l[0] if rel[0] else l[0], 8, d["ancho"] - 8),
		clampf(centro.y + l[1] if rel[1] else l[1], 8, d["alto"] - 8))
