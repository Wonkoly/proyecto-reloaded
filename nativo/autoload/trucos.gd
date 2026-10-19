extends Node
## Los códigos del original (ExecuteCheat): con F3 se abre "Introduce un Cheat..." (13 letras como
## máximo, se comparan en mayúsculas). En builds de depuración F3 es el overlay de la consola dev y
## los códigos se abren con Shift+F3 o con el comando "codigo <texto>".

const LARGO_MAXIMO: int = 13
## Cama de la casa del protagonista, a donde va si desfallece sin haber visitado un Centro
## (GoCentroPokemon con global.lastcenter = -100: Home_2, homeDescansoX/Y).
const CASA: String = "Home_2"
const CAMA: Vector2 = Vector2(88, 94)
const VERSION: String = "Pokémon Reloaded Last Beta 1.9.2.1"
const CONSEJOS: Array[String] = ["MIERDA", "JODER", "VIOLENCIA", "DIOS", "PAZ", "JUSTICIA", "VERDAD", "FUCK", "GOD", "PEACE"]
const INFO: Array[String] = ["ABOUT", "VERSION", "HELP", "INFO", "AYUDA", "INFORMACION", "INFORMACIÓN", "BETA"]
## Último número de Pokémon que recorre GUARDERIA cuando se deja un padre vacío.
const ULTIMO_POKEMON: int = 1034

var _dialogo: DialogoModal
var _abierto: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dialogo = (load("res://scenes/ui/dialogo_modal.tscn") as PackedScene).instantiate()
	add_child(_dialogo)


func _unhandled_input(evento: InputEvent) -> void:
	var tecla: InputEventKey = evento as InputEventKey
	if tecla and tecla.pressed and not tecla.echo and tecla.physical_keycode == KEY_F3:
		# Con la consola dev, F3 es su overlay: los códigos van con Shift+F3.
		if tecla.shift_pressed or not has_node("/root/DevConsole"):
			get_viewport().set_input_as_handled()
			abrir_pantalla()


## La pantalla de códigos del original (GetDialogString(TextMenu(9), "", 0, 13)).
func abrir_pantalla() -> void:
	if _abierto or SceneManager.en_transicion:
		return
	_abierto = true
	var texto: String = await _dialogo.pedir_texto(Textos.linea("txt_menu", 9), LARGO_MAXIMO)
	_abierto = false
	await ejecutar(texto)


## Aplica un código. Devuelve un resumen para la consola dev.
func ejecutar(texto: String) -> String:
	var c: String = texto.to_upper().strip_edges()
	if c == "":
		return ""
	var en_batalla: bool = get_tree().current_scene is Node2D and get_tree().current_scene.has_node("BattleManager")
	var en_mapa: bool = get_tree().current_scene is Mapa
	match c:
		"GUARDERIA", "GUARDERÍA":
			await _guarderia()
		"TORBELLINOS":
			await _lista_pendientes(1184, "estorbo_torbellino_%d", 200)
		"ENTRENADORES":
			await _lista_pendientes(1185, "trainer_%d", 1050)
		"ME RINDO":
			if en_batalla and await _dialogo.preguntar(_menu(1186)):
				_desfallecer()
		"INCONSCIENTE":
			if en_mapa and await _dialogo.preguntar(_menu(1187)):
				_desfallecer()
		"CHEATS":
			await _dialogo.mensaje(Textos.par(_menu(1193), str(GameState.trucos_usados)))
		"MOTE", "APODO":
			if en_mapa:
				var apodo: String = await _dialogo.pedir_texto(Textos.linea("txt_dialog", 1), 12)
				if apodo != "":
					GameState.apodo_jugador = apodo
					_recargar_mapa()
		"Q", "CARA":
			if en_mapa:
				await _cambiar_personaje()
		"LOGBATTLE", "BATTLELOG":
			GameState.guardar_log_batalla = not GameState.guardar_log_batalla
			await _dialogo.mensaje("Battle Log Enabled" if GameState.guardar_log_batalla else "Battle Log Disabled")
		"PRISA":
			GameState.velocidad_texto = 2
		"TRANSITION":
			GameState.transicion_especial = not GameState.transicion_especial
			await _dialogo.mensaje("Special Transition Enabled" if GameState.transicion_especial else "Special Transition Disabled")
		"CLEANBATTLE":
			if en_batalla:
				var hud: CanvasLayer = get_tree().current_scene.get_node("BattleHud")
				hud.visible = not hud.visible
		"LLAMAME", "LLÁMAME", "QQ", "VESTUARIO", "GIGAMAX", "GIGAMAX1", "GIGAMAX2", "GUARDIAN", "SHINY":
			return "%s: depende de algo que todavía no existe en nativo (teléfono, vestuario, gigamax...)" % c
		_:
			if c == "SELUE" + str(99999 - GameState.prota_id):
				# Antitrampas del original: cuenta Pokémon con la suma de control alterada. Nativo no la guarda.
				await _dialogo.mensaje(Textos.par(_menu(1192), "0"))
			elif c in INFO:
				await _dialogo.mensaje(VERSION)
			elif c in CONSEJOS:
				for n: int in range(1197, 1208):
					if await _dialogo.mensaje(_menu(n)):
						break
			else:
				return "\"%s\" no es un código del original" % c
	return "código %s aplicado" % c


func _menu(n: int) -> String:
	return Textos.linea("txt_menu", n)


## GUARDERIA: dice qué huevo darían un macho y una hembra; si se deja uno vacío, prueba con todos.
func _guarderia() -> void:
	var macho: int = await _dialogo.pedir_numero(_menu(1181), 1, 4000)
	var hembra: int = await _dialogo.pedir_numero(_menu(1182), 1, 4000)
	if macho == -1 and hembra == -1:
		return
	var nombre: Callable = func(id: int) -> String:
		var e: PokemonData = Datos.especie(id) if id > 0 else null
		return e.nombre if e else "-"
	var pares: Array[Vector2i] = []
	if macho == -1:
		for i: int in range(1, ULTIMO_POKEMON + 1):
			pares.append(Vector2i(i, hembra))
	elif hembra == -1:
		for j: int in range(1, ULTIMO_POKEMON + 1):
			pares.append(Vector2i(macho, j))
	else:
		pares.append(Vector2i(macho, hembra))
	for par: Vector2i in pares:
		var huevo: int = -Cria.huevo(par.x, par.y)
		var texto: String = Textos.par(_menu(1179), nombre.call(par.x), nombre.call(par.y)) \
			+ Textos.par(_menu(1180), nombre.call(huevo))
		if await _dialogo.mensaje(texto):
			return


## TORBELLINOS / ENTRENADORES: los que siguen sin hacer según las banderas de la historia.
func _lista_pendientes(titulo: int, bandera: String, cantidad: int) -> void:
	var texto: String = _menu(titulo)
	for i: int in range(1, cantidad + 1):
		if GameState.bandera(bandera % i) == 0:
			texto += str(i) + " "
	await _dialogo.mensaje(texto)


## ME RINDO / INCONSCIENTE (AjustesDerrota + GoCentroPokemon): a casa, curado y sin dinero.
func _desfallecer() -> void:
	for p: PokemonInstance in GameState.equipo:
		p.hp_actual = p.calcular_stats()["hp"]
		p.energia_actual = p.calcular_energia_maxima()
	GameState.dinero = 0
	GameState.historia["ev_1429"] = GameState.bandera("ev_1429") + 1
	GameState.trucos_usados += 1
	GameState.salvaje = null
	SceneManager.ir_a_mapa(CASA, CAMA, 2)


## Q / CARA: personaje 0-9, o 10 = el sprite de un entrenador (1-351).
func _cambiar_personaje() -> void:
	var n: int = await _dialogo.pedir_numero(_menu(1194), 0, 10)
	if n == -1:
		return
	var entrenador: int = 1
	if n == 10:
		entrenador = await _dialogo.pedir_numero(Textos.par(_menu(1195), "351"), 0, 351)
		if entrenador == -1:
			return
	GameState.personaje = n
	GameState.personaje_entrenador = entrenador
	GameState.trucos_usados += 1
	_recargar_mapa()


## RoomRestart: el mismo mapa en la misma posición.
func _recargar_mapa() -> void:
	var j: Jugador = get_tree().current_scene.get_node_or_null("Objetos/Jugador") as Jugador
	if j:
		SceneManager.ir_a_mapa(GameState.mapa_actual, j.global_position, j.mira)
