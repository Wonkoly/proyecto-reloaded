class_name InfoPartida
## Textos para mostrar una partida guardada (SaveManager.resumen) en los menús.


## "CiudadNaos" → "Ciudad Naos", "Ruta_29" → "Ruta 29".
static func nombre_mapa(room: String) -> String:
	var r := RegEx.create_from_string("([a-z0-9])([A-Z])")
	return r.sub(room, "$1 $2", true).replace("_", " ").strip_edges()


## 3725 → "1 h 02 min".
static func tiempo(segundos: int) -> String:
	return "%d h %02d min" % [segundos / 3600, (segundos / 60) % 60]


static func fecha(unix: int) -> String:
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	return "%02d/%02d/%d %02d:%02d" % [t.day, t.month, t.year, t.hour, t.minute]


## [[especie, nivel], ...] → "Charmander Nv. 5 · Pikachu Nv. 17".
static func equipo(lista: Array) -> String:
	var partes: PackedStringArray = []
	for p: Variant in lista:
		if p is Array and p.size() == 2:
			var e: PokemonData = Datos.especie(int(p[0]))
			partes.append("%s Nv. %d" % [e.nombre if e else "?", int(p[1])])
	return " · ".join(partes) if not partes.is_empty() else "Sin Pokémon"
