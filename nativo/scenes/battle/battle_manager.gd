class_name BattleManager
extends Node
## Lleva el estado de la batalla: cuando un Pokémon cae entra el siguiente de su equipo (el del jugador
## en orden, sin menú todavía); sin nadie más, la termina y vuelve al mapa (o al menú de pruebas).

signal batalla_terminada(ganador: BattlePokemon)
## Entró otro Pokémon de un equipo (para refrescar el HUD).
signal cambio_pokemon(bp: BattlePokemon)

const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"
const ESPERA_FIN: float = 3.0

## Pausa antes de que entre el siguiente Pokémon.
const ESPERA_CAMBIO: float = 1.0

var terminada: bool = false
var _pokemon: Array[BattlePokemon] = []
var _equipos: Array = [[], []]
var _inicio: Array[Vector2] = []


func iniciar(jugador: BattlePokemon, rival: BattlePokemon, equipo_jugador: Array = [], equipo_rival: Array = []) -> void:
	_pokemon = [jugador, rival]
	_equipos = [equipo_jugador, equipo_rival]
	_inicio = [jugador.position, rival.position]
	for bp: BattlePokemon in _pokemon:
		bp.debilitado.connect(_on_debilitado.bind(bp))


func _siguiente(lado: int) -> PokemonInstance:
	for p: PokemonInstance in _equipos[lado]:
		if p.hp_actual > 0 and p != _pokemon[lado].pokemon:
			return p
	return null


func _on_debilitado(caido: BattlePokemon) -> void:
	if terminada:
		return
	var lado: int = _pokemon.find(caido)
	var otro: PokemonInstance = _siguiente(lado)
	if otro:
		await get_tree().create_timer(ESPERA_CAMBIO).timeout
		if terminada:
			return
		caido.position = _inicio[lado]
		caido.configurar(otro)
		cambio_pokemon.emit(caido)
		return
	terminada = true
	var ganador: BattlePokemon = _pokemon[1] if caido == _pokemon[0] else _pokemon[0]
	# Congela la batalla: sin controladores no hay más movimientos ni ataques.
	for bp: BattlePokemon in _pokemon:
		for hijo: Node in bp.get_children():
			if hijo is BattleController:
				hijo.queue_free()
		bp.set_direccion(Vector2.ZERO)
	batalla_terminada.emit(ganador)
	await get_tree().create_timer(ESPERA_FIN).timeout
	_volver()


func _unhandled_input(event: InputEvent) -> void:
	if terminada and event.is_action_pressed("ui_accept"):
		_volver()


func _volver() -> void:
	if not is_inside_tree():
		return
	if GameState.combate_entrenador != 0:
		SceneManager.volver_de_combate(_pokemon[0].pokemon.hp_actual > 0)
	elif GameState.salvaje != null:
		SceneManager.volver_de_batalla()
	else:
		get_tree().change_scene_to_file(MENU_PRUEBAS)
