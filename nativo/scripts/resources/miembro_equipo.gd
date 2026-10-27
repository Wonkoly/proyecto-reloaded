class_name MiembroEquipo
extends Resource
## Un Pokémon del equipo de un entrenador (TrainerPokemon: PKn, NVn, OBn, ATn).

## id_original de la especie (0 = el de la bandera `especie_bandera`).
@export var especie: int = 0
## Bandera de la historia con la especie (p. ej. primerpkrival: el inicial del rival).
@export var especie_bandera: String = ""
@export_range(1, 100) var nivel: int = 5
## setMinMax(nivel, MAX_NV, ajuste): sube hasta el nivel más alto de tu equipo + ajuste.
@export var nivel_escala: bool = false
@export var ajuste: int = 0
## Objeto equipado (0 = ninguno).
@export var objeto: int = 0
## Movimientos propios (ids); vacío = los que aprende por nivel.
@export var movimientos: PackedInt32Array = PackedInt32Array()
## Solo si se cumple (condición de evento sobre las banderas, p. ej. "pkchoose == 1"); vacío = siempre.
@export var condicion: String = ""


## El nivel con la escala del original (entre 2 y 100).
func nivel_para(nivel_max_equipo: int) -> int:
	var n: int = nivel
	if nivel_escala and nivel_max_equipo + ajuste > n:
		n = nivel_max_equipo + ajuste
	return clampi(n, 2, 100)
