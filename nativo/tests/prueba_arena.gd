extends SceneTree
## La arena de batalla: los entrenadores (Trainer1 y Trainer2) en sus posiciones del original.
## Sin --headless guarda capturas en user://arena_*.png.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --path . -s res://tests/prueba_arena.gd

var _fallas: int = 0


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	gs.nueva_partida("Prueba")
	gs.equipo.append(load("res://scripts/resources/pokemon_instance.gd").crear(load("res://scripts/datos.gd").especie(25), 20))
	root.get_node("DevConsole").ejecutar("tp Ruta_1")
	await create_timer(1.5).timeout
	root.get_node("SceneManager").ir_a_combate(2, current_scene.get_node("Objetos/Jugador"))
	await create_timer(2.5).timeout
	var t1: Node = current_scene.find_child("Trainer1", true, false)
	var t2: Node = current_scene.find_child("Trainer2", true, false)
	_ok(t1 != null and t1.position == Vector2(98, 64) and t1.sprite != null, "el jugador en (98, 64)")
	_ok(t2 != null and t2.position == Vector2(480, 244) and t2.sprite != null and t2.xscale == -1.0, "el rival en (480, 244) mirando a la izquierda")
	await _captura("arena_entrenador")
	# HUD: el estado y, con Ctrl, el tiempo y las etapas (draw_modifier).
	var jug: Node = current_scene.find_child("Jugador", true, false)
	jug.pokemon.estado = 1  # parálisis
	jug._etapas[1] = 2
	jug._etapas[5] = -1
	var hud: Node = current_scene.find_child("BattleHud", true, false)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_CTRL
	e.keycode = KEY_CTRL
	e.pressed = true
	Input.parse_input_event(e)
	await create_timer(0.3).timeout
	_ok(hud._jugador.estado == 1 and hud._jugador.modificadores == {1: 2, 5: -1}, "el HUD sigue el estado y las etapas: %s" % hud._jugador.modificadores)
	_ok(hud._mostrar_tiempo, "con Ctrl se ve el panel de tiempo y modificadores")
	await _captura("arena_hud_ctrl")
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(_fallas)


func _ok(c: bool, que: String) -> void:
	print(("PASA  " if c else "FALLA ") + que)
	if not c:
		_fallas += 1


func _captura(nombre: String) -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_png("user://%s.png" % nombre)
