@tool
class_name FondoMenu
extends Control
## Fondo de los menús: degradado vertical y líneas de luz que cruzan (como las obj_lineafreak del
## título original, más suaves).

@export var color_arriba: Color = Color(0.051, 0.071, 0.133)
@export var color_abajo: Color = Color(0.118, 0.067, 0.243)
@export var color_lineas: Color = Color(0.486, 0.361, 1.0)

var _lineas: Array[Array] = []  # [x, y, velocidad, alfa, largo]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if randf() < 1.2 * delta:
		_lineas.append([-200.0, randf() * size.y, 500.0 + randf() * 300.0, randf_range(0.08, 0.25), randf_range(80.0, 220.0)])
	for l: Array in _lineas:
		l[0] += l[2] * delta
	_lineas = _lineas.filter(func(l: Array) -> bool: return l[0] < size.x + 50.0)
	queue_redraw()


func _draw() -> void:
	var colores := PackedColorArray([color_arriba, color_arriba, color_abajo, color_abajo])
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), colores)
	for l: Array in _lineas:
		var c: Color = Color(color_lineas, l[3])
		var a := Vector2(l[0] - l[4], l[1])
		draw_polyline_colors(PackedVector2Array([a, Vector2(l[0], l[1])]), PackedColorArray([Color(c, 0.0), c]), 1.5, true)
