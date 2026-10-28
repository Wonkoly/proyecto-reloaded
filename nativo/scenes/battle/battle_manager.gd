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
var _gano: bool = false
var _saliendo: bool = false
var _pokemon: Array[BattlePokemon] = []
var _equipos: Array = [[], []]
var _inicio: Array[Vector2] = []


func iniciar(jugador: BattlePokemon, rival: BattlePokemon, equipo_jugador: Array = [], equipo_rival: Array = []) -> void:
	_pokemon = [jugador, rival]
	_equipos = [equipo_jugador, equipo_rival]
	_inicio = [jugador.position, rival.position]
	for bp: BattlePokemon in _pokemon:
		bp.debilitado.connect(_on_debilitado.bind(bp))


## NextPokemon: el siguiente con vida después del que cayó, dando la vuelta al equipo (el original
## solo muestra un menú para elegir con la opción cambio_custom, que está apagada por defecto).
func _siguiente(lado: int) -> PokemonInstance:
	var equipo: Array = _equipos[lado]
	var actual: int = equipo.find(_pokemon[lado].pokemon)
	for k: int in range(1, equipo.size() + 1):
		var p: PokemonInstance = equipo[(actual + k) % equipo.size()]
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
	_gano = ganador == _pokemon[0]
	batalla_terminada.emit(ganador)
	await get_tree().create_timer(ESPERA_FIN).timeout
	_salir()


## Cobra (o paga) y vuelve, una sola vez (al pasar el tiempo o con Enter).
func _salir() -> void:
	if _saliendo:
		return
	_saliendo = true
	await _dinero(_gano)
	_volver()


## NextPokemon: contra un entrenador se gana la suma de los niveles de su equipo × 16 (× 32 los
## líderes; tope 20000, TextMenu 232). Sin Pokémon: "Ya no te quedan más Pokémon..." y, contra un
## entrenador, se pierde la mitad del dinero (TextMenu 230).
func _dinero(gano: bool) -> void:
	if not is_inside_tree() or (GameState.combate_entrenador == 0 and GameState.salvaje == null):
		return
	if gano and GameState.combate_entrenador != 0:
		var t: EntrenadorData = Datos.entrenador(GameState.combate_entrenador)
		var premio: int = 0
		for p: PokemonInstance in _equipos[1]:
			premio += p.nivel * (32 if t and t.lider else 16)
		premio = mini(premio, 20000)
		if premio > 0:
			GameState.dinero += premio
			await CuadroOriginal.mensaje(self, Textos.par(Textos.linea("txt_menu", 232), str(premio)))
	elif not gano and GameState.pokemon_para_combatir() == null:
		await CuadroOriginal.mensaje(self, Textos.batalla(148))
		if GameState.combate_entrenador != 0:  # global.battle = 1
			GameState.dinero = GameState.dinero / 2
			await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 230))


func _unhandled_input(event: InputEvent) -> void:
	if terminada and event.is_action_pressed("ui_accept"):
		_salir()


func _volver() -> void:
	if not is_inside_tree():
		return
	if GameState.combate_entrenador != 0:
		SceneManager.volver_de_combate(_pokemon[0].pokemon.hp_actual > 0)
	elif GameState.salvaje != null:
		SceneManager.volver_de_batalla()
	else:
		get_tree().change_scene_to_file(MENU_PRUEBAS)
