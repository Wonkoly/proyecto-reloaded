class_name MovimientoAprendible
extends Resource
## Un movimiento que una especie puede aprender y cómo.

enum Metodo { NIVEL, MT, TUTOR, DT }

@export var move: MoveData
## Nivel al que lo aprende (solo para Metodo.NIVEL; 0 en los demás).
@export var nivel: int = 0
@export var metodo: Metodo = Metodo.NIVEL
