extends Node2D
## Arena de batalla: el BattleROOM del original (576×324, zona jugable 416×240). Si viene del
## overworld (GameState.salvaje), pelea el equipo contra el salvaje y al final vuelve al mapa; si no,
## usa lo elegido en el menú de pruebas.

const ESCENA_POKEMON: PackedScene = preload("res://scenes/battle/battle_pokemon.tscn")
const MENU_PRUEBAS: String = "res://scenes/debug/menu_pruebas.tscn"
## La batalla del original se ve en 576×324 (BattleROOM).
const RESOLUCION: Vector2i = Vector2i(576, 324)

@onready var pokemons: Node2D = $Pokemon
var _numeros: Dictionary[BattlePokemon, Variant] = {}


func _ready() -> void:
	get_window().content_scale_size = RESOLUCION
	var desde_overworld: bool = GameState.salvaje != null or GameState.combate_entrenador != 0
	var p_jugador: PokemonInstance
	var p_rival: PokemonInstance
	var equipo_rival: Array[PokemonInstance] = []
	var entrenador: EntrenadorData = Datos.entrenador(GameState.combate_entrenador) if GameState.combate_entrenador != 0 else null
	if entrenador:
		equipo_rival = entrenador.crear_equipo()
		# Dobles y triples: los equipos de los compañeros, intercalados (como pkmn2 en el original).
		var equipos: Array = [equipo_rival]
		for n: int in GameState.combate_companeros:
			var otro: EntrenadorData = Datos.entrenador(n)
			if otro:
				equipos.append(otro.crear_equipo())
		if equipos.size() > 1:
			equipo_rival = []
			for i: int in 6:
				for eq: Array in equipos:
					if i < eq.size():
						equipo_rival.append(eq[i])
		p_jugador = GameState.pokemon_para_combatir()
		p_rival = equipo_rival[0] if not equipo_rival.is_empty() else null
	elif desde_overworld:
		p_jugador = GameState.pokemon_para_combatir()
		p_rival = GameState.salvaje
	else:
		p_jugador = _pokemon_de_prueba(ConfigPruebas.especie_jugador, ConfigPruebas.nivel_jugador)
		p_rival = _pokemon_de_prueba(ConfigPruebas.especie_rival, ConfigPruebas.nivel_rival)
	if p_jugador == null or p_rival == null:
		if entrenador:  # sin equipo extraído (entrenadores especiales): cuenta como ganado
			push_warning("El entrenador %d no tiene equipo" % GameState.combate_entrenador)
			SceneManager.volver_de_combate(true)
		return
	if desde_overworld:
		GameState.marcar_pokedex(p_rival.especie, 1)  # Pokemon2SeePokedex
	var jugador: BattlePokemon = _crear_pokemon("Jugador", p_jugador, 1, $PosicionJugador.position)
	var rival: BattlePokemon = _crear_pokemon("Rival", p_rival, 2, $PosicionRival.position)
	jugador.add_child(PlayerController.new())
	var ia := AIController.new()
	ia.entrenador = entrenador != null or (ConfigPruebas.rival_entrenador and not desde_overworld)
	ia.crack = ConfigPruebas.rival_crack and not desde_overworld
	ia.maestro = ConfigPruebas.rival_maestro and not desde_overworld
	rival.add_child(ia)
	jugador.objetivo = rival
	rival.objetivo = jugador
	var manager: BattleManager = $BattleManager
	var hud: BattleHud = $BattleHud
	hud.conectar(jugador, rival, ia.entrenador)
	manager.batalla_terminada.connect(
		func(ganador: BattlePokemon) -> void: hud.mostrar_resultado("¡Gana %s!" % ganador.pokemon.especie.nombre))
	manager.cambio_pokemon.connect(hud.cambiar_pokemon)
	manager.mensaje_panel.connect(hud.mensaje)
	manager.iniciar(jugador, rival, GameState.equipo if desde_overworld else [], equipo_rival)
	for bp: BattlePokemon in [jugador, rival]:
		bp.golpeado.connect(_mostrar_danio.bind(bp))


func _pokemon_de_prueba(id_especie: int, nivel: int) -> PokemonInstance:
	var especie: PokemonData = Datos.especie(id_especie)
	return PokemonInstance.crear(especie, nivel) if especie else null


func _crear_pokemon(nombre: String, p: PokemonInstance, lado: int, posicion: Vector2) -> BattlePokemon:
	var bp: BattlePokemon = ESCENA_POKEMON.instantiate()
	bp.name = nombre
	bp.lado = lado
	bp.position = posicion
	bp.configurar(p)
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
		get_viewport().set_input_as_handled()
		($BattleManager as BattleManager).huir()
