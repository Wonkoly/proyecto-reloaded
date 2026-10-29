class_name Buceo
## Buceo (MO 7): a dónde lleva sumergirse o salir a la superficie (GoDiving), desde
## data/extraido/buceo.json (tools/buceo_original.py).

static var _datos: Dictionary = {}


static func datos() -> Dictionary:
	if _datos.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/buceo.json", FileAccess.READ)
		_datos = JSON.parse_string(f.get_as_text()) if f else {}
	return _datos


## GoDiving(vk_down / vk_up): {mapa, posicion, indice, y salida_mapa/salida_posicion si las pone}, o {}
## si desde ahí no se puede. `superficie`: la superficie más cercana (las llegadas que la usan).
static func destino(direccion: String, mapa: String, indice: int, pos: Vector2, superficie: Vector2) -> Dictionary:
	var r: Dictionary = {}
	for b: Dictionary in datos().get("%s:%s" % [direccion, mapa], []):
		if b.indice != null and int(b.indice) != indice:
			continue
		for paso: Dictionary in b.pasos:
			if paso.cond == "" or _cumple(paso.cond, pos):
				r.merge(paso, true)
	if not r.has("mapa"):
		return {}
	var d: Dictionary = {"mapa": r.mapa, "indice": int(r.get("indice", 0)),
		"posicion": Vector2(_coordenada(r.get("xx"), pos.x, superficie.x), _coordenada(r.get("yy"), pos.y, superficie.y))}
	if r.has("salida_mapa"):
		d["salida_mapa"] = r.salida_mapa
		d["salida_posicion"] = Vector2(r.get("salida_x", 0), r.get("salida_y", 0))
	return d


static func _coordenada(v: Variant, propia: float, superficie: float) -> float:
	if v is String:
		return superficie if v == "superficie" else propia
	return float(v) if v != null else propia


static func _cumple(cond: String, pos: Vector2) -> bool:
	var e := Expression.new()
	if e.parse(cond, ["x", "y"]) != OK:
		push_warning("GoDiving: no se entiende la condición " + cond)
		return false
	return bool(e.execute([pos.x, pos.y]))
