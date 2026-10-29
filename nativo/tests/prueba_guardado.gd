extends Node
## Pruebas de SaveManager (en una carpeta aparte; no toca las partidas reales):
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tests/prueba_guardado.tscn
## Imprime cada comprobación y sale con código 1 si alguna falla.

var _fallas: int = 0


func _ready() -> void:
	SaveManager.carpeta = "user://pruebas_guardado"
	_limpiar()
	_ida_y_vuelta()
	_respaldo()
	_danado()
	_editado_a_mano()
	_sin_nada()
	_slots_llenos()
	_borrar()
	_limpiar()
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	get_tree().quit(1 if _fallas else 0)


func _ok(cond: bool, que: String) -> void:
	print(("PASA  " if cond else "FALLA ") + que)
	if not cond:
		_fallas += 1


func _limpiar() -> void:
	var dir: String = SaveManager.carpeta
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))


## Una partida con de todo un poco.
func _partida_de_prueba() -> void:
	GameState.nueva_partida("Prueba")  # empieza sin Pokémon, como el original
	GameState.equipo.append(PokemonInstance.crear(Datos.especie(4), 5))
	GameState.equipo.append(PokemonInstance.crear(Datos.especie(25), 17))
	GameState.equipo[1].apodo = "Chispa"
	GameState.equipo[1].hp_actual = 3
	GameState.equipo[0].experiencia = 1234
	GameState.historia["fy_010"] = 2
	GameState.vuelo[3] = 1
	GameState.mapa_actual = "CiudadNaos"
	GameState.posicion_jugador = Vector2(412.5, 300)
	GameState.mira = 6
	GameState.dinero = 98765
	GameState.indice_lugar = 4
	GameState.tiempo_juego = 3725.5
	GameState.dificultad = GameState.Dificultad.MAESTRO


func _estado() -> String:
	return JSON.stringify(GameState.a_dict(), "", true)


func _ida_y_vuelta() -> void:
	_partida_de_prueba()
	var antes: String = _estado()
	_ok(SaveManager.guardar(3) == "", "guardar en el slot 3")
	_ok(GameState.slot == 3, "la partida queda en el slot 3")
	GameState.nueva_partida()
	var c := SaveManager.cargar(3)
	_ok(c.ok and not c.de_respaldo, "cargar el slot 3")
	var despues: String = _estado()
	_ok(JSON.parse_string(antes).hash() == JSON.parse_string(despues).hash(), "todo vuelve igual (equipo, historia, posición, dinero, tiempo...)")
	if JSON.parse_string(antes).hash() != JSON.parse_string(despues).hash():
		print("  antes:   ", antes, "\n  después: ", despues)
	_ok(GameState.equipo[1].movimientos.size() > 0 and GameState.equipo[1].especie.id_original == 25, "Pokémon con especie y movimientos")
	var r: Dictionary = SaveManager.resumen(3)
	_ok(r.get("nombre") == "Prueba" and r.get("mapa") == "CiudadNaos" and r.get("equipo", []).size() == 2, "resumen para la pantalla de cargar")


func _respaldo() -> void:
	_partida_de_prueba()
	SaveManager.guardar(4)
	GameState.dinero = 1
	SaveManager.guardar(4)
	_ok(FileAccess.file_exists(SaveManager.ruta(4) + ".bak"), "al guardar de nuevo, la anterior queda de respaldo")
	SaveManager.cargar(4)
	_ok(GameState.dinero == 1, "se carga la más nueva")


func _danado() -> void:
	var f := FileAccess.open(SaveManager.ruta(4), FileAccess.WRITE)
	f.store_string("{esto no es una partida")
	f.close()
	var c := SaveManager.cargar(4)
	_ok(c.ok and c.de_respaldo and GameState.dinero == 98765, "archivo dañado: carga el respaldo")
	_ok(SaveManager.resumen(4).get("respaldo") == true, "el resumen avisa que viene del respaldo")
	GameState.dinero = 5
	_ok(SaveManager.guardar(4) == "", "guardar sobre un archivo dañado")
	SaveManager.cargar(4)
	_ok(GameState.dinero == 5, "y se puede volver a cargar")


func _editado_a_mano() -> void:
	_partida_de_prueba()
	SaveManager.guardar(5)
	var texto: String = FileAccess.get_file_as_string(SaveManager.ruta(5))
	var f := FileAccess.open(SaveManager.ruta(5), FileAccess.WRITE)
	f.store_string(texto.replace("98765", "99999999"))
	f.close()
	var c := SaveManager.cargar(5)
	_ok(not c.ok or c.de_respaldo, "un archivo modificado a mano no pasa la comprobación")


func _sin_nada() -> void:
	var c := SaveManager.cargar(8)
	_ok(not c.ok and c.error != "", "slot vacío: error en lugar de partida")


func _slots_llenos() -> void:
	_partida_de_prueba()
	for n: int in range(1, SaveManager.SLOTS + 1):
		SaveManager.guardar(n)
	_ok(SaveManager.primer_libre() == 0 and SaveManager.ocupados().size() == 9, "9 slots ocupados")
	GameState.slot = 0
	_ok(SaveManager.guardar() != "", "sin slot libre, guardar una partida nueva avisa")


func _borrar() -> void:
	SaveManager.borrar(2)
	_ok(not SaveManager.existe(2) and SaveManager.primer_libre() == 2, "borrar libera el slot (y su respaldo)")
	GameState.slot = 0
	_ok(SaveManager.guardar() == "" and GameState.slot == 2, "una partida nueva va al primer slot libre")
