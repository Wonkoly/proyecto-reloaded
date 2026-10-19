class_name BattleManager
extends Node
## Lleva el estado de la batalla: detecta al debilitado, la termina y vuelve al menú de pruebas.

signal batalla_terminada(ganador: BattlePokemon)

const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"
const ESPERA_FIN: float = 3.0

var terminada: bool = false
var _pokemon: Array[BattlePokemon] = []


func iniciar(jugador: BattlePokemon, rival: BattlePokemon) -> void:
	_pokemon = [jugador, rival]
	for bp: BattlePokemon in _pokemon:
		bp.debilitado.connect(_on_debilitado.bind(bp))


func _on_debilitado(caido: BattlePokemon) -> void:
	if terminada:
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
	if GameState.salvaje != null:
		SceneManager.volver_de_batalla()
	else:
		get_tree().change_scene_to_file(MENU_PRUEBAS)
