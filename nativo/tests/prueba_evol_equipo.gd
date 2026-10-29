extends SceneTree
## Evoluciones que dependen del equipo (CheckTeamEvolution): Nincada, Mantyke y la 769.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/prueba_evol_equipo.gd


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var PI = load("res://scripts/resources/pokemon_instance.gd")
	var D = load("res://scripts/datos.gd")
	var Ev = load("res://scenes/ui/evolucion.gd")
	var fallas: int = 0
	gs.nueva_partida("Prueba")
	var mantyke = PI.crear(D.especie(458), 20)
	gs.equipo.append(mantyke)
	fallas += _ok(mantyke.evolucion_pendiente() == null, "Mantyke sin Remoraid no evoluciona")
	gs.equipo.append(PI.crear(D.especie(223), 10))
	fallas += _ok(mantyke.evolucion_pendiente() != null and mantyke.evolucion_pendiente().id_original == 226, "Mantyke con Remoraid → Mantine")
	var p769 = PI.crear(D.especie(769), 40)
	gs.equipo.append(p769)
	fallas += _ok(p769.evolucion_pendiente() == null, "769 sin Siniestro no evoluciona")
	gs.equipo.append(PI.crear(D.especie(197), 10))  # Umbreon
	fallas += _ok(p769.evolucion_pendiente() != null and p769.evolucion_pendiente().id_original == 770, "769 con Siniestro → 770")
	var nincada = PI.crear(D.especie(290), 25)
	gs.equipo.append(nincada)
	fallas += _ok(nincada.evolucion_pendiente() != null, "Nincada con hueco evoluciona")
	Ev._shedinja(nincada)
	fallas += _ok(gs.equipo.size() == 6 and gs.equipo[5].especie.id_original == 292 and gs.equipo[5].nivel == 25, "aparece Shedinja")
	fallas += _ok(nincada.evolucion_pendiente() == null, "con el equipo lleno Nincada espera")
	print("RESULTADO: ", "todo bien" if fallas == 0 else "%d fallas" % fallas)
	quit(fallas)


func _ok(c: bool, que: String) -> int:
	print(("PASA  " if c else "FALLA ") + que)
	return 0 if c else 1
