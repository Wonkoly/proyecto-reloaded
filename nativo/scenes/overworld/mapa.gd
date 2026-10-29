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


var _guardando: bool = false


func _ready() -> void:
	get_window().content_scale_size = RESOLUCION
	GameState.en_partida = true
	# AdjustmentsRoom: algunos mapas registran el último Centro Pokémon.
	var centro: Variant = SceneManager.centros().get("por_mapa", {}).get(nombre_original)
	if centro != null:
		GameState.ultimo_centro = int(centro)
	aplicar_historia()
	GameState.historia_cambiada.connect(aplicar_historia)


## Teclas de KeyActionsExplorer con el jugador quieto: F5 guarda (key_global_guardar), Enter abre el
## menú principal, Espacio el equipo y F12 la Pokédex.
func _unhandled_input(evento: InputEvent) -> void:
	var tecla := evento as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	if tecla.physical_keycode not in [KEY_F5, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F12]:
		return
	var jugador: Jugador = get_node_or_null("Objetos/Jugador") as Jugador
	if _guardando or SceneManager.en_transicion or Eventos.en_curso or jugador == null or not jugador.quieto():
		return
	get_viewport().set_input_as_handled()
	_guardando = true
	match tecla.physical_keycode:
		KEY_F5: await guardar_partida()
		KEY_ENTER, KEY_KP_ENTER: await MenuPrincipal.abrir(self, self)
		KEY_SPACE: await MenuEquipo.abrir(self)
		KEY_F12: await Pokedex.abrir(self)
	_guardando = false


## Pregunta y guarda la partida con la posición actual del jugador.
func guardar_partida() -> void:
	var jugador: Jugador = get_node_or_null("Objetos/Jugador") as Jugador
	if jugador == null:
		return
	if await CuadroOriginal.preguntar(self, Textos.linea("txt_menu", 39)):
		GameState.posicion_jugador = jugador.global_position
		GameState.mira = jugador.mira
		var error: String = SaveManager.guardar()
		await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 44) if error == "" else error)


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
	# Lo que un evento quitó (orden "ocultar", instance_destroy) no vuelve hasta recargar el mapa.
	if n.get_meta("oculto_por_evento", false) or (n.get_parent() and n.get_parent().get_meta("oculto_por_evento", false)):
		activo = false
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
