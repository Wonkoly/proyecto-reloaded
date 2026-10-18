class_name Datos
## Acceso a los datos extraídos (data/extraido/, ver tools/README.md).

const CARPETA_POKEMON: String = "res://data/extraido/pokemon"


## La especie con ese id_original, o null si no está extraída.
static func especie(id_original: int) -> PokemonData:
	var prefijo: String = "%04d_" % id_original
	for archivo: String in DirAccess.get_files_at(CARPETA_POKEMON):
		if archivo.begins_with(prefijo) and archivo.ends_with(".tres"):
			return load(CARPETA_POKEMON.path_join(archivo)) as PokemonData
	push_error("No hay datos de la especie %d: corre tools/extraer.py" % id_original)
	return null
