class_name Mapa
extends Node2D
## Raíz de un mapa del overworld generado por tools/extraer.py desde una room del original.
## Hijos: Fondos, TilesDebajo, BaseHierba, Objetos (y-sort: decorado, NPCs, puertas y el jugador),
## TilesArriba, Paredes, ZonaHierba, Salidas y Marcadores (instancias que aún no se convierten).

## Resolución de la vista del original en el overworld.
const RESOLUCION: Vector2i = Vector2i(320, 180)

## Nombre de la room en el original (PuebloAlba, Ruta_1...).
@export var nombre_original: String = ""
@export var tamano: Vector2i = Vector2i(320, 180)


func _ready() -> void:
	get_window().content_scale_size = RESOLUCION
	aplicar_historia()
	GameState.historia_cambiada.connect(aplicar_historia)


## Activa o desactiva lo que depende de la historia (grupo "historia", con metadata/condicion: una
## expresión sobre h = GameState.historia, generada desde CreateNPC*/CreateDoors).
func aplicar_historia() -> void:
	for n: Node in find_children("*", "", true, false):
		if n.is_in_group("historia"):
			_activar(n, cumple(str(n.get_meta("condicion", ""))))


func cumple(condicion: String) -> bool:
	if condicion == "":
		return true
	var e := Expression.new()
	if e.parse(condicion, ["h", "lugar"]) != OK:
		push_warning("Condición de historia inválida: %s" % condicion)
		return true
	return bool(e.execute([GameState.historia, GameState.indice_lugar]))


func _activar(n: Node, activo: bool) -> void:
	if n is CollisionShape2D:
		(n as CollisionShape2D).set_deferred("disabled", not activo)
		return
	if n is CanvasItem:
		(n as CanvasItem).visible = activo
	# Sin procesar, los cuerpos y áreas salen de la física (no chocan ni detectan).
	n.process_mode = Node.PROCESS_MODE_INHERIT if activo else Node.PROCESS_MODE_DISABLED


## Donde van el jugador y lo que se ordena por y.
func objetos() -> Node2D:
	return $Objetos
