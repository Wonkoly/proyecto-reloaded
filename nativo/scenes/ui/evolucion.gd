class_name Evolucion
extends CanvasLayer
## La evolución del original (objeto EVOLUTION en la room 12, fondo BackEvolution): el Pokémon
## parpadea entre su forma y la nueva y se puede cancelar con X. Se usa con await:
##   await Evolucion.revisar_equipo(self, subidos)

const FONDO: String = "res://assets/extraido/sprites/tilesets/back_evolution.png"
## Segundos de parpadeo antes de completar (EvolutionBrillo: alarm 200 steps).
const DURACION: float = 200.0 / 30.0

signal _terminada(evoluciono: bool)

var _p: PokemonInstance
var _nueva: PokemonData
var _sprite_viejo: AnimatedSprite2D
var _sprite_nuevo: AnimatedSprite2D
var _tiempo: float = 0.0
var _cancelada: bool = false
var _preguntando: bool = false
var _texto: Label
## EvolutionKeyActions: con objeto (evolMode 2-21) no se puede cancelar.
var _cancelable: bool = true


## CompEvolucion: evoluciona, uno tras otro, a los Pokémon del equipo que subieron de nivel y cumplen
## la condición.
static func revisar_equipo(desde: Node, subidos: Array[PokemonInstance]) -> void:
	for p: PokemonInstance in subidos:
		var nueva: PokemonData = p.evolucion_pendiente()
		if nueva:
			var objeto_necesario: bool = p.regla_evolucion().has("objeto")
			if await evolucionar(desde, p, nueva) and objeto_necesario:
				p.objeto = 0  # LostItemEvolution: se usa el objeto equipado


static func evolucionar(desde: Node, p: PokemonInstance, nueva: PokemonData, cancelable: bool = true) -> bool:
	var e := Evolucion.new()
	e._p = p
	e._nueva = nueva
	e._cancelable = cancelable
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(e)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	var evoluciono: bool = await e._terminada
	if evoluciono:
		await e._aprendizaje()
	arbol.paused = pausa_previa
	e.queue_free()
	return evoluciono


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	var tam: Vector2 = get_viewport().get_visible_rect().size
	var fondo := TextureRect.new()
	fondo.texture = load(FONDO) if ResourceLoader.exists(FONDO) else null
	fondo.stretch_mode = TextureRect.STRETCH_SCALE
	fondo.size = tam
	add_child(fondo)
	_sprite_viejo = _crear_sprite(_p.especie, tam)
	_sprite_nuevo = _crear_sprite(_nueva, tam)
	_sprite_nuevo.modulate = Color(1, 1, 1, 0)
	_texto = Label.new()
	_texto.text = Textos.par(Textos.linea("txt_dialog", 6885), Progreso.nombre(_p))
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto.position = Vector2(0, tam.y * 0.78)
	_texto.size = Vector2(tam.x, 24)
	_texto.add_theme_color_override("font_outline_color", Color.BLACK)
	_texto.add_theme_constant_override("outline_size", 4)
	add_child(_texto)


func _crear_sprite(especie: PokemonData, tam: Vector2) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = especie.cargar_sprite_frames()
	if s.sprite_frames and s.sprite_frames.has_animation("mover_2"):
		s.play("mover_2")
	s.position = tam / 2.0
	s.scale = Vector2(3, 3)
	add_child(s)
	return s


func _process(delta: float) -> void:
	if _cancelada or _preguntando:
		return
	_tiempo += delta
	# Parpadeo cada vez más rápido entre la forma vieja y la nueva (EvolutionLuz*).
	var t: float = _tiempo / DURACION
	var visible_nueva: bool = sin(_tiempo * TAU * lerpf(1.0, 6.0, t)) > 0.0 and t > 0.15
	_sprite_viejo.modulate = Color(1, 1, 1, 0.0 if visible_nueva else 1.0) * Color(1 + t, 1 + t, 1 + t)
	_sprite_nuevo.modulate = Color(1, 1, 1, 1.0 if visible_nueva else 0.0) * Color(1 + t, 1 + t, 1 + t)
	if _tiempo >= DURACION:
		set_process(false)
		_sprite_viejo.visible = false
		_sprite_nuevo.modulate = Color.WHITE
		_p.evolucionar(_nueva)
		_texto.text = ""
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 6883).replace("#", "\n"))
		_terminada.emit(true)


## EvolutionKeyActions: X pregunta si se cancela.
func _unhandled_input(evento: InputEvent) -> void:
	if _cancelada or _preguntando or _tiempo >= DURACION or not _cancelable:
		return
	if evento is InputEventKey and evento.pressed and not evento.echo and (evento as InputEventKey).physical_keycode == KEY_X:
		get_viewport().set_input_as_handled()
		_preguntando = true
		if await CuadroOriginal.preguntar(self, Textos.linea("txt_dialog", 6887)):
			_cancelada = true
			_sprite_nuevo.visible = false
			_sprite_viejo.modulate = Color.WHITE
			await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 6888))
			_terminada.emit(false)
		_preguntando = false


## EvolutionAprendizaje: los movimientos de la nueva especie en su nivel actual.
func _aprendizaje() -> void:
	for m: MoveData in _p.movimientos_de_nivel(_p.nivel):
		await Progreso.aprender(self, _p, m)
