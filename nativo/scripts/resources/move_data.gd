class_name MoveData
extends Resource
## Definición de un movimiento.

@export var nombre: String = ""
@export var tipo: Tipos.Tipo = Tipos.Tipo.NORMAL
@export var poder: int = 0
## Segundos de espera antes de poder volver a usarlo.
@export var cooldown: float = 1.0
## Alcance en píxeles.
@export var alcance: float = 32.0
@export_multiline var descripcion: String = ""
