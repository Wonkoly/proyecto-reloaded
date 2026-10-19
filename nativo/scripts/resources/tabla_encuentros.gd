class_name TablaEncuentros
extends Resource
## Los Pokémon salvajes de un mapa (data/extraido/encuentros/<mapa>.tres, generado de
## AparicionSalvajes por tools/extraer.py). Los mapas sin tabla no tienen encuentros.

const CARPETA: String = "res://data/extraido/encuentros"

## En orden: gana la primera que coincide (las que tienen zona van antes que la general).
@export var subtablas: Array[SubtablaEncuentros] = []
## Partes del mapa donde también salen salvajes fuera de la hierba (cuevas: ActivacionSalvajes).
@export var sin_hierba: Array[Rect2] = []


## La tabla de un mapa (nombre de la room del original), o null si no tiene.
static func de_mapa(nombre_original: String) -> TablaEncuentros:
	var ruta: String = CARPETA.path_join(SceneManager.snake(nombre_original) + ".tres")
	return load(ruta) as TablaEncuentros if ResourceLoader.exists(ruta) else null


## La subtabla que vale ahora para ese método y posición, o null.
func subtabla(metodo: SubtablaEncuentros.Metodo, es_de_dia: bool, posicion: Vector2, cumple: Callable) -> SubtablaEncuentros:
	for s: SubtablaEncuentros in subtablas:
		if s.aplica(metodo, es_de_dia, posicion, cumple):
			return s
	return null


## Si en esa posición salen salvajes sin hierba (ActivacionSalvajes).
func en_sin_hierba(posicion: Vector2) -> bool:
	for r: Rect2 in sin_hierba:
		if r.grow(0.5).has_point(posicion):
			return true
	return false
