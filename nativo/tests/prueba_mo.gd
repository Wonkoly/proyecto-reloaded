extends SceneTree
## MO en el mapa: Destello, Cascada (la corriente no deja subir; con Cascada sí), Buceo (bajar y subir),
## Ola Lava, Treparrocas, bici y pesca.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/prueba_mo.gd
## Sin --headless guarda capturas en user://mo_*.png.

const CASCADAS: Array[String] = ["obj_cascada"]
const BUCEABLE: Array[String] = ["obj_agua_buceable"]

var _fallas: int = 0
var gs: Node


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.nueva_partida("Prueba")
	gs.dev_encuentros = false  # que un salvaje no interrumpa al surfear
	var crear = func(id: int, bits: Array) -> Object:
		var p = load("res://scripts/resources/pokemon_instance.gd").crear(load("res://scripts/datos.gd").especie(id), 50)
		for b: int in bits:
			p.habilidades_campo |= 1 << b
		gs.equipo.append(p)
		return p
	crear.call(130, [2, 9, 11])  # Gyarados: Surf, Cascada y Torbellino
	crear.call(131, [2, 6])  # Lapras: Surf y Buceo
	crear.call(25, [4])  # Pikachu: Destello
	crear.call(6, [16, 13])  # Charizard: Ola Lava y Treparrocas
	crear.call(78, [8])  # Rapidash: Vel. Extrema
	for n: int in range(1, 9):
		gs.historia["MEDALLA_STAR_%d" % n] = 1
	await _destello()
	await _cascada()
	await _buceo()
	await _ola_lava()
	await _treparrocas()
	await _bici()
	await _montura()
	await _torbellino()
	await _pesca()
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(_fallas)


func _ok(c: bool, que: String) -> void:
	print(("PASA  " if c else "FALLA ") + que)
	if not c:
		_fallas += 1


func _jugador() -> Node:
	return current_scene.get_node_or_null("Objetos/Jugador")


func _ir(mapa: String, pos: Vector2 = Vector2(-1, -1)) -> void:
	root.get_node("DevConsole").ejecutar("tp " + mapa)
	await create_timer(1.3).timeout
	for i: int in 50:  # hasta que termine de cargar
		if current_scene and str(current_scene.get("nombre_original")) == mapa and _jugador():
			break
		await create_timer(0.1).timeout
	if pos.x >= 0:
		_jugador().global_position = pos
		await physics_frame


func _subir(segundos: float) -> float:
	var j: Node = _jugador()
	var y0: float = j.global_position.y
	Input.action_press("mover_arriba")
	await create_timer(segundos).timeout
	Input.action_release("mover_arriba")
	return y0 - j.global_position.y


func _destello() -> void:
	gs.historia.erase("MEDALLA_STAR_3")
	await _ir("Tunel_Yucca")
	var o: Node = current_scene.get_node_or_null("Oscuridad")
	_ok(o != null and o.radio == 1.0, "el Túnel Yucca está oscuro")
	await _captura("mo_oscuro")
	await _tecla(KEY_5)
	await create_timer(0.3).timeout
	_ok(gs.bandera("usadestello") == 0, "sin la medalla 3 la tecla 5 no hace nada")
	gs.historia["MEDALLA_STAR_3"] = 1
	await _tecla(KEY_5)
	await create_timer(1.6).timeout
	_ok(gs.bandera("usadestello") == 1 and o.radio >= 40.0, "con la medalla 3 y Destello se ilumina (%.0f)" % o.radio)
	await _captura("mo_destello")
	await _ir("CiudadSirio")
	_ok(gs.bandera("usadestello") == 0, "al salir a Ciudad Sirio la luz se apaga")


func _cascada() -> void:
	# Isla Viento: una cascada de 6 bloques (x 176, y 624-720) sin paredes alrededor.
	await _ir("IslaViento")
	var p: Vector2 = Vector2(184, 696)
	gs.surfer = 130
	_jugador().global_position = p
	await physics_frame
	_ok(_jugador()._toca(CASCADAS), "hay una cascada en Isla Viento (%s)" % p)
	_ok(_jugador().surfeando(), "surfeando sobre la cascada")
	var subio: float = await _subir(1.0)
	_ok(subio <= 1.0, "sin Cascada la corriente no deja subir (subió %.1f px)" % subio)
	gs.surfer = 131  # sobre Lapras: al activar Cascada pasa a Gyarados
	_jugador().intentar_cascada()
	await create_timer(0.3).timeout
	await _tecla(KEY_Z)
	await create_timer(0.3).timeout
	_ok(_jugador()._cascada and gs.surfer == 130, "Z + Sí: Cascada activa, sobre Gyarados")
	subio = await _subir(1.0)
	_ok(subio > 20.0, "con Cascada sube (%.1f px)" % subio)
	await _captura("mo_cascada")


func _buceo() -> void:
	gs.surfer = 0
	await _ir("Ruta_3")
	var agua: Node = null
	for n: Node in current_scene.get_node("Objetos").get_children():
		if n.name.begins_with("obj_agua_buceable"):
			agua = n
			break
	_ok(agua != null, "Ruta 3 tiene agua buceable")
	if agua == null:
		return
	gs.surfer = 130
	_jugador().global_position = agua.caja().get_center()
	await physics_frame
	_ok(_jugador()._toca(BUCEABLE), "el jugador toca el agua buceable")
	_jugador().intentar_buceo()
	await create_timer(0.3).timeout
	await _tecla(KEY_Z)
	await create_timer(1.5).timeout
	_ok(str(current_scene.get("nombre_original")) == "Ruta_3_Buceo" and gs.buceando, "se sumerge en Ruta 3 Buceo")
	_ok(_jugador() and _jugador().global_position.distance_to(Vector2(160, 144)) < 2.0, "en la llegada (160, 144)")
	await create_timer(0.5).timeout
	_ok(_jugador() and _jugador().surfeando(), "bajo el agua sigue sobre el Pokémon (%d)" % gs.surfer)
	await _captura("mo_buceo")
	var sup: Vector2 = _jugador()._superficie_cercana()
	_ok(sup != Vector2.INF, "hay una superficie en %s" % sup)
	_jugador().global_position = sup
	await physics_frame
	_jugador().intentar_buceo()
	await create_timer(0.3).timeout
	await _tecla(KEY_Z)
	await create_timer(1.5).timeout
	_ok(str(current_scene.get("nombre_original")) == "Ruta_3" and not gs.buceando, "sale a la superficie en Ruta 3")
	_ok(_jugador() and _jugador().surfeando(), "arriba, surfeando")


func _captura(nombre: String) -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_png("user://%s.png" % nombre)


## Cueva Ardiente 2: junto a la lava, la tecla 3 sube al Pokémon con Ola Lava y se cruza la lava.
func _ola_lava() -> void:
	gs.surfer = 0
	await _ir("CuevaArdiente_2")
	var j: Node = _jugador()
	var lava: Rect2 = Rect2()
	for c: Node in current_scene.get_node("Lava").get_children():
		var r: Rect2 = (c as CollisionShape2D).shape.get_rect()
		r.position += (c as CollisionShape2D).global_position
		if r.size.x >= 32 and r.size.y >= 32:
			lava = r
			break
	_ok(lava.size != Vector2.ZERO, "hay lava en Cueva Ardiente 2 (%s)" % lava)
	# Desde cada lado, mirando hacia la lava, hasta que uno funcione (los otros pueden ser pared).
	for lado: Array in [[Vector2(lava.position.x - 10, lava.get_center().y), 6], [Vector2(lava.end.x + 10, lava.get_center().y), 4],
			[Vector2(lava.get_center().x, lava.position.y - 12), 2], [Vector2(lava.get_center().x, lava.end.y + 10), 8]]:
		j.global_position = lado[0]
		j.mira = lado[1]
		await physics_frame
		if j.sobre_agua(j.global_position, j.CAPA_LAVA):
			continue
		await j.intentar_surf()
		await create_timer(0.4).timeout
		if j.surfeando():
			break
	_ok(j.surfeando() and gs.surf_lava and gs.surfer == 6, "Ola Lava: sobre Charizard en la lava")
	await _captura("mo_lava")
	j.terminar_surf()


## Isla Halley: debajo de la pared trepable, Z mirando arriba la cruza.
func _treparrocas() -> void:
	await _ir("IslaHalley")
	var j: Node = _jugador()
	var rocas: Rect2 = Rect2()
	for n: Node in current_scene.get_node("Objetos").get_children():
		if n.name.begins_with("obj_rocatrepable") and n.global_position.x < 200:
			rocas = n.caja() if rocas.size == Vector2.ZERO else rocas.merge(n.caja())
	_ok(rocas.size != Vector2.ZERO, "hay una pared trepable en Isla Halley (%s)" % rocas)
	j.global_position = Vector2(rocas.position.x + 8, rocas.end.y + 8)
	j.mira = 8
	await physics_frame
	_ok(j._roca_trepable() != null, "de frente a la pared trepable")
	j.intentar_treparrocas()
	await create_timer(0.3).timeout
	await _tecla(KEY_Z)
	await create_timer(2.0).timeout
	_ok(j.global_position.y < rocas.position.y and j._trepando == 0, "la trepa hasta arriba (y %.0f, la pared empieza en %.0f)" % [j.global_position.y, rocas.position.y])
	await _captura("mo_trepa")


## V con la Bicicleta: va a 6 px/step (180 px/s) y al entrar a un edificio se baja.
func _bici() -> void:
	gs.mapa_salida = ""  # afuera (la partida nueva empieza dentro de casa)
	await _ir("PuebloAlba", Vector2(417, 240))
	var j: Node = _jugador()
	await _tecla(KEY_V)
	_ok(not gs.ciclista, "sin la Bicicleta la V no hace nada")
	gs.objetos[184] = 1
	await _tecla(KEY_V)
	_ok(gs.ciclista, "con la Bicicleta, V sube")
	var x0: float = j.global_position.x
	Input.action_press("mover_izquierda")
	await create_timer(0.5).timeout
	Input.action_release("mover_izquierda")
	var v: float = (x0 - j.global_position.x) / 0.5
	_ok(v > 150.0, "en bici va a ~180 px/s (%.0f)" % v)
	await _captura("mo_bici")
	await _tecla(KEY_V)
	_ok(not gs.ciclista, "V baja")
	gs.ciclista = true
	gs.mapa_salida = "PuebloAlba"
	await _ir("Lab_Oak")
	_ok(not gs.ciclista, "al entrar al laboratorio se baja de la bici")
	gs.mapa_salida = ""


## Habilidades → Vel. Extrema: monta a Rapidash (11 px/step; con X, 4) y se baja igual.
func _montura() -> void:
	gs.mapa_salida = ""
	gs.ciclista = false
	await _ir("PuebloAlba", Vector2(417, 240))
	var j: Node = _jugador()
	await _elegir_habilidad("Vel. Extrema")
	_ok(gs.caballo == 78 and j.get_node_or_null("Montura") != null, "Habilidades → Vel. Extrema monta a Rapidash")
	var x0: float = j.global_position.x
	Input.action_press("mover_izquierda")
	await create_timer(0.3).timeout
	Input.action_release("mover_izquierda")
	var v: float = (x0 - j.global_position.x) / 0.3
	_ok(v > 280.0, "montado va a ~330 px/s (%.0f)" % v)
	await _captura("mo_montura")
	x0 = j.global_position.x
	Input.action_press("correr")
	Input.action_press("mover_derecha")
	await create_timer(0.5).timeout
	Input.action_release("mover_derecha")
	Input.action_release("correr")
	v = (j.global_position.x - x0) / 0.5
	_ok(v > 100.0 and v < 140.0, "con X frena a ~120 px/s (%.0f)" % v)
	await _elegir_habilidad("Vel. Extrema")
	_ok(gs.caballo == 0 and j.get_node_or_null("Montura") == null, "y se baja")


## Abre el menú Habilidades y elige la opción con ese nombre.
func _elegir_habilidad(nombre: String) -> void:
	var lista: Array = load("res://scenes/ui/menu_principal.gd").HABILIDADES.filter(
		func(h: Array) -> bool: return gs.tiene_medalla(h[1]))
	var textos = load("res://scripts/textos.gd")
	var i: int = lista.map(func(h: Array) -> String: return textos.linea("txt_menu", h[2])).find(nombre)
	load("res://scenes/ui/menu_principal.gd").habilidades(current_scene)
	await create_timer(0.3).timeout
	for k: int in i:
		await _tecla(KEY_DOWN)
	await _tecla(KEY_Z)
	await create_timer(0.5).timeout


## Isla Viento: surfeando frente a un torbellino, Z (medalla 6) lo quita para siempre.
func _torbellino() -> void:
	gs.caballo = 0
	await _ir("IslaViento")
	var t: Node = current_scene.get_node_or_null("Objetos/obj_torbellino_s2")
	_ok(t != null and t.mo == "torbellino", "el torbellino de Isla Viento es un obstáculo")
	if t == null:
		return
	var j: Node = _jugador()
	var r: Rect2 = t.rect()
	gs.surfer = 131
	j.global_position = Vector2(r.get_center().x, r.end.y + 6)
	j.mira = 8
	await physics_frame
	await _tecla(KEY_Z)
	await create_timer(0.3).timeout
	await _tecla(KEY_Z)
	await create_timer(3.2).timeout
	_ok(not is_instance_valid(t) and gs.bandera("estorbo_torbellino_2") == 1 and gs.surfer == 130,
		"Z lo quita (bandera estorbo_torbellino_2) y sigue sobre Gyarados")


## C con una caña de cara al agua: se echa y, cuando pica, empieza un combate.
func _pesca() -> void:
	gs.surfer = 0
	gs.objetos[181] = 1
	seed(3)
	await _ir("Ruta_3")
	var j: Node = _jugador()
	var listo: bool = false
	for c: Node in current_scene.get_node("Agua").get_children():
		var r: Rect2 = (c as CollisionShape2D).shape.get_rect()
		r.position += (c as CollisionShape2D).global_position
		if r.size.x < 32 or r.size.y < 32:
			continue
		for lado: Array in [[Vector2(r.position.x - 9, r.get_center().y), 6], [Vector2(r.end.x + 9, r.get_center().y), 4],
				[Vector2(r.get_center().x, r.position.y - 9), 2], [Vector2(r.get_center().x, r.end.y + 9), 8]]:
			j.global_position = lado[0]
			j.mira = lado[1]
			await physics_frame
			if not j.sobre_agua(j.global_position) and j.sobre_agua(j.global_position + j.VECTOR_MIRA[j.mira] * 10.0) \
					and j.global_position.distance_to(lado[0]) < 1.0:
				listo = true
				break
		if listo:
			break
	_ok(listo, "en la orilla de cara al agua (%s, mira %d)" % [j.global_position, j.mira])
	var combate: bool = false
	for intento: int in 6:
		j = _jugador()
		j.pescar()
		await create_timer(0.3).timeout
		await _captura("mo_pesca") if intento == 0 else null
		for k: int in 40:
			await _tecla(KEY_Z)
			await create_timer(0.1).timeout
			if current_scene and current_scene.name == "BattleArena":
				combate = true
				break
			if not j._pescando and k > 35:
				break
		if combate:
			break
	_ok(combate, "con la Caña Vieja pica algo y empieza el combate")


func _tecla(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await create_timer(0.1).timeout
