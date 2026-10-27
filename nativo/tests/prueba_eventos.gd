extends Node
## Pruebas del motor de eventos y de los datos de entrenadores:
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tests/prueba_eventos.tscn

var _fallas: int = 0


func _ready() -> void:
	GameState.nueva_partida("Prueba")
	_lectura()
	_errores()
	_condiciones()
	await _ejecucion()
	_entrenadores()
	_generados()
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	get_tree().quit(1 if _fallas else 0)


func _ok(cond: bool, que: String) -> void:
	print(("PASA  " if cond else "FALLA ") + que)
	if not cond:
		_fallas += 1


func _lectura() -> void:
	var e := Evento.desde_texto("""
# un comentario
decir 222 "Espacio"   # otro comentario
si trainer_2 == 0 y movil == 1:
	bandera trainer_2 = 1
sino si trainer_2 == 1:
	decir "Hola # esto no es comentario"
sino:
	fin
""")
	_ok(e.errores.is_empty(), "lee un evento sin errores")
	_ok(e.ordenes.size() == 2 and e.ordenes[0].orden == "decir" and e.ordenes[0].args == PackedStringArray(["222", "Espacio"]), "orden con argumentos y comillas")
	var si: Dictionary = e.ordenes[1]
	_ok(si.orden == "si" and si.ramas.size() == 2 and si.sino.size() == 1, "si / sino si / sino")
	_ok(si.ramas[1][1][0].args[0] == "Hola # esto no es comentario", "un # entre comillas no es comentario")


func _errores() -> void:
	var e := Evento.desde_texto("decir \"sin cerrar\nsi x == 1:\nbandera x = 2", "prueba.evento")
	_ok(e.errores.size() == 2, "detecta comillas sin cerrar y bloque vacío")
	_ok(e.errores.size() > 0 and e.errores[0].begins_with("prueba.evento:1:"), "los errores dicen archivo y línea: " + (e.errores[0] if e.errores.size() > 0 else ""))


func _condiciones() -> void:
	GameState.historia["trainer_2"] = 1
	_ok(Eventos.condicion_simple("trainer_2 == 1 y movil == 1"), "banderas, == e y")
	_ok(Eventos.condicion_simple("no trainer_3"), "una bandera que no existe vale 0")
	_ok(Eventos.condicion_simple("trainer[2] == 1"), "trainer[2] es la bandera trainer_2")
	_ok(not Eventos.condicion_simple("pkchoose == 1 o trainer_2 > 5"), "o")


func _ejecucion() -> void:
	var e := Evento.desde_texto("""
bandera cuenta = 5
bandera cuenta += 2
si cuenta == 7:
	bandera paso = 1
	dinero + 300
sino:
	bandera paso = 2
fin
bandera despues_de_fin = 1
""")
	var dinero: int = GameState.dinero
	await Eventos.ejecutar(e)
	_ok(GameState.bandera("cuenta") == 7 and GameState.bandera("paso") == 1, "bandera = y += con si")
	_ok(GameState.dinero == dinero + 300, "dinero +")
	_ok(GameState.bandera("despues_de_fin") == 0, "fin corta el evento")


func _entrenadores() -> void:
	var t: EntrenadorData = Datos.entrenador(2)
	_ok(t != null and t.nombre != "" and t.equipo.size() == 3, "entrenador 2: nombre y 3 Pokémon")
	var eq: Array[PokemonInstance] = t.crear_equipo() if t else []
	_ok(eq.size() == 3 and eq[0].especie.id_original == 19 and eq[0].nivel == 3, "crea su equipo (Rattata nv 3...)")
	var t25: EntrenadorData = Datos.entrenador(25)
	GameState.equipo[0].nivel = 40
	var eq25: Array[PokemonInstance] = t25.crear_equipo() if t25 else []
	_ok(eq25.size() > 0 and eq25[0].nivel == 38, "nivel escalado (setMinMax: máx del equipo 40 - 2 = 38)")
	_ok(eq25.size() > 0 and eq25[0].movimientos.size() == 4, "movimientos propios")
	GameState.historia["primerpkrival"] = 7
	var eq1: Array[PokemonInstance] = Datos.entrenador(1).crear_equipo()
	_ok(eq1.size() == 4 and eq1[3].especie.id_original == 7, "especie desde una bandera (inicial del rival)")


func _generados() -> void:
	var malos: int = 0
	var total: int = 0
	var base: String = "res://data/extraido/eventos"
	for mapa: String in DirAccess.get_directories_at(base):
		for f: String in DirAccess.get_files_at(base.path_join(mapa)):
			total += 1
			if not Evento.desde_archivo(base.path_join(mapa).path_join(f)).errores.is_empty():
				malos += 1
	_ok(total > 0 and malos == 0, "los %d eventos generados se leen sin errores (%d con errores)" % [total, malos])
