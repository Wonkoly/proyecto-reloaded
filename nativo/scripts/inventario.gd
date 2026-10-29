class_name Inventario
## La mochila: los objetos del jugador (GameState.objetos: id → cantidad) y sus datos del original
## (data/extraido/objetos.json: nombre, descripción, precio y bolsillo; ver tools/objetos_original.py).

const DATOS: String = "res://data/extraido/objetos.json"
## Bolsillos de la mochila en el orden del original, con su nombre.
const BOLSILLOS: Array[String] = ["objeto", "ball", "baya", "mt", "clave"]
const NOMBRES_BOLSILLO: Dictionary[String, String] = {"objeto": "Objetos", "ball": "Poké Balls", "baya": "Bayas",
	"mt": "MT y MO", "clave": "Objetos clave", "base": "Decoración", "dt": "DT"}
## Como máximo 999 de cada objeto (PillaObject).
const MAXIMO: int = 999

## UseDirectObject: PS que cura cada objeto (número), "max" = todos, "1/4" = una fracción del máximo.
const CURA: Dictionary[int, Variant] = {15: 20, 681: 20, 23: 30, 580: 40, 16: 50, 24: 50, 548: 50, 25: 80,
	26: 100, 17: 120, 549: 200, 115: 10, 18: "max", 19: "max", 118: "1/4", 579: "1/5"}
## Revivir: 21 (la mitad), 22 y 550 (todo), 130 (1 PS).
const REVIVE: Dictionary[int, String] = {21: "1/2", 22: "max", 550: "max", 130: "1"}

static var _datos: Dictionary = {}
static var _evoluciones: Dictionary = {}

## UseObject: vitaminas y Mochis → dígito de IV que suben (0 PS, 1 Ataque, 2 Defensa, 3 At. Esp.,
## 4 Def. Esp., 5 Velocidad) y el texto de TextMenu que dicen.
const VITAMINAS: Dictionary[int, int] = {32: 0, 698: 0, 36: 1, 699: 1, 34: 2, 700: 2, 33: 3, 701: 3,
	37: 4, 702: 4, 35: 5, 703: 5}
const TEXTO_VITAMINA: Array[int] = [534, 538, 536, 535, 539, 537]
## Caramelo Raro (UseObject, OB = 38): sube un nivel.
const CARAMELO_RARO: int = 38


## UseObject (piedras...): la especie en la que evoluciona `p` con el objeto `id`, o null.
static func evolucion_con(id: int, p: PokemonInstance) -> PokemonData:
	var destino: Variant = (_tabla_evoluciones().get(str(id), {}) as Dictionary).get(str(p.especie.id_original))
	return Datos.especie(int(destino)) if destino != null else null


static var _mts: Dictionary = {}


## UseObject: el movimiento que enseña una MT (194-290, 618-637, MTAtack) o un DT (5000 + N), o null.
static func movimiento_que_ensena(id: int) -> MoveData:
	if id > 5000 and id <= 5000 + 866:
		return Datos.movimiento(id - 5000)
	if _mts.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/pokemon/mt_movimientos.json", FileAccess.READ)
		_mts = JSON.parse_string(f.get_as_text()) if f else {"-": 0}
	return Datos.movimiento(int(_mts[str(id)])) if _mts.has(str(id)) else null


static func hace_evolucionar(id: int) -> bool:
	return _tabla_evoluciones().has(str(id))


static func _tabla_evoluciones() -> Dictionary:
	if _evoluciones.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/pokemon/evoluciones_objeto.json", FileAccess.READ)
		_evoluciones = JSON.parse_string(f.get_as_text()) if f else {"-": {}}
	return _evoluciones


static func datos(id: int) -> Dictionary:
	if _datos.is_empty() and FileAccess.file_exists(DATOS):
		_datos = JSON.parse_string(FileAccess.get_file_as_string(DATOS))
	return _datos.get(str(id), {})


static func nombre(id: int) -> String:
	return str(datos(id).get("nombre", "?"))


static func precio(id: int) -> int:
	return int(datos(id).get("precio", 0))


static func bolsillo(id: int) -> String:
	var b: String = str(datos(id).get("bolsillo", "objeto"))
	return "objeto" if b in ["base", "dt"] else b


static func descripcion(id: int) -> String:
	return str(datos(id).get("descripcion", "")).replace("#", " ")


static func cantidad(id: int) -> int:
	return int(GameState.objetos.get(id, 0))


## PillaObject: agrega n del objeto (falso si no cabe).
static func dar(id: int, n: int = 1) -> bool:
	if id <= 0 or n <= 0 or datos(id).is_empty() or cantidad(id) + n > MAXIMO:
		return false
	GameState.objetos[id] = cantidad(id) + n
	return true


static func quitar(id: int, n: int = 1) -> bool:
	if cantidad(id) < n:
		return false
	GameState.objetos[id] = cantidad(id) - n
	if GameState.objetos[id] <= 0:
		GameState.objetos.erase(id)
	return true


## Los objetos de un bolsillo, ordenados por id.
static func de_bolsillo(b: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in GameState.objetos:
		if bolsillo(id) == b and cantidad(id) > 0:
			out.append(id)
	out.sort()
	return out


## Se puede usar sobre un Pokémon fuera de combate (UseDirectObject: curar o revivir).
static func es_de_curar(id: int) -> bool:
	return CURA.has(id) or REVIVE.has(id)


## UseDirectObject sobre un Pokémon: devuelve los PS recuperados (0 = no hizo nada; no gasta).
static func usar_en(id: int, p: PokemonInstance) -> int:
	var maximo: int = p.calcular_stats()["hp"]
	var antes: int = p.hp_actual
	if REVIVE.has(id):
		if p.hp_actual > 0:
			return 0
		var r: String = REVIVE[id]
		p.hp_actual = maximo if r == "max" else (1 if r == "1" else maxi(1, maximo / 2))
	elif CURA.has(id):
		if p.hp_actual <= 0 or p.hp_actual >= maximo:
			return 0
		var c: Variant = CURA[id]
		var suma: int = maximo if c is String and c == "max" else (maximo / int(str(c).get_slice("/", 1)) if c is String else int(c))
		p.hp_actual = mini(maximo, p.hp_actual + suma)
	return p.hp_actual - antes
