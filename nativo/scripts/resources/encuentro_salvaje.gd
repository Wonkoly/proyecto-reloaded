class_name EncuentroSalvaje
extends Resource
## Un Pokémon que puede aparecer en la hierba de un mapa.

## id_original de la especie (el número del archivo en data/extraido/pokemon/).
@export var id_especie: int = 1
@export_range(1, 100) var nivel_min: int = 2
@export_range(1, 100) var nivel_max: int = 4
## Peso relativo frente a los demás encuentros del mapa.
@export var peso: int = 1
