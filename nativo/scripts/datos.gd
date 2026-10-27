class_name Datos
## Acceso a los datos extraídos (data/extraido/, ver tools/README.md).

const CARPETA_POKEMON: String = "res://data/extraido/pokemon"
const CARPETA_MOVIMIENTOS: String = "res://data/extraido/moves"

static var _especies_con_sprites: Dictionary[int, String] = {}


## La especie con ese id_original, o null si no está extraída.
static func especie(id_original: int) -> PokemonData:
	var ruta: String = _buscar(CARPETA_POKEMON, id_original)
	if ruta == "":
		push_error("No hay datos de la especie %d: corre tools/extraer.py" % id_original)
		return null
	return load(ruta) as PokemonData


## El movimiento con ese id_original, o null si no está extraído.
static func movimiento(id_original: int) -> MoveData:
	var ruta: String = _buscar(CARPETA_MOVIMIENTOS, id_original)
	if ruta == "":
		push_error("No hay datos del movimiento %d: corre tools/extraer.py" % id_original)
		return null
	return load(ruta) as MoveData


## Los archivos de datos se llaman NNNN_nombre.tres (NNNN = id_original).
static func _buscar(carpeta: String, id_original: int) -> String:
	var prefijo: String = "%04d_" % id_original
	for archivo: String in DirAccess.get_files_at(carpeta):
		archivo = archivo.trim_suffix(".remap")  # en un export, los .tres aparecen como .tres.remap
		if archivo.begins_with(prefijo) and archivo.ends_with(".tres"):
			return carpeta.path_join(archivo)
	return ""



## {id_original: nombre} de las especies con sprites de batalla extraídos, en orden de id.
static func especies_con_sprites() -> Dictionary[int, String]:
	if not _especies_con_sprites.is_empty():
		return _especies_con_sprites
	var archivos: Dictionary[int, String] = {}
	for archivo: String in DirAccess.get_files_at(CARPETA_POKEMON):
		if archivo.ends_with(".tres"):
			archivos[archivo.get_slice("_", 0).to_int()] = archivo
	var ids: Array[int] = []
	for carpeta: String in DirAccess.get_directories_at("res://assets/extraido/sprites/pokemon"):
		if carpeta.is_valid_int() and carpeta.to_int() in archivos:
			ids.append(carpeta.to_int())
	ids.sort()
	var nombres: Dictionary[int, String] = {}
	for id: int in ids:
		nombres[id] = (load(CARPETA_POKEMON.path_join(archivos[id])) as PokemonData).nombre
	_especies_con_sprites = nombres
	return nombres
