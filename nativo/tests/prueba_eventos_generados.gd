extends SceneTree
## Todos los .evento (generados y propios): que se lean sin errores y que cada condición sea una
## expresión válida. Lista los problemas por archivo.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/prueba_eventos_generados.gd

var _malos: int = 0
var _condiciones: int = 0


func _initialize() -> void:
	await process_frame
	var ev: Node = root.get_node("Eventos")
	var EventoS = load("res://scripts/eventos/evento.gd")
	var archivos: Array[String] = []
	for base: String in ["res://data/extraido/eventos", "res://data/eventos"]:
		_listar(base, archivos)
	for ruta: String in archivos:
		var e = EventoS.desde_archivo(ruta)
		var problemas: PackedStringArray = e.errores.duplicate()
		_revisar(ev, e.ordenes, problemas)
		if not problemas.is_empty():
			_malos += 1
			if _malos <= 30:
				print("MAL  ", ruta, ": ", problemas[0], " (", problemas.size(), ")")
	print("%d eventos, %d condiciones, %d con problemas" % [archivos.size(), _condiciones, _malos])
	print("RESULTADO: ", "todo bien" if _malos == 0 else "%d fallas" % _malos)
	quit(1 if _malos else 0)


func _revisar(ev: Node, ordenes: Array, problemas: PackedStringArray) -> void:
	for o: Dictionary in ordenes:
		var conds: Array = []
		if o.orden == "si":
			for r: Array in o.ramas:
				conds.append(r[0])
				_revisar(ev, r[1], problemas)
			_revisar(ev, o.sino, problemas)
		elif o.orden == "mientras":
			conds.append(o.cond)
			_revisar(ev, o.cuerpo, problemas)
		for c: String in conds:
			_condiciones += 1
			var t: String = c.trim_prefix("no ")
			if t.begins_with("pregunta "):
				continue
			var x := Expression.new()
			if x.parse(ev._expresion(c), ev.ENTRADAS) != OK:
				problemas.append("línea %d: condición inválida: %s" % [o.linea, c])


func _listar(dir: String, out: Array[String]) -> void:
	for d: String in DirAccess.get_directories_at(dir):
		_listar(dir.path_join(d), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".evento"):
			out.append(dir.path_join(f))
