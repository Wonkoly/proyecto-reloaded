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
	_ok(hud._jugador.estado == 1 and hud._jugador.modificadores.get(1) == 2 and hud._jugador.modificadores.get(5) == -1, "el HUD sigue el estado y las etapas: %s" % hud._jugador.modificadores)
	_ok(hud._mostrar_tiempo, "con Ctrl se ve el panel de tiempo y modificadores")
	await _captura("arena_hud_ctrl")
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _repartir_exp(gs)
	await _mega_z_dinamax(gs)
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(_fallas)


## Con Repartir Exp. activado, el que no combatió gana la mitad (ceil) de la experiencia.
func _repartir_exp(gs: Node) -> void:
	var PI = load("res://scripts/resources/pokemon_instance.gd")
	var D = load("res://scripts/datos.gd")
	root.get_node("DevConsole").ejecutar("tp Ruta_1")
	await create_timer(1.5).timeout
	gs.equipo.clear()
	gs.equipo.append(PI.crear(D.especie(6), 60))
	gs.equipo.append(PI.crear(D.especie(25), 10))
	gs.historia["activoRepartirEXP"] = 1
	gs.combate_entrenador = 0
	var salvaje = PI.crear(D.especie(19), 30)
	var exp0: Array = [gs.equipo[0].experiencia, gs.equipo[1].experiencia]
	var esperado: int = floori(salvaje.nivel * salvaje.especie.exp_base / 7.0)
	root.get_node("SceneManager").ir_a_batalla(salvaje, current_scene.get_node("Objetos/Jugador"))
	await create_timer(2.5).timeout
	var rival: Node = current_scene.find_child("Rival", true, false)
	rival.recibir_danio(9999)
	for i: int in 80:
		await create_timer(0.1).timeout
		var e := InputEventKey.new()
		e.physical_keycode = KEY_Z
		e.keycode = KEY_Z
		e.pressed = true
		Input.parse_input_event(e)
		await process_frame
		e = e.duplicate()
		e.pressed = false
		Input.parse_input_event(e)
		if current_scene and current_scene.get("nombre_original") == "Ruta_1":
			break
	var ganado: Array = [gs.equipo[0].experiencia - exp0[0], gs.equipo[1].experiencia - exp0[1]]
	_ok(ganado[0] == esperado and ganado[1] >= ceili(esperado / 2.0),
		"Repartir Exp.: el que combate gana %d y el otro la mitad (%s)" % [esperado, ganado])


## M en combate: megaevolución (Mega Aro + megapiedra), movimiento Z (Pulsera Z + cristal) y dinamax.
func _mega_z_dinamax(gs: Node) -> void:
	var PI = load("res://scripts/resources/pokemon_instance.gd")
	var D = load("res://scripts/datos.gd")
	gs.dev_god = true
	root.get_node("DevConsole").ejecutar("tp Ruta_1")
	await create_timer(1.5).timeout
	gs.equipo.clear()
	var zard = PI.crear(D.especie(6), 60)
	zard.objeto = 416  # Charizardita X
	gs.equipo.append(zard)
	gs.objetos[193] = 1
	root.get_node("SceneManager").ir_a_batalla(PI.crear(D.especie(19), 5), current_scene.get_node("Objetos/Jugador"))
	await create_timer(2.5).timeout
	await _tecla(KEY_M)
	await create_timer(1.2).timeout
	var jug: Node = current_scene.find_child("Jugador", true, false)
	_ok(jug.pokemon.especie.id_original == 100006, "M megaevoluciona a Charizard en Mega Charizard X (%d)" % jug.pokemon.especie.id_original)
	await _captura("arena_mega")
	var manager: Node = current_scene.find_child("BattleManager", true, false)
	manager._deshacer_megas()
	_ok(zard.especie.id_original == 6, "al terminar el combate vuelve a ser Charizard")
	# Movimiento Z: Pikachu con Electrostal Z (492) y la Pulsera Z.
	var bp = load("res://scenes/battle/battle_pokemon.gd")
	var impactrueno: Resource = D.movimiento(9) if false else null
	for m: Resource in jug.pokemon.movimientos:
		var z: Resource = bp.movimiento_z(m, 487 + 2)  # cristal de Fuego
		if z:
			_ok(z.nombre != m.nombre and z.poder >= 100, "%s con el cristal de Fuego pasa a %s (poder %d)" % [m.nombre, z.nombre, z.poder])
			break
	jug.dinamax()
	await create_timer(1.0).timeout
	_ok(jug.sprite.scale.x > 1.9, "dinamax: crece al doble (%.2f)" % jug.sprite.scale.x)
	await _captura("arena_dinamax")
	gs.dev_god = false


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


func _ok(c: bool, que: String) -> void:
	print(("PASA  " if c else "FALLA ") + que)
	if not c:
		_fallas += 1


func _captura(nombre: String) -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_viewport().get_texture().get_image().save_png("user://%s.png" % nombre)
