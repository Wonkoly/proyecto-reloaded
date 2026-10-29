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
## Desde dónde sale la Poké Ball: el entrenador del jugador (Trainer1 en t1x = 114, y = 64).
const ORIGEN_BALL: Vector2 = Vector2(114, 64)

var terminada: bool = false
var _gano: bool = false
var _saliendo: bool = false
var _pokemon: Array[BattlePokemon] = []
var _equipos: Array = [[], []]
var _inicio: Array[Vector2] = []
## Los Pokémon del jugador que subieron de nivel (global.subido): al final se revisa si evolucionan.
var _subidos: Array[PokemonInstance] = []
var _ball: BallLanzada
## Segundos de combate (fight_time, para las balls Turno y Veloz).
var _segundos: float = 0.0


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
	if lado == 1:
		await _experiencia(caido.pokemon)
		if terminada:
			return
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
	_congelar()
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
	if _gano:
		await Evolucion.revisar_equipo(self, _subidos)
	_volver()


## ExpGana: el Pokémon del jugador que está en el campo gana la experiencia del rival que cayó.
func _experiencia(rival: PokemonInstance) -> void:
	var bp: BattlePokemon = _pokemon[0]
	if _equipos[0].is_empty() or bp.esta_debilitado():
		return  # batalla de prueba o ya sin vida
	var cantidad: int = Progreso.experiencia_de(rival, GameState.combate_entrenador != 0)
	if await Progreso.dar_experiencia(self, bp.pokemon, cantidad):
		if bp.pokemon not in _subidos:
			_subidos.append(bp.pokemon)
		bp.configurar(bp.pokemon)  # stats, HP máximo y barras del nuevo nivel


## NextPokemon: contra un entrenador se gana la suma de los niveles de su equipo × 16 (× 32 los
## líderes; tope 20000, TextMenu 232). Sin Pokémon: "Ya no te quedan más Pokémon..." y, contra un
## entrenador, se pierde la mitad del dinero (TextMenu 230).
func _dinero(gano: bool) -> void:
	if not is_inside_tree() or (GameState.combate_entrenador == 0 and GameState.salvaje == null):
		return
	if gano and GameState.combate_entrenador != 0:
		var t: EntrenadorData = Datos.entrenador(GameState.combate_entrenador)
		for n: int in GameState.combate_companeros:
			var otro: EntrenadorData = Datos.entrenador(n)
			if otro and otro.lider:
				t = otro
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


func _process(delta: float) -> void:
	if not terminada:
		_segundos += delta


## Sin controladores no hay más movimientos ni ataques.
func _congelar() -> void:
	for bp: BattlePokemon in _pokemon:
		for hijo: Node in bp.get_children():
			if hijo is BattleController:
				hijo.queue_free()
		bp.set_direccion(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if terminada:
		if event.is_action_pressed("ui_accept"):
			_salir()
		return
	var tecla: InputEventKey = event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_B:  # key_bt_ball
			get_viewport().set_input_as_handled()
			_lanzar_ball()
		KEY_E:  # key_bt_escapar
			get_viewport().set_input_as_handled()
			huir()
		KEY_O:  # key_menu_mochila
			if not _equipos[0].is_empty():
				get_viewport().set_input_as_handled()
				Mochila.abrir(self)


## KeyActionsBattle, key_bt_ball: lanza la ball asignada (solo contra salvajes).
func _lanzar_ball() -> void:
	if _equipos[0].is_empty() or _pokemon.size() < 2:
		return  # batalla de prueba: no hay mochila
	if GameState.combate_entrenador != 0:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 188))
		return
	if is_instance_valid(_ball) or _pokemon[1].esta_debilitado() or _pokemon[0].esta_debilitado():
		return
	var id: int = GameState.ball_asignada
	if id < 0 or Inventario.cantidad(id) < 1:
		GameState.ball_asignada = -1
		await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 187))
		await Mochila.abrir(self, Inventario.BOLSILLOS.find("ball"))
		return
	Inventario.quitar(id)
	if Inventario.cantidad(id) == 0:
		GameState.ball_asignada = -1
	var rival: PokemonInstance = _pokemon[1].pokemon
	_ball = BallLanzada.new()
	_ball.indice = FormulasBatalla.indice_ball(id)
	_ball.objetivo = _pokemon[1]
	_ball.probabilidad = FormulasBatalla.probabilidad_captura(rival, _ball.indice, _pokemon[0].pokemon, _segundos,
		GameState.pokedex.get(rival.especie.numero_pokedex, 0) == 2)
	_ball.position = ORIGEN_BALL
	_ball.resuelta.connect(_on_ball_resuelta)
	get_parent().get_node("EfectosArriba").add_child(_ball)


func _on_ball_resuelta(capturado: bool) -> void:
	if capturado and not terminada:
		await _capturar(_pokemon[1].pokemon)


## PokeBallCapturando + CapturaPokemon: termina la batalla, da la experiencia y guarda al Pokémon.
func _capturar(p: PokemonInstance) -> void:
	terminada = true
	_saliendo = true
	_congelar()
	await _experiencia(p)
	await CuadroOriginal.mensaje(self, Textos.batalla(217))
	GameState.marcar_pokedex(p.especie, 2)
	await _guardar_capturado(p)
	await Evolucion.revisar_equipo(self, _subidos)
	_volver()


## CapturaPokemon: al primer hueco del equipo; si está lleno, al PC o se manda uno del equipo al PC.
func _guardar_capturado(p: PokemonInstance) -> void:
	if GameState.equipo.size() < 6:
		GameState.equipo.append(p)
		await CuadroOriginal.mensaje(self, Textos.par(Textos.linea("txt_menu", 244), str(GameState.equipo.size())))
		return
	await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 245))
	var enviado: PokemonInstance = p
	if not await CuadroOriginal.preguntar(self, Textos.linea("txt_menu", 1865)):
		var filas: Array = GameState.equipo.map(func(q: PokemonInstance) -> Dictionary:
			return {"texto": "%s Nv.%d" % [Progreso.nombre(q), q.nivel]})
		var i: int = await MenuLista.elegir(self, Textos.linea("txt_menu", 1866), filas)
		if i >= 0:
			enviado = GameState.equipo[i]
			GameState.equipo[i] = p
	var hueco: Array[int] = GameState.guardar_en_pc(enviado)
	if hueco.is_empty():
		await CuadroOriginal.mensaje(self, Textos.linea("txt_menu", 248))
	elif enviado == p:
		await CuadroOriginal.mensaje(self, Textos.par(Textos.linea("txt_menu", 246), GameState.nombres_cajas[hueco[0]], str(hueco[1] + 1)))
	else:
		await CuadroOriginal.mensaje(self, Textos.par(Textos.linea("txt_menu", 247), Progreso.nombre(enviado),
			GameState.nombres_cajas[hueco[0]]).replace("$par3$", str(hueco[1] + 1)))


## KeyActionsBattle, key_bt_escapar: contra salvajes pregunta y vuelve al mapa.
func huir() -> void:
	if terminada:
		return
	if GameState.combate_entrenador != 0:
		await CuadroOriginal.mensaje(self, Textos.batalla(174))
		return
	if GameState.salvaje == null:
		get_tree().change_scene_to_file(MENU_PRUEBAS)
		return
	if is_instance_valid(_ball):
		await CuadroOriginal.mensaje(self, Textos.batalla(172))
		return
	if await CuadroOriginal.preguntar(self, Textos.batalla(167)):
		await CuadroOriginal.mensaje(self, Textos.batalla(173))
		terminada = true
		_saliendo = true
		SceneManager.volver_de_batalla()


func _volver() -> void:
	if not is_inside_tree():
		return
	if GameState.combate_entrenador != 0:
		SceneManager.volver_de_combate(_pokemon[0].pokemon.hp_actual > 0)
	elif GameState.salvaje != null:
		SceneManager.volver_de_batalla()
	else:
		get_tree().change_scene_to_file(MENU_PRUEBAS)
