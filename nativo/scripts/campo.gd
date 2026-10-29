class_name Campo
## Lo que las MO necesitan saber de cada mapa (data/extraido/campo.json, tools/campo_original.py).

## Destello (AttackHabExt).
const HABILIDAD_DESTELLO: int = 4

static var _datos: Dictionary = {}


static func datos() -> Dictionary:
	if _datos.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/campo.json", FileAccess.READ)
		_datos = JSON.parse_string(f.get_as_text()) if f else {}
	return _datos


## AdjustmentsRoom al cargar un mapa: algunas rooms apagan Destello y las cuevas oscuras crean
## obj_Oscuro1.
static func al_entrar(mapa: Mapa) -> void:
	if mapa.nombre_original in datos().get("apaga_destello", []):
		GameState.historia.erase("usadestello")
	if mapa.nombre_original in datos().get("oscuros", []):
		var o := Oscuridad.new()
		o.name = "Oscuridad"
		mapa.add_child(o)
