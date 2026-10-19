extends Node2D
## Arena de batalla de pruebas: el BattleROOM del original (576×324, zona jugable 416×240).

const ESCENA_POKEMON: PackedScene = preload("res://scenes/battle/battle_pokemon.tscn")
const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"

@onready var pokemons: Node2D = $Pokemon
var _numeros: Dictionary[BattlePokemon, Variant] = {}


func _ready() -> void:
	var jugador: BattlePokemon = _crear_pokemon("Jugador", ConfigPruebas.especie_jugador,
		ConfigPruebas.nivel_jugador, 1, $PosicionJugador.position)
	var rival: BattlePokemon = _crear_pokemon("Rival", ConfigPruebas.especie_rival,
		ConfigPruebas.nivel_rival, 2, $PosicionRival.position)
	if jugador == null or rival == null:
		return
	jugador.add_child(PlayerController.new())
	var ia := AIController.new()
	ia.entrenador = ConfigPruebas.rival_entrenador
	ia.crack = ConfigPruebas.rival_crack
	ia.maestro = ConfigPruebas.rival_maestro
	rival.add_child(ia)
	jugador.objetivo = rival
	rival.objetivo = jugador
	var manager: BattleManager = $BattleManager
	var hud: BattleHud = $BattleHud
	hud.conectar(jugador, rival, ConfigPruebas.rival_entrenador)
	manager.batalla_terminada.connect(
		func(ganador: BattlePokemon) -> void: hud.mostrar_resultado("¡Gana %s!" % ganador.pokemon.especie.nombre))
	manager.iniciar(jugador, rival)
	for bp: BattlePokemon in [jugador, rival]:
		bp.golpeado.connect(_mostrar_danio.bind(bp))


func _crear_pokemon(nombre: String, id_especie: int, nivel: int, lado: int, posicion: Vector2) -> BattlePokemon:
	var especie: PokemonData = Datos.especie(id_especie)
	if especie == null:
		return null
	var bp: BattlePokemon = ESCENA_POKEMON.instantiate()
	bp.name = nombre
	bp.lado = lado
	bp.position = posicion
	bp.configurar(PokemonInstance.crear(especie, nivel))
	pokemons.add_child(bp)
	return bp


## CreateNumberEffect: el daño flota sobre el Pokémon; si ya hay un número visible, se suma.
func _mostrar_danio(_move: MoveData, danio: int, _eficacia: float, bp: BattlePokemon) -> void:
	if danio <= 0:
		return
	var actual: Variant = _numeros.get(bp)
	if is_instance_valid(actual):
		(actual as NumeroDanio).numero -= danio
		return
	var n := NumeroDanio.new()
	n.objetivo = bp
	n.numero = -danio
	$EfectosArriba.add_child(n)
	_numeros[bp] = n


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_PRUEBAS)
