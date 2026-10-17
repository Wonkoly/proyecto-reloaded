## A GameMaker 8 array variable: up to two dimensions, sparse, unset elements read as 0.
## Stored inside instance/global dictionaries in place of the scalar value.
class_name GMArray
extends RefCounted

const STRIDE := 32000

var data: Dictionary = {}

func get_at(i: int, j: int) -> Variant:
	return data.get(i * STRIDE + j, 0.0)

func set_at(i: int, j: int, value: Variant) -> void:
	data[i * STRIDE + j] = value
