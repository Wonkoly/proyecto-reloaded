class_name Mapa
extends Node2D
## Raíz de un mapa del overworld generado por tools/extraer.py desde una room del original.
## Hijos: Fondos, TilesDebajo, BaseHierba, Objetos (y-sort: decorado, NPCs, puertas y el jugador),
## TilesArriba, Paredes, ZonaHierba, Salidas y Marcadores (instancias que aún no se convierten).

## Nombre de la room en el original (PuebloAlba, Ruta_1...).
@export var nombre_original: String = ""
@export var tamano: Vector2i = Vector2i(320, 180)


## Donde van el jugador y lo que se ordena por y.
func objetos() -> Node2D:
	return $Objetos
