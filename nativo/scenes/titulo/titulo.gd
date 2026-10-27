extends Control
## Menú de título (rediseño): logo animado del original, menú a la izquierda y, a la derecha, el
## perfil local (el nombre del jugador; será la cuenta del multijugador) y la última partida.
## Teclado: ↑/↓ y Enter (o Z), Esc sale; F12 muestra la versión y F2 reinicia (como el original).

const RESOLUCION: Vector2i = Vector2i(640, 360)
const ESCENA_INTRO: String = "res://scenes/titulo/intro.tscn"
const ESCENA_CARGAR: String = "res://scenes/titulo/cargar_partida.tscn"
const VERSION: String = "Pokémon Reloaded Last Beta 1.9.2.2 · port nativo"

var _ocupado: bool = false


func _ready() -> void:
	# Los menús se dibujan nítidos (no pixelados como el juego) a 640×360.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = RESOLUCION
	GameState.en_partida = false
	AudioManager.reproducir_intro()
	%Continuar.pressed.connect(_continuar)
	%Nueva.pressed.connect(_nueva_partida)
	%Cargar.pressed.connect(_cargar)
	%Multijugador.pressed.connect(_multijugador)
	%Opciones.pressed.connect(_opciones)
	%Salir.pressed.connect(_salir)
	%CambiarNombre.pressed.connect(_cambiar_nombre)
	%Avatar.draw.connect(_dibujar_avatar)
	for b: Button in %Menu.get_children():
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(AudioManager.efecto_ui.bind("snd_click"))
	%Version.text = "Last Beta 1.9.2.2 · F12 versión"
	_actualizar()
	(%Continuar if %Continuar.visible else %Nueva).grab_focus.call_deferred()
	if SaveManager.nombre_perfil() == "":
		_pedir_nombre_inicial.call_deferred()


func _exit_tree() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT


## Perfil y tarjeta de la última partida.
func _actualizar() -> void:
	var nombre: String = SaveManager.nombre_perfil()
	%NombrePerfil.text = nombre if nombre != "" else "Sin nombre"
	%Avatar.queue_redraw()
	var slot: int = SaveManager.mas_reciente()
	%Continuar.visible = slot > 0
	%Ultima.visible = slot > 0
	if slot > 0:
		var r: Dictionary = SaveManager.resumen(slot)
		%LugarUltima.text = InfoPartida.nombre_mapa(str(r.get("mapa", "")))
		%DetalleUltima.text = "%s · Slot %d · %s" % [str(r.get("nombre", "")), slot, InfoPartida.tiempo(int(r.get("tiempo", 0)))]
		%EquipoUltima.text = InfoPartida.equipo(r.get("equipo", []))


func _dibujar_avatar() -> void:
	var a: Control = %Avatar
	var c: Vector2 = a.size / 2.0
	a.draw_circle(c, c.x, Color(0.486, 0.361, 1.0))
	a.draw_arc(c, c.x - 1.0, 0.0, TAU, 32, Color(1, 0.796, 0.02), 1.5, true)
	var inicial: String = SaveManager.nombre_perfil().left(1).to_upper()
	var fuente: Font = a.get_theme_default_font()
	var tam: int = 18
	var ancho: float = fuente.get_string_size(inicial, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	a.draw_string(fuente, Vector2(c.x - ancho / 2.0, c.y + fuente.get_ascent(tam) / 2.0 - 2.0), inicial,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color.WHITE)


func _unhandled_input(evento: InputEvent) -> void:
	if _ocupado or not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	match evento.physical_keycode:
		KEY_ESCAPE, KEY_X:
			_salir()
		KEY_Z:
			var foco: Control = get_viewport().gui_get_focus_owner()
			if foco is Button:
				foco.pressed.emit()
		KEY_F12:
			_mensaje(VERSION)
		KEY_F2:
			_reiniciar()
		_:
			return
	get_viewport().set_input_as_handled()


func _continuar() -> void:
	if _ocupado:
		return
	await _cargar_slot(SaveManager.mas_reciente())


func _nueva_partida() -> void:
	if _ocupado:
		return
	if SaveManager.primer_libre() == 0:
		await _mensaje(Textos.linea("txt_menu", 59))
		return
	if not await _preguntar(Textos.linea("txt_menu", 58).replace("#", " ")):
		return
	_ocupado = true
	GameState.nueva_partida(SaveManager.nombre_perfil())
	await _ir_a_la_partida()


func _cargar() -> void:
	if _ocupado:
		return
	if SaveManager.ocupados().is_empty():
		await _mensaje("Todavía no hay partidas guardadas. En el juego, guarda con F5.")
		return
	get_tree().change_scene_to_file(ESCENA_CARGAR)


## Inicio de sesión del multijugador: por ahora, el perfil local con el nombre del jugador.
func _multijugador() -> void:
	if _ocupado:
		return
	_ocupado = true
	var nombre: String = await ModalMenu.pedir_texto(self, "Multijugador",
		"Inicia sesión con tu nombre de jugador. El juego en línea todavía no está disponible: por ahora el nombre queda guardado en este equipo.",
		SaveManager.nombre_perfil(), SaveManager.LARGO_NOMBRE, "Entrar")
	if nombre != "":
		SaveManager.guardar_perfil(nombre)
		_actualizar()
		await ModalMenu.mensaje(self, "Sesión iniciada como %s.\nEl modo en línea llegará en una próxima versión." % SaveManager.nombre_perfil(), "Multijugador")
	_ocupado = false
	%Multijugador.grab_focus()


func _opciones() -> void:
	await _mensaje("El menú de Opciones todavía no está en esta versión.")


func _salir() -> void:
	if await _preguntar(Textos.linea("txt_menu", 7).replace("#", "\n")):
		AudioManager.detener_musica()
		get_tree().quit()


func _reiniciar() -> void:
	if await _preguntar(Textos.linea("txt_menu", 8).replace("#", "\n")):
		AudioManager.detener_musica()
		get_tree().change_scene_to_file(ESCENA_INTRO)


func _cambiar_nombre() -> void:
	if _ocupado:
		return
	_ocupado = true
	var nombre: String = await ModalMenu.pedir_texto(self, "Perfil", "¿Cómo te llamas?",
		SaveManager.nombre_perfil(), SaveManager.LARGO_NOMBRE)
	if nombre != "":
		SaveManager.guardar_perfil(nombre)
		_actualizar()
	_ocupado = false
	%CambiarNombre.grab_focus()


## La primera vez que se abre el juego: el nombre es obligatorio (lo usan las partidas nuevas).
func _pedir_nombre_inicial() -> void:
	_ocupado = true
	var nombre: String = ""
	while SaveManager.limpiar_nombre(nombre) == "":
		nombre = await ModalMenu.pedir_texto(self, "Bienvenido",
			"¿Cómo te llamas? Será tu nombre en las partidas nuevas y en el multijugador.", "",
			SaveManager.LARGO_NOMBRE, "Continuar", false)
	SaveManager.guardar_perfil(nombre)
	_actualizar()
	_ocupado = false
	(%Continuar if %Continuar.visible else %Nueva).grab_focus()


func _cargar_slot(slot: int) -> void:
	_ocupado = true
	var r := SaveManager.cargar(slot)
	if not r.ok:
		await ModalMenu.mensaje(self, r.error)
		_ocupado = false
		_actualizar()
		return
	if r.de_respaldo:
		await ModalMenu.mensaje(self, "La partida estaba dañada: se cargó su copia de respaldo.")
	await _ir_a_la_partida()


## Al mapa de GameState (el de la partida nueva o cargada).
func _ir_a_la_partida() -> void:
	if not SceneManager.existe_mapa(GameState.mapa_actual):
		await ModalMenu.mensaje(self, "El mapa %s no está extraído (tools/extraer.py --mapas todos)." % GameState.mapa_actual)
		_ocupado = false
		return
	AudioManager.detener_musica()
	SceneManager.ir_a_mapa(GameState.mapa_actual, GameState.posicion_jugador, GameState.mira)


func _preguntar(texto: String) -> bool:
	_ocupado = true
	var foco: Control = get_viewport().gui_get_focus_owner()
	var si: bool = await ModalMenu.preguntar(self, texto)
	_ocupado = false
	if foco and is_instance_valid(foco):
		foco.grab_focus()
	return si


func _mensaje(texto: String) -> void:
	_ocupado = true
	var foco: Control = get_viewport().gui_get_focus_owner()
	await ModalMenu.mensaje(self, texto)
	_ocupado = false
	if foco and is_instance_valid(foco):
		foco.grab_focus()
