extends Node2D
## Arena de batalla de pruebas: el BattleROOM del original (576×324, zona jugable 416×240).

const ESCENA_POKEMON: PackedScene = preload("res://scenes/battle/battle_pokemon.tscn")
const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"

@export var especie_jugador: int = 4
@export var nivel_jugador: int = 50
@export var especie_rival: int = 1
@export var nivel_rival: int = 50

@onready var pokemons: Node2D = $Pokemon


func _ready() -> void:
	var jugador: BattlePokemon = _crear_pokemon("Jugador", especie_jugador, nivel_jugador, 1, $PosicionJugador.position)
	var rival: BattlePokemon = _crear_pokemon("Rival", especie_rival, nivel_rival, 2, $PosicionRival.position)
	if jugador == null or rival == null:
		return
	jugador.add_child(PlayerController.new())
	jugador.objetivo = rival
	rival.objetivo = jugador


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_PRUEBAS)
