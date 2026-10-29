extends SceneTree
## Vuelo en tiempo real: abre el mapa con la tecla 2, elige un lugar con las flechas, confirma y
## comprueba que el jugador llega volando. Con ventana guarda capturas en user://vuelo_*.png.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --path . -s res://tests/prueba_vuelo.gd

var _fallas: int = 0
var gs: Node


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.nueva_partida("Prueba")
	var p = load("res://scripts/resources/pokemon_instance.gd").crear(load("res://scripts/datos.gd").especie(18), 40)
	p.habilidades_campo |= 1 << 1  # Vuelo
	gs.equipo.append(p)
	gs.historia["MEDALLA_STAR_4"] = 1
	gs.objetos[186] = 1
	gs.mapa_salida = ""
	await _ir("CiudadSpica")
	_ok(gs.vuelo.get(2, 0) == 1, "entrar a Ciudad Spica la marca como visitada")
	gs.vuelo[3] = 1  # Pueblo Talo
	await _tecla(KEY_2)
	await create_timer(0.5).timeout
	var pantalla: Node = _buscar("pantalla_vuelo.gd")
	_ok(pantalla != null, "la tecla 2 abre la pantalla de Vuelo")
	await _captura("vuelo_1_mapa")
	await _tecla(KEY_DOWN)
	await _tecla(KEY_DOWN)
	await _tecla(KEY_DOWN)
	await create_timer(0.3).timeout
	_ok(pantalla and pantalla._lugar == "3", "↓ recorre los visitados (Pueblo Alba, Spica, Talo): %s" % (pantalla._lugar if pantalla else ""))
	await _captura("vuelo_2_elegido")
	await _tecla(KEY_Z)
	await create_timer(0.4).timeout
	await _captura("vuelo_3_pregunta")
	await _tecla(KEY_Z)
	await create_timer(1.5).timeout
	await _captura("vuelo_4_despegue")
	await create_timer(5.0).timeout
	_ok(str(current_scene.get("nombre_original")) == "PuebloTalo", "aterriza en Pueblo Talo")
	var j: Node = current_scene.get_node_or_null("Objetos/Jugador")
	_ok(j != null and j.global_position.distance_to(Vector2(256, 290)) < 2.0, "en la llegada del original (256, 290)")
	await _captura("vuelo_5_llegada")
	# Sin medalla 4 la tecla 2 no hace nada.
	gs.historia.erase("MEDALLA_STAR_4")
	await _tecla(KEY_2)
	await create_timer(0.4).timeout
	_ok(_buscar("pantalla_vuelo.gd") == null, "sin la medalla 4 no se abre")
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(_fallas)


func _ok(c: bool, que: String) -> void:
	print(("PASA  " if c else "FALLA ") + que)
	if not c:
		_fallas += 1


func _ir(mapa: String) -> void:
	root.get_node("DevConsole").ejecutar("tp " + mapa)
	await create_timer(1.3).timeout


func _buscar(script: String) -> Node:
	for n: Node in root.get_children():
		if n.get_script() and str(n.get_script().resource_path).ends_with(script):
			return n
	return null


func _captura(nombre: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
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
