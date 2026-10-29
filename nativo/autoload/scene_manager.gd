extends Node
## Cambia de escena con un fundido a negro: entre mapas del overworld (por las salidas) y del
## overworld a la batalla y de vuelta al mismo mapa y posición. Guarda el estado en GameState.

const RUTA_MAPAS: String = "res://assets/extraido/mapas/%s.tscn"
const ESCENA_JUGADOR: String = "res://scenes/overworld/jugador.tscn"
const ESCENA_BATALLA: String = "res://scenes/battle/battle_arena.tscn"
const DURACION_FUNDIDO: float = 0.25

## El mapa nuevo ya está en el árbol (los eventos siguen después de un combate o de "ir_a").
signal mapa_cargado

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
	if GameState.pokemon_para_combatir() == null:
		_preparar_centro()  # todo el equipo debilitado
	if not en_transicion:
		await _con_fundido(_cargar_mapa)


## Del overworld a un combate contra el entrenador `n` (lo pide un evento: "combate n").
func ir_a_combate(n: int, jugador: Jugador = null, companeros: Array[int] = []) -> void:
	GameState.combate_companeros = companeros
	if jugador:
		GameState.posicion_jugador = jugador.global_position
		GameState.mira = jugador.mira
	GameState.combate_entrenador = n
	# EntrenadorHabla: last_trainer_x/y/mira, donde aparece después su NPC de vencido.
	var mapa: Node = get_tree().current_scene
	if mapa:
		for npc: Npc in get_tree().get_nodes_in_group("npcs"):
			if npc.entrenador == n:
				GameState.ultimo_entrenador = {"id": n, "mapa": GameState.mapa_actual,
					"x": npc.position.x, "y": npc.position.y, "mira": npc.mira}
	await _con_fundido(func() -> void: get_tree().change_scene_to_file(ESCENA_BATALLA))


## Vuelve del combate al mismo lugar y el evento sigue con el resultado. Si perdió, al último Centro
## Pokémon (GoCentroPokemon) y el evento termina ahí.
func volver_de_combate(gano: bool) -> void:
	GameState.combate_entrenador = 0
	GameState.combate_companeros = []
	if not gano:
		_preparar_centro()
	await _con_fundido(_cargar_mapa)
	Eventos.combate_terminado.emit(gano)


const CENTROS: String = "res://data/extraido/centros.json"
static var _centros: Dictionary = {}


static func centros() -> Dictionary:
	if _centros.is_empty() and FileAccess.file_exists(CENTROS):
		_centros = JSON.parse_string(FileAccess.get_file_as_string(CENTROS))
	return _centros


## GoCentroPokemon: cura al equipo y deja al jugador en el último centro (la casa si no hay), con la
## salida apuntando a su ciudad.
func _preparar_centro() -> void:
	GameState.curar_equipo()
	var d: Dictionary = centros().get("destinos", {}).get(str(GameState.ultimo_centro), {})
	if d.is_empty() or not existe_mapa(str(d.get("mapa", ""))):
		d = {"mapa": GameState.INICIO_MAPA, "x": GameState.INICIO_POSICION.x, "y": GameState.INICIO_POSICION.y,
			"mira": 2, "indice_lugar": 0, "salida_mapa": GameState.INICIO_SALIDA_MAPA,
			"salida_x": GameState.INICIO_SALIDA_POSICION.x, "salida_y": GameState.INICIO_SALIDA_POSICION.y}
	GameState.mapa_actual = d.mapa
	GameState.posicion_jugador = Vector2(float(d.x), float(d.y))
	GameState.mira = int(d.get("mira", 2))
	GameState.indice_lugar = int(d.get("indice_lugar", 0))
	GameState.mapa_salida = str(d.get("salida_mapa", ""))
	GameState.posicion_salida = Vector2(float(d.get("salida_x", 0)), float(d.get("salida_y", 0)))


## Al último Centro Pokémon (orden de evento "ir_al_centro").
func ir_al_centro() -> void:
	_preparar_centro()
	await _con_fundido(_cargar_mapa)


func _cargar_mapa() -> void:
	var mapa: Mapa = (load(ruta_mapa(GameState.mapa_actual)) as PackedScene).instantiate()
	var jugador: Jugador = (load(ESCENA_JUGADOR) as PackedScene).instantiate()
	if GameState.posicion_jugador == CENTRO:
		GameState.posicion_jugador = Vector2(mapa.tamano) / 2.0
	jugador.position = GameState.posicion_jugador
	jugador.mira = GameState.mira
	GameState.mapa_actual = mapa.nombre_original
	GameState.fuerza_activa = false
	Vuelo.marcar(mapa.nombre_original)
	AudioManager.musica_mapa(mapa.nombre_original)
	mapa.objetos().add_child(jugador)
	get_tree().change_scene_to_node(mapa)
	mapa.ready.connect(mapa_cargado.emit, CONNECT_ONE_SHOT)


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
