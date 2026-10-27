extends Node2D
## Pantalla de título del original (InicioROOM): el logo que brilla, "RELOADED" latiendo, la estrella
## que gira tras cada brillo, las líneas que cruzan el fondo y el menú de InicioControl.
## Teclas como el original (KeyActionsInicioControl): ↑/↓, Z o Enter elige, X o Esc sale, y los
## atajos Espacio (nueva), F6 (cargar), M (multijugador), F11 (opciones), F12 (versión), F2 (reiniciar).

const UI: String = "res://assets/extraido/sprites/ui/"
const RESOLUCION: Vector2i = Vector2i(320, 180)
const PASOS_POR_SEGUNDO: float = 30.0
const ESCENA_INTRO: String = "res://scenes/titulo/intro.tscn"

enum Opcion { NUEVA, CARGAR, MULTIJUGADOR, OPCIONES, SALIR }
## Texto (TextMenu) y color al estar elegida de cada opción (DrawInicioControl).
const OPCIONES: Array[Dictionary] = [
	{"texto": 1, "color": 16744448},
	{"texto": 2, "color": 52235},
	{"texto": 1612, "color": 16742844},
	{"texto": 618, "color": 49151},
	{"texto": 3, "color": 255},
]
const MENU_X: float = 160.0
const MENU_Y: float = 74.0
const MENU_SALTO: float = 18.0
## getCurrentVersion(1): lo que muestra F12.
const VERSION: String = "Pokémon Reloaded Last Beta 1.9.2.1"
## Lo que aún no existe en el port (el original lleva a otras rooms).
const AUN_NO: Dictionary[Opcion, String] = {
	Opcion.CARGAR: "Todavía no se pueden guardar ni cargar partidas en esta versión.",
	Opcion.MULTIJUGADOR: "El modo Multijugador todavía no está en esta versión.",
	Opcion.OPCIONES: "El menú de Opciones todavía no está en esta versión.",
}

var _fondo: Texture2D = load(UI + "fondos/gradiente_night.png")
var _franja: Texture2D = load(UI + "fondos/back_fer_productions.png")
var _spr_logo: SpriteOriginal = load(UI + "spr_title.tres")
var _spr_reloaded: SpriteOriginal = load(UI + "spr_title2.tres")
var _spr_estrella: SpriteOriginal = load(UI + "spr_title3.tres")
var _spr_linea: SpriteOriginal = load(UI + "spr_lineafreak.tres")
var _fuente: Font = load(TextoGM.FUENTE1)

var _acumulado: float = 0.0
var _fondo_y: float = 0.0
## obj_title: frame, si está brillando y cuánto falta para volver a brillar (alarm[0]).
var _logo: float = 0.0
var _brilla: bool = true
var _espera_brillo: int = 0
## obj_title2: frame y alfa (oscila entre 0.7 y 1.3; por encima de 1 se ve igual).
var _reloaded: float = 0.0
var _reloaded_alfa: float = 1.0
var _reloaded_sube: bool = false
## obj_title3: ángulo y pasos hasta el próximo giro (alarm[0]).
var _estrella: float = 0.0
var _espera_giro: int = 0
## obj_lineafreak: [x, y, velocidad, alfa].
var _lineas: Array[Array] = []
## InicioControl: opción elegida y si se puede mover (canshoot, alarm[0] = 10).
var _sel: Opcion = Opcion.NUEVA
var _espera_mover: int = 0
var _ocupado: bool = false


func _ready() -> void:
	get_window().content_scale_size = RESOLUCION
	AudioManager.reproducir_intro()


func _process(delta: float) -> void:
	if _ocupado:
		return
	_acumulado += delta * PASOS_POR_SEGUNDO
	while _acumulado >= 1.0:
		_acumulado -= 1.0
		_paso()
	queue_redraw()


func _paso() -> void:
	# Alarmas.
	if _espera_mover > 0:
		_espera_mover -= 1
	if _espera_brillo > 0:
		_espera_brillo -= 1
		if _espera_brillo == 0:
			_brilla = true  # PokemonTitleBrilla
	if _espera_giro > 0:
		_espera_giro -= 1
		if _espera_giro == 0:
			_estrella -= 20.0  # StarTitleGira
			if _estrella > -340.0:
				_espera_giro = 1
			else:
				_estrella = 0.0
	_reloaded_alfa += 0.025 if _reloaded_sube else -0.025  # ReloadedTitleSetAlpha
	if _reloaded_alfa > 1.3:
		_reloaded_sube = false
	if _reloaded_alfa < 0.7:
		_reloaded_sube = true
	# Step.
	_teclas_mantenidas()
	if randf() * 100.0 < 5.0:  # LineaFreakCreation: randomPorcent(5)
		_lineas.append([-400.0, 8.0 * ceilf(randf() * 20.0), 26.0 + randf() * 4.0, [0.8, 0.6, 0.4, 0.2].pick_random()])
	if not _brilla:
		_logo = 0.0
	# Movimiento y animaciones (al final del step, como GM8).
	for l: Array in _lineas:
		l[0] += l[2]
	_lineas = _lineas.filter(func(l: Array) -> bool: return l[0] <= 500.0)
	_fondo_y = fposmod(_fondo_y + 1.0, _fondo.get_height())  # GradienteNight: vspeed = 1
	_reloaded = fposmod(_reloaded + 0.1666, _spr_reloaded.frames.size())
	if _brilla:
		_logo += 0.1666
		if _logo >= _spr_logo.frames.size():
			# PokemonTitleApaga: deja de brillar 100 pasos y la estrella da una vuelta.
			_logo -= _spr_logo.frames.size()
			_brilla = false
			_espera_brillo = 100
			_espera_giro = 1


func _draw() -> void:
	var alto: float = _fondo.get_height()
	for y: float in [_fondo_y - alto, _fondo_y]:
		draw_texture_rect(_fondo, Rect2(0, y, RESOLUCION.x, alto), false)
	draw_texture(_franja, Vector2(0, 170))
	for l: Array in _lineas:
		_spr_linea.dibujar(self, 0, Vector2(l[0], l[1]), Vector2.ONE, Color(1, 1, 1, l[3]))
	_spr_reloaded.dibujar(self, int(_reloaded), Vector2(160, 60), Vector2.ONE, Color(1, 1, 1, clampf(_reloaded_alfa, 0.0, 1.0)))
	_spr_logo.dibujar(self, int(_logo), Vector2(154, 32))
	_spr_estrella.dibujar(self, 0, Vector2(248, 44), Vector2.ONE, Color.WHITE, _estrella)
	for i: int in OPCIONES.size():
		var texto: String = Textos.linea("txt_menu", OPCIONES[i].texto)
		var pos := Vector2(MENU_X, MENU_Y + MENU_SALTO * i)
		var color: Color = TextoGM.color(OPCIONES[i].color) if i == _sel else Color.WHITE
		TextoGM.dibujar(self, _fuente, pos, texto, color, true)
		if i == _sel:  # el eco tembloroso de la opción elegida
			var temblor := Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
			TextoGM.dibujar(self, _fuente, pos + temblor, texto, Color(color, 0.3), true)


## ↑/↓ mantenidas: una opción cada 10 pasos.
func _teclas_mantenidas() -> void:
	if _espera_mover > 0:
		return
	var paso: int = 0
	if Input.is_physical_key_pressed(KEY_UP):
		paso = -1
	elif Input.is_physical_key_pressed(KEY_DOWN):
		paso = 1
	if paso != 0:
		_sel = posmod(_sel + paso, OPCIONES.size()) as Opcion
		_espera_mover = 10


func _unhandled_input(evento: InputEvent) -> void:
	if _ocupado:
		return
	if evento is InputEventMouseMotion:
		# MouseActionsInicioControl: el ratón sobre una opción la elige (el original pone el
		# rectángulo en x 62-178, corrido a la izquierda del texto; aquí está centrado en él).
		var p: Vector2 = get_local_mouse_position()
		for i: int in OPCIONES.size():
			if Rect2(MENU_X - 58, MENU_Y + 1 + MENU_SALTO * i, 116, 13).has_point(p):
				_sel = i as Opcion
		return
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_elegir(_sel)  # mouse_50 → KeyPressEnter: un clic es como Enter
		return
	if not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	var tecla: Key = evento.physical_keycode
	var accion: Variant = {
		KEY_Z: _sel, KEY_ENTER: _sel, KEY_KP_ENTER: _sel,
		KEY_X: Opcion.SALIR, KEY_ESCAPE: Opcion.SALIR,
		KEY_SPACE: Opcion.NUEVA, KEY_F6: Opcion.CARGAR, KEY_M: Opcion.MULTIJUGADOR, KEY_F11: Opcion.OPCIONES,
	}.get(tecla)
	if accion != null:
		get_viewport().set_input_as_handled()
		_elegir(accion)
	elif tecla == KEY_F12:
		get_viewport().set_input_as_handled()
		_mensaje(VERSION)
	elif tecla == KEY_F2:
		get_viewport().set_input_as_handled()
		_reiniciar()


func _elegir(opcion: Opcion) -> void:
	match opcion:
		Opcion.NUEVA:
			if await _preguntar(Textos.linea("txt_menu", 58)):
				_nueva_partida()
		Opcion.SALIR:
			if await _preguntar(Textos.linea("txt_menu", 7), true):
				AudioManager.detener_musica()
				get_tree().quit()
		_:
			await _mensaje(AUN_NO[opcion])


## Mientras hay un cuadro abierto, el título no responde (el original se queda dentro del cuadro).
func _preguntar(texto: String, importante: bool = false) -> bool:
	_ocupado = true
	var si: bool = await CuadroOriginal.preguntar(self, texto, importante)
	_ocupado = false
	return si


func _mensaje(texto: String) -> void:
	_ocupado = true
	await CuadroOriginal.mensaje(self, texto)
	_ocupado = false


func _nueva_partida() -> void:
	_ocupado = true
	AudioManager.detener_musica()
	GameState.nueva_partida()
	SceneManager.ir_a_mapa(GameState.mapa_actual, GameState.posicion_jugador, GameState.mira)


## ReiniciarJuego: vuelve a la intro (con su música, que se elige de nuevo).
func _reiniciar() -> void:
	if await _preguntar(Textos.linea("txt_menu", 8), true):
		AudioManager.detener_musica()
		get_tree().change_scene_to_file(ESCENA_INTRO)
