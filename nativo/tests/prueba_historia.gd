extends SceneTree
## Recorre la historia como un jugador (validador de recorrido): habla con quien hay que hablar, gana los
## combates y comprueba que cada paso deja las banderas, el equipo y los caminos como el original.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/prueba_historia.gd
## Los nombres de clases del proyecto se cargan en tiempo de ejecución (con -s todavía no existen).

var _fallas: int = 0
var gs: Node
var ev: Node


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	ev = root.get_node("Eventos")
	await _inicio()
	await _ruta_al_gimnasio_1()
	await _gimnasio_1()
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(1 if _fallas else 0)


func _ok(cond: bool, que: String) -> void:
	print(("PASA  " if cond else "FALLA ") + que)
	if not cond:
		_fallas += 1


## Casa → laboratorio → inicial → móvil: Pueblo Alba queda abierto.
func _inicio() -> void:
	gs.nueva_partida("Prueba")
	_ok(gs.equipo.is_empty() and gs.bandera("fy_002") == 0, "la partida nueva empieza sin Pokémon")
	await _ir("PuebloAlba")
	_ok(_activo("obj_NoPass_s8"), "sin Pokémon, Pueblo Alba no deja ir a la Ruta 1")
	await _hablar("Lab_Oak", "obj_Oak1_s6")
	_ok(gs.bandera("lab_rival_fuera") == 1 and not _activo("obj_Lab_Rival_s7"), "el profesor habla y el rival se va")
	await _hablar("Lab_Oak", "obj_ini_s0", "Lab_Oak")
	_ok(gs.equipo.size() == 1 and gs.equipo[0].especie.id_original == 25 and gs.equipo[0].nivel == 5,
		"la primera Poké Ball da un Pikachu de nivel 5")
	_ok(gs.objetos.get(1, 0) == 15 and gs.ball_asignada == 1, "con 15 Poké Balls asignadas a B")
	await _ir("PuebloAlba")
	_ok(not _activo("obj_NoPass_s8") and _activo("obj_NoPass_s11"), "con Pokémon y sin móvil sigue cerrado")
	await _hablar("Home_1", "obj_Mom_s16")
	_ok(gs.bandera("movil") == 1 and gs.objetos.get(176, 0) == 1, "la madre da el SmartPhone")
	await _ir("PuebloAlba")
	_ok(not _activo("obj_NoPass_s8") and not _activo("obj_NoPass_s11"), "Pueblo Alba queda abierto")


## Del pueblo al gimnasio de Spica hay camino y ningún NPC lo cierra.
func _ruta_al_gimnasio_1() -> void:
	var conexiones = load("res://scenes/debug/conexiones_dev.gd")
	var camino: Array = conexiones.ruta("PuebloAlba", "GYM1_Spica")
	_ok(not camino.is_empty(), "hay camino de Pueblo Alba al Gimnasio de Spica (%d mapas)" % camino.size())
	for con: Dictionary in camino:
		await _ir(con["origen"])
		# Los NPCs que cierran el paso (obj_NoPass) cerca de la salida que usa el camino.
		var r: Array = con["salida"].get("rect", [])
		var salida := Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]).grow(48.0) if r.size() == 4 else Rect2()
		var cerrados: Array = current_scene.get_node("Objetos").get_children().filter(
			func(n: Node) -> bool: return n.get("no_pasar") and n.no_pasar > 0 and _activo(n.name) \
				and salida.has_point((n as Node2D).position))
		_ok(cerrados.is_empty(), "%s: nadie cierra el paso %s" % [con["origen"], cerrados.map(func(n: Node) -> String: return n.name)])


## Líder Mino: combate (con un equipo fuerte), medalla y paso abierto en Ciudad Spica.
func _gimnasio_1() -> void:
	gs.equipo.append(load("res://scripts/resources/pokemon_instance.gd").crear(load("res://scripts/datos.gd").especie(6), 80))
	gs.equipo.reverse()
	gs.dev_god = true
	gs.dev_energia_infinita = true
	await _hablar("GYM1_Spica", "obj_Entrenador_s1")
	gs.dev_god = false
	gs.dev_energia_infinita = false
	_ok(gs.bandera("trainer_25") == 1 and gs.tiene_medalla(1) and gs.objetos.get(235, 0) == 1,
		"Mino entrega la Medalla Pedrusco y la MT35")
	await _ir("CiudadSpica")
	_ok(not _activo("obj_NoPass_s12"), "con la medalla se abre el paso de Ciudad Spica")


func _ir(mapa: String) -> void:
	root.get_node("DevConsole").ejecutar("tp " + mapa)
	await create_timer(1.3).timeout


func _activo(nodo: String) -> bool:
	var n: Node = current_scene.get_node_or_null("Objetos/" + nodo)
	return n != null and n.is_visible_in_tree() and n.process_mode != Node.PROCESS_MODE_DISABLED


## Corre el evento del nodo como si el jugador le hablara: pasa los cuadros (Enter: Sí) y, si hay un
## combate, ataca hasta que termine.
func _hablar(mapa: String, nodo: String, _vuelta: String = "") -> void:
	if current_scene == null or str(current_scene.get("nombre_original")) != mapa:
		await _ir(mapa)
	var npc: Node = current_scene.get_node_or_null("Objetos/" + nodo)
	var evento = ev.de_nodo(mapa, nodo)
	if npc == null or evento == null:
		_ok(false, "%s/%s existe y tiene evento" % [mapa, nodo])
		return
	ev.ejecutar(evento, npc)
	for i: int in 6000:
		await create_timer(0.03).timeout
		if _hay_cuadro():
			await _tecla(KEY_ENTER)
		elif current_scene and current_scene.name == "BattleArena":
			var a := InputEventAction.new()
			a.action = "atacar_1"
			a.pressed = true
			Input.parse_input_event(a)
			await process_frame
			a = a.duplicate()
			a.pressed = false
			Input.parse_input_event(a)
		elif not ev.en_curso and i > 20:
			return


func _hay_cuadro() -> bool:
	for n: Node in root.get_children():
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("caja_dialogo.gd") or str(sc.resource_path).ends_with("cuadro_original.gd")
				or str(sc.resource_path).ends_with("menu_lista.gd")):
			return true
	return false


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
	await create_timer(0.05).timeout
