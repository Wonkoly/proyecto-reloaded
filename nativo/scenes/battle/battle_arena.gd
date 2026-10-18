extends Node2D
## Arena de batalla de pruebas: el BattleROOM del original (576×324, zona jugable 416×240).

const ESCENA_POKEMON: PackedScene = preload("res://scenes/battle/battle_pokemon.tscn")
const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"

@export var especie_jugador: int = 4
@export var nivel_jugador: int = 50

@onready var pokemons: Node2D = $Pokemon


func _ready() -> void:
	var especie: PokemonData = Datos.especie(especie_jugador)
	if especie == null:
		return
	var jugador: BattlePokemon = ESCENA_POKEMON.instantiate()
	jugador.name = "Jugador"
	jugador.position = $PosicionJugador.position
	jugador.configurar(PokemonInstance.crear(especie, nivel_jugador))
	jugador.add_child(PlayerController.new())
	pokemons.add_child(jugador)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MENU_PRUEBAS)
