class_name Habilidades
## Las habilidades en combate (data/extraido/habilidades.json, tools/habilidades_original.py y las
## que se escriben a mano en BattlePokemon).

static var _datos: Dictionary = {}
static var _expresiones: Dictionary = {}
const VARIABLES: PackedStringArray = ["tipo", "modo", "poder", "eff", "estado_at", "estado_def", "ps_at", "max_at",
	"ps_def", "max_def", "hab_at", "hab_def", "sol", "dia"]


static func datos() -> Dictionary:
	if _datos.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/habilidades.json", FileAccess.READ)
		_datos = JSON.parse_string(f.get_as_text()) if f else {"danio": []}
	return _datos


static func nombre(h: int) -> String:
	return Textos.linea("txt_abilities", h)


## Ataque1GolpeaPokemon2: lo que las habilidades de los dos multiplican el daño de un golpe. Devuelve
## el factor y quién la usó (para el aviso), o [1.0, []].
static func factor_danio(atacante: BattlePokemon, defensor: BattlePokemon, move: MoveData, eff: float) -> Array:
	var hab_at: int = atacante.habilidad
	var hab_def: int = defensor.habilidad
	var valores: Array = [FormulasBatalla.TIPO_ORIGINAL[move.tipo], int(move.categoria), move.poder, eff,
		int(atacante.pokemon.estado), int(defensor.pokemon.estado), atacante.pokemon.hp_actual, atacante.hp_max,
		defensor.pokemon.hp_actual, defensor.hp_max, hab_at, hab_def, Clima.soleado(), Reloj.es_de_dia()]
	var factor: float = 1.0
	var usaron: Array[BattlePokemon] = []
	for r: Dictionary in datos().get("danio", []):
		var quien: BattlePokemon = atacante if r.de == "atacante" else defensor
		if quien.habilidad != int(r.habilidad) or not _cumple(str(r.cond), valores):
			continue
		factor *= float(r.factor)
		if quien not in usaron:
			usaron.append(quien)
	return [factor, usaron]


static func _cumple(cond: String, valores: Array) -> bool:
	if cond == "":
		return true
	if cond not in _expresiones:
		var e := Expression.new()
		_expresiones[cond] = e if e.parse(cond, VARIABLES) == OK else null
	var e: Expression = _expresiones[cond]
	return e != null and bool(e.execute(valores))
