extends Node
## Cambia de escena con un fundido a negro: entre mapas del overworld (por las salidas) y del
## overworld a la batalla y de vuelta al mismo mapa y posición. Guarda el estado en GameState.

const RUTA_MAPAS: String = "res://assets/extraido/mapas/%s.tscn"
const ESCENA_JUGADOR: String = "res://scenes/overworld/jugador.tscn"
const ESCENA_BATALLA: String = "res://scenes/battle/battle_arena.tscn"
const DURACION_FUNDIDO: float = 0.25

var en_transicion: bool = false
var _velo: ColorRect


func _ready() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 128
	add_child(capa)
	_velo = ColorRect.new()
	_velo.color = Color.BLACK
	_velo.modulate.a = 0.0
	_velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa.add_child(_velo)


static func ruta_mapa(nombre_original: String) -> String:
	return RUTA_MAPAS % _snake(nombre_original)


func existe_mapa(nombre_original: String) -> bool:
	return ResourceLoader.exists(ruta_mapa(nombre_original))


## Lleva al jugador a un mapa (nombre de la room del original) en esa posición.
func ir_a_mapa(nombre_original: String, posicion: Vector2, mira: int = -1) -> void:
	if en_transicion or not existe_mapa(nombre_original):
		if not existe_mapa(nombre_original):
			push_warning("El mapa %s no está extraído (tools/extraer.py --mapas-lista)" % nombre_original)
		return
	GameState.mapa_actual = nombre_original
	GameState.posicion_jugador = posicion
	if mira > 0:
		GameState.mira = mira
	await _con_fundido(_cargar_mapa)


## Usa una salida del mapa actual desde la posición del jugador.
func usar_salida(salida: Salida, jugador: Jugador) -> void:
	if salida.volver:
		if GameState.mapa_salida != "":
			ir_a_mapa(GameState.mapa_salida, GameState.posicion_salida, jugador.mira)
		return
	if salida.activacion == Salida.Activacion.ARRIBA:
		# Al salir del interior se vuelve frente a la puerta (DoorEnter: outx = puerta, outy = jugador).
		GameState.mapa_salida = GameState.mapa_actual
		GameState.posicion_salida = Vector2(salida.global_position.x, jugador.global_position.y)
	ir_a_mapa(salida.destino, salida.posicion_destino(jugador.global_position), jugador.mira)


## Del overworld a una batalla contra un salvaje; al terminar se vuelve con volver_de_batalla().
func ir_a_batalla(salvaje: PokemonInstance, jugador: Jugador) -> void:
	if en_transicion:
		return
	GameState.posicion_jugador = jugador.global_position
	GameState.mira = jugador.mira
	GameState.salvaje = salvaje
	await _con_fundido(func() -> void: get_tree().change_scene_to_file(ESCENA_BATALLA))


func volver_de_batalla() -> void:
	GameState.salvaje = null
	if not en_transicion:
		await _con_fundido(_cargar_mapa)


func _cargar_mapa() -> void:
	var mapa: Mapa = (load(ruta_mapa(GameState.mapa_actual)) as PackedScene).instantiate()
	var jugador: Jugador = (load(ESCENA_JUGADOR) as PackedScene).instantiate()
	jugador.position = GameState.posicion_jugador
	jugador.mira = GameState.mira
	mapa.objetos().add_child(jugador)
	get_tree().change_scene_to_node(mapa)


func _con_fundido(cambio: Callable) -> void:
	en_transicion = true
	var t: Tween = create_tween()
	t.tween_property(_velo, "modulate:a", 1.0, DURACION_FUNDIDO)
	await t.finished
	cambio.call()
	await get_tree().process_frame
	await get_tree().process_frame
	t = create_tween()
	t.tween_property(_velo, "modulate:a", 0.0, DURACION_FUNDIDO)
	await t.finished
	en_transicion = false


## Mismo criterio que tools/extraer.py: PuebloAlba → pueblo_alba.
static func _snake(nombre: String) -> String:
	var r := RegEx.new()
	r.compile("([a-z0-9])([A-Z])")
	return r.sub(nombre, "$1_$2", true).to_lower()
