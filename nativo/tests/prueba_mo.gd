extends SceneTree
## MO en el mapa: Cascada (la corriente no deja subir; con Cascada sí) y Buceo (bajar y subir).
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
	crear.call(130, [2, 9])  # Gyarados: Surf y Cascada
	crear.call(131, [2, 6])  # Lapras: Surf y Buceo
	for n: int in range(1, 9):
		gs.historia["MEDALLA_STAR_%d" % n] = 1
	await _cascada()
	await _buceo()
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
