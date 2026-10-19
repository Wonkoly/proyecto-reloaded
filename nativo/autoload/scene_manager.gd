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
	process_mode = Node.PROCESS_MODE_ALWAYS  # la consola dev pausa el juego mientras está abierta
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
	return RUTA_MAPAS % snake(nombre_original)


func existe_mapa(nombre_original: String) -> bool:
	return ResourceLoader.exists(ruta_mapa(nombre_original))


## Posición especial: el centro del mapa (la consola dev la usa con "tp <mapa>").
const CENTRO: Vector2 = Vector2(-1, -1)


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
		# OutDoorStepActions: a global.room_out (outx, outy o la posición fija de esa room) y se borra.
		if GameState.mapa_salida != "":
			var mapa: String = GameState.mapa_salida
			var pos: Vector2 = salida.volver_posicion if salida.volver_posicion != Vector2(-1, -1) else GameState.posicion_salida
			GameState.mapa_salida = ""
			ir_a_mapa(mapa, pos, jugador.mira)
		return
	# DoorEnter / NoDoorEnter: outx = la puerta, outy = el jugador.
	var aqui := Vector2(salida.global_position.x, jugador.global_position.y)
	match salida.regreso:
		Salida.Regreso.GUARDAR:
			GameState.mapa_salida = GameState.mapa_actual
			GameState.posicion_salida = aqui
		Salida.Regreso.GUARDAR_SI_VACIO:
			if GameState.mapa_salida == "":
				GameState.mapa_salida = GameState.mapa_actual
				GameState.posicion_salida = aqui
		Salida.Regreso.BORRAR:
			GameState.mapa_salida = ""
	if salida.indice_lugar >= 0:
		GameState.indice_lugar = salida.indice_lugar
	ir_a_mapa(salida.destino, salida.posicion_destino(jugador.global_position), jugador.mira)


## Del overworld a una batalla contra un salvaje; al terminar se vuelve con volver_de_batalla().
func ir_a_batalla(salvaje: PokemonInstance, jugador: Jugador = null) -> void:
	if en_transicion:
		return
	if jugador:
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
	if GameState.posicion_jugador == CENTRO:
		GameState.posicion_jugador = Vector2(mapa.tamano) / 2.0
	jugador.position = GameState.posicion_jugador
	jugador.mira = GameState.mira
	GameState.mapa_actual = mapa.nombre_original
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
static func snake(nombre: String) -> String:
	var r := RegEx.new()
	r.compile("([a-z0-9])([A-Z])")
	return r.sub(nombre, "$1_$2", true).to_lower()
