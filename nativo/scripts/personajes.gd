class_name Personajes
extends RefCounted
## Sprites de los protagonistas (código Q/CARA): data/extraido/personajes.json (generado) más
## data/personajes.json (propio, versionado), que añade o sustituye entradas. En la tabla propia
## los nombres pueden ser rutas res:// completas; si no, son sprites de assets/extraido/sprites/overworld.

const EXTRAIDO: String = "res://data/extraido/personajes.json"
const PROPIO: String = "res://data/personajes.json"
const OVERWORLD: String = "res://assets/extraido/sprites/overworld/%s.tres"

## Protagonistas propios (después de los 0-9 originales; 10 = sprite de un entrenador).
const GALLETA: int = 11


static func tabla() -> Dictionary:
	var t: Dictionary = _leer(EXTRAIDO)
	var propia: Dictionary = _leer(PROPIO)
	for grupo: String in propia:
		var g: Dictionary = t.get(grupo, {})
		g.merge(propia[grupo], true)
		t[grupo] = g
	return t


## Nombres [d, u, r, (db, ub, rb, p_d, p_u, p_r)] del personaje elegido en GameState.
static func del_jugador() -> Array:
	var t: Dictionary = tabla()
	var v: Variant = t.get("entrenadores", {}).get(str(GameState.personaje_entrenador)) if GameState.personaje == 10 \
		else t.get("protagonistas", {}).get(str(GameState.personaje))
	return v if v is Array else []


static func cargar(nombre: String) -> SpriteOriginal:
	return load(nombre if nombre.begins_with("res://") else OVERWORLD % nombre)


## Mayor índice de protagonista disponible (para el código Q/CARA).
static func ultimo() -> int:
	var m: int = 10
	for k: String in tabla().get("protagonistas", {}):
		m = maxi(m, int(k))
	return m


static func _leer(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return v if v is Dictionary else {}
