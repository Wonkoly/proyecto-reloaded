class_name Evento
extends RefCounted
## Un evento de la historia leído de un archivo .evento (ver docs/eventos.md). Lo ejecuta el autoload
## Eventos. El formato es una orden por línea; los bloques de "si" van con sangría:
##
##   # comentario
##   si trainer_2 == 0:
##       exclamacion
##       decir 222
##       combate 2
##       si gano:
##           bandera trainer_2 = 1
##   sino:
##       decir "¡Eres muy fuerte!"
##
## Cada orden queda como {"orden", "args": PackedStringArray, "linea"}; un "si" como
## {"orden": "si", "ramas": [[condición, órdenes]...], "sino": órdenes, "linea"}.

var ruta: String = ""
var ordenes: Array = []
## Errores de lectura ("archivo:línea: qué pasa"); un evento con errores no se ejecuta.
var errores: PackedStringArray = []


static func desde_archivo(path: String) -> Evento:
	var e := Evento.new()
	e.ruta = path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		e.errores.append("%s: no se pudo abrir" % path)
		return e
	e._leer(f.get_as_text())
	return e


static func desde_texto(texto: String, nombre: String = "(texto)") -> Evento:
	var e := Evento.new()
	e.ruta = nombre
	e._leer(texto)
	return e


func _leer(texto: String) -> void:
	var lineas: Array = []  # [sangría, texto, número de línea]
	var n: int = 0
	for crudo: String in texto.replace("\r", "").split("\n"):
		n += 1
		var sin_comentario: String = _quitar_comentario(crudo)
		if sin_comentario.strip_edges() == "":
			continue
		var sangria: int = 0
		for c: String in sin_comentario:
			if c == " ":
				sangria += 1
			elif c == "\t":
				sangria += 4
			else:
				break
		lineas.append([sangria, sin_comentario.strip_edges(), n])
	var i: Array = [0]
	ordenes = _bloque(lineas, i, 0)


## Un "#" fuera de comillas empieza un comentario.
static func _quitar_comentario(linea: String) -> String:
	var en_comillas: bool = false
	for k: int in linea.length():
		var c: String = linea[k]
		if c == "\"":
			en_comillas = not en_comillas
		elif c == "#" and not en_comillas:
			return linea.left(k)
	return linea


func _bloque(lineas: Array, i: Array, sangria: int) -> Array:
	var out: Array = []
	while i[0] < lineas.size():
		var l: Array = lineas[i[0]]
		if l[0] < sangria:
			break
		if l[0] > sangria:
			_error(l[2], "sangría inesperada")
			i[0] += 1
			continue
		var texto: String = l[1]
		if texto.begins_with("si ") and texto.ends_with(":"):
			out.append(_si(lineas, i, sangria))
			continue
		if _es_sino(texto):
			_error(l[2], "\"sino\" sin un \"si\" antes")
			i[0] += 1
			continue
		var partes: PackedStringArray = partir(texto)
		if partes.is_empty():
			_error(l[2], "comillas sin cerrar")
		else:
			out.append({"orden": partes[0], "args": partes.slice(1), "linea": l[2]})
		i[0] += 1
	return out


func _si(lineas: Array, i: Array, sangria: int) -> Dictionary:
	var l: Array = lineas[i[0]]
	var nodo: Dictionary = {"orden": "si", "ramas": [], "sino": [], "linea": l[2]}
	var cond: String = l[1].substr(3, l[1].length() - 4).strip_edges()
	i[0] += 1
	nodo.ramas.append([cond, _hijos(lineas, i, sangria, l[2])])
	while i[0] < lineas.size() and lineas[i[0]][0] == sangria and _es_sino(lineas[i[0]][1]):
		var t: String = lineas[i[0]][1]
		var linea: int = lineas[i[0]][2]
		i[0] += 1
		var resto: String = t.trim_prefix("sino").trim_prefix("si no").strip_edges().trim_suffix(":").strip_edges()
		if resto.begins_with("si "):
			nodo.ramas.append([resto.substr(3).strip_edges(), _hijos(lineas, i, sangria, linea)])
		else:
			nodo.sino = _hijos(lineas, i, sangria, linea)
			break
	return nodo


func _hijos(lineas: Array, i: Array, sangria: int, linea: int) -> Array:
	if i[0] >= lineas.size() or lineas[i[0]][0] <= sangria:
		_error(linea, "el bloque está vacío (las órdenes de adentro van con más sangría)")
		return []
	return _bloque(lineas, i, lineas[i[0]][0])


static func _es_sino(texto: String) -> bool:
	return texto.ends_with(":") and (texto.begins_with("sino") or texto.begins_with("si no"))


## Parte una línea en palabras; lo que va entre comillas es una sola (sin las comillas). Vacío si
## quedan comillas sin cerrar.
static func partir(linea: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var actual: String = ""
	var en_comillas: bool = false
	var hay: bool = false
	for c: String in linea:
		if c == "\"":
			en_comillas = not en_comillas
			hay = true
		elif c in [" ", "\t"] and not en_comillas:
			if hay:
				out.append(actual)
			actual = ""
			hay = false
		else:
			actual += c
			hay = true
	if en_comillas:
		return PackedStringArray()
	if hay:
		out.append(actual)
	return out


func _error(linea: int, que: String) -> void:
	errores.append("%s:%d: %s" % [ruta, linea, que])
