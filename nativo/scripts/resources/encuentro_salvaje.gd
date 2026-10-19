class_name EncuentroSalvaje
extends Resource
## Una especie de una SubtablaEncuentros.

## id_original de la especie (el número del archivo en data/extraido/pokemon/).
@export var id_especie: int = 1
## NV = base + ceil(random(k)) del original → nivel_min = base + 1, nivel_max = base + k.
@export_range(1, 100) var nivel_min: int = 2
@export_range(1, 100) var nivel_max: int = 4
## Cuántos de los 1000 valores de AparicionSalvajes ocupa.
@export var peso: int = 1
## Solo para especies que dependen de la historia una a una (ruinas Unown, salas de fósiles).
@export var condicion: String = ""
