class_name Clima
extends CanvasLayer
## El clima (global.clima y sus objetos LLUVIA, SOLEADO, TOR_ARENA, NIEVE, GRANIZO): en el mapa solo
## se ve; en combate además cambia el daño (Ataque1GolpeaPokemon2), la velocidad de algunas
## habilidades (GetSpeedPokemonPos) y quita o da PS cada step (EfectoTormentaArena, EfectoGranizo,
## EffectHabilityStep). Los movimientos lo ponen por 500 steps (800 con su roca).

enum Tipo { NINGUNO = 0, LLUVIA = 1, SOL = 2, NIEVE = 3, ARENA = 4, DILUVIO = 5, ABRASADOR = 6, GRANIZO = 9 }

const STEP: float = 1.0 / 30.0
const UI: String = "res://assets/extraido/sprites/ui/"
## DefineLluvia... / ...Finished: los avisos al empezar y al terminar (TextBattle).
const TEXTO_EMPIEZA: Dictionary[int, int] = {1: 363, 2: 362, 3: 365, 4: 366, 9: 364}
const TEXTO_TERMINA: Dictionary[int, int] = {1: 292, 2: 293, 3: 295, 4: 294, 9: 361}
## Tipos del original que no sufren la arena (Roca, Acero, Tierra) ni el granizo (Hielo), y las
## habilidades que los protegen; Gafa Protectora (733) protege de los dos.
const INMUNES_ARENA: Array[int] = [6, 14, 8]
const HABS_ARENA: Array[int] = [8, 142, 146, 98, 159]
const HABS_GRANIZO: Array[int] = [81, 142, 98, 229]
## GetSpeedPokemonPos: ×1.25 a la velocidad con su clima (Nado Rápido, Clorofila, Ímpetu Arena).
const VELOCIDAD: Dictionary[int, Array] = {33: [1, 5], 34: [2, 6], 146: [4]}

## El clima del combate en curso (o del mapa).
static var actual: Clima

signal cambiado(tipo: int)

var tipo: int = Tipo.NINGUNO
## Steps que le quedan (-1: el del mapa, no se acaba).
var timer: int = -1
## En combate: los Pokémon que lo sufren (avisos, PS).
var pokemon: Array[BattlePokemon] = []
var en_batalla: bool = false
var _acumulado: float = 0.0
var _lienzo: Node2D
var _destello: float = 0.0
var _alfa_sol: float = 0.2
var _sube_sol: bool = true
var _gotas: Array[Dictionary] = []
var _sprites: Dictionary[String, SpriteOriginal] = {}


static func es(t: int) -> bool:
	return actual != null and is_instance_valid(actual) and actual.tipo == t


static func llueve() -> bool:
	return es(Tipo.LLUVIA) or es(Tipo.DILUVIO)


static func soleado() -> bool:
	return es(Tipo.SOL) or es(Tipo.ABRASADOR)


func _ready() -> void:
	layer = 5
	actual = self
	_lienzo = Node2D.new()
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)


func _exit_tree() -> void:
	if actual == self:
		actual = null


## Cambia el clima (un movimiento: 500 steps, 800 con la roca equipada) con su aviso.
func poner(nuevo: int, steps: int = -1, avisar: Node = null) -> void:
	if tipo != Tipo.NINGUNO and tipo != nuevo:
		_aviso(TEXTO_TERMINA.get(tipo, 0), avisar)
	tipo = nuevo
	timer = steps
	_gotas.clear()
	if nuevo in [Tipo.LLUVIA, Tipo.DILUVIO]:
		_destello = 1.0  # ZZ.image_alpha = 1
	_aviso(TEXTO_EMPIEZA.get(nuevo, 0), avisar)
	for bp: BattlePokemon in pokemon:
		if is_instance_valid(bp) and (VELOCIDAD.get(bp.habilidad, []) as Array).has(nuevo):
			bp.habilidad_actuo()  # DefineLluvia / DefineSoleado: hab_fugaz de Nado Rápido / Clorofila
		if is_instance_valid(bp):
			bp.velocidad = bp._velocidad_actual()
	cambiado.emit(tipo)


func _aviso(texto: int, avisar: Node) -> void:
	if texto > 0 and en_batalla and avisar and avisar.has_signal("mensaje"):
		avisar.emit_signal("mensaje", Textos.batalla(texto))


func _process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP:
		_acumulado -= STEP
		_step()
	_lienzo.queue_redraw()


func _step() -> void:
	if timer > 0:
		timer -= 1
		if timer == 0:
			var aviso: BattlePokemon = pokemon[0] if not pokemon.is_empty() and is_instance_valid(pokemon[0]) else null
			_aviso(TEXTO_TERMINA.get(tipo, 0), aviso)
			tipo = Tipo.NINGUNO
			timer = -1
			for bp: BattlePokemon in pokemon:
				if is_instance_valid(bp):
					bp.velocidad = bp._velocidad_actual()
			cambiado.emit(tipo)
	_step_visual()
	if en_batalla:
		for bp: BattlePokemon in pokemon:
			if is_instance_valid(bp) and not bp.esta_debilitado():
				_step_pokemon(bp)


## EfectoTormentaArena / EfectoGranizo (1 de cada 100 steps pierde 1.5625 % del PS máximo) y las
## habilidades que curan con su clima (1 de cada 150: Cura Lluvia y Piel Seca con lluvia, Gélido con nieve).
func _step_pokemon(bp: BattlePokemon) -> void:
	var tipos: Array = bp.pokemon.especie.tipos.map(func(t: Tipos.Tipo) -> int: return FormulasBatalla.TIPO_ORIGINAL[t])
	var cuarto: int = ceili(bp.hp_max * 1.5625 / 100.0)
	match tipo:
		Tipo.ARENA:
			if not tipos.any(func(t: int) -> bool: return t in INMUNES_ARENA) and bp.habilidad not in HABS_ARENA \
					and bp.pokemon.objeto != 733 and randi_range(1, 100) == 100:
				bp.recibir_danio(cuarto)
		Tipo.GRANIZO:
			if 12 not in tipos and bp.habilidad not in HABS_GRANIZO and bp.pokemon.objeto != 733 and randi_range(1, 100) == 100:
				bp.recibir_danio(cuarto)
	var cura: bool = (bp.habilidad in [44, 87] and llueve()) or (bp.habilidad == 115 and tipo == Tipo.NIEVE)
	if cura and bp.pokemon.hp_actual < bp.hp_max and randi_range(1, 150) == 150:
		bp.curar(cuarto)
		bp.habilidad_actuo()


## Ataque1GolpeaPokemon2: con lluvia el Agua ×1.5 y el Fuego ×0.5; con sol al revés; con arena los
## especiales contra Roca ×0.5; con nieve los físicos contra Hielo ×0.5; Rayo Solar (5, 657) ×0.5 con
## arena, lluvia o nieve. La habilidad 311 del atacante no se fija en el clima.
static func factor_danio(move: MoveData, atacante: BattlePokemon, defensor: BattlePokemon) -> float:
	if actual == null or not is_instance_valid(actual) or actual.tipo == Tipo.NINGUNO:
		return 1.0
	var t: int = FormulasBatalla.TIPO_ORIGINAL[move.tipo]
	var tipos_def: Array = defensor.pokemon.especie.tipos.map(func(x: Tipos.Tipo) -> int: return FormulasBatalla.TIPO_ORIGINAL[x])
	var f: float = 1.0
	var ignora: bool = atacante.habilidad == 311
	if llueve():
		f *= 1.5 if t == 3 else (0.5 if t == 2 else 1.0)
	if soleado():
		f *= 1.5 if t == 2 else (0.5 if t == 3 else 1.0)
	if not ignora:
		if es(Tipo.ARENA) and move.categoria == MoveData.Categoria.ESPECIAL and 6 in tipos_def:
			f *= 0.5
		if es(Tipo.NIEVE) and move.categoria == MoveData.Categoria.FISICO and 12 in tipos_def:
			f *= 0.5
		if move.id_original in [5, 657] and (es(Tipo.ARENA) or llueve() or es(Tipo.NIEVE)):
			f *= 0.5
	return f


static func factor_velocidad(bp: BattlePokemon) -> float:
	var climas: Array = VELOCIDAD.get(bp.habilidad, [])
	return 1.25 if actual != null and is_instance_valid(actual) and actual.tipo in climas else 1.0


## Lo que se ve, en las coordenadas de la vista del original (320×180 en el mapa, 576×324 en combate):
## gotas (obj_gotaLluvia: 2 por step a 6.5-7.5 px/step hacia 255°, y al llegar salpican), relámpagos
## (EfectoTruenosLluvia: 1 de cada 300 steps), el tono del sol (EfectoAlphaSoleado: entre 0.2 y 0.3),
## copos (obj_copoNieve: 3 por step a 1-3 px/step hacia 285°), granizo y arena.
func _vista() -> Vector2:
	return Vector2(576, 324) if en_batalla else Vector2(320, 180)


func _step_visual() -> void:
	var vista: Vector2 = _vista()
	if llueve():
		if randi_range(1, 300) == 300:
			_destello = 1.0
		for i: int in 2:
			_nueva_gota(vista, [6.5, 7.0, 7.5].pick_random(), 255.0, 5, 1.0)
	elif tipo == Tipo.NIEVE:
		for i: int in 3:
			_nueva_gota(vista, [1.0, 2.0, 3.0].pick_random(), 285.0, 20, [0.7, 0.8, 0.9].pick_random())
	elif tipo == Tipo.GRANIZO:
		for i: int in 2:
			_nueva_gota(vista, randf_range(8, 10), 260.0, 5, 0.9)
	elif tipo == Tipo.ARENA:
		for i: int in 2:
			_gotas.append({"pos": Vector2(-20, randf_range(0, vista.y)), "vel": Vector2(randf_range(8, 12), 2), "vida": 80,
				"frame": 0, "alfa": 0.8, "angulo": 0.0})
	_destello = maxf(0.0, _destello - 0.05)
	if soleado():
		_alfa_sol += 0.002 if _sube_sol else -0.002
		if _alfa_sol > 0.3:
			_sube_sol = false
		elif _alfa_sol < 0.2:
			_sube_sol = true
	# EfectoAtomicClima: al acabarse su tiempo se queda quieta y pasa los frames de la salpicadura.
	var vivas: Array[Dictionary] = []
	var frames: int = _sprite_gota().frames.size() if _sprite_gota() else 1
	for g: Dictionary in _gotas:
		if g.vida > 0:
			g.pos += g.vel
			g.vida -= 1
		else:
			g.frame += 1
		if g.frame < frames:
			vivas.append(g)
	_gotas = vivas


func _nueva_gota(vista: Vector2, rapidez: float, direccion: float, minimo: int, alfa: float) -> void:
	var vida: int = maxi(minimo, minimo + ceili(randf() * vista.y / rapidez))
	_gotas.append({"pos": Vector2(-100 + randf() * (vista.x + 200), -40),
		"vel": Vector2(cos(deg_to_rad(direccion)), -sin(deg_to_rad(direccion))) * rapidez, "vida": vida,
		"frame": 0, "alfa": alfa, "angulo": randf() * 360.0 if tipo == Tipo.NIEVE else 0.0})


func _sprite_gota() -> SpriteOriginal:
	var nombre: String = "spr_copo_nieve" if tipo == Tipo.NIEVE else "spr_gota_lluvia"
	if nombre not in _sprites:
		_sprites[nombre] = load(UI + nombre + ".tres") if ResourceLoader.exists(UI + nombre + ".tres") else null
	return _sprites[nombre]


func _dibujar() -> void:
	var vista: Vector2 = _vista()
	_lienzo.scale = get_viewport().get_visible_rect().size / vista
	if soleado():
		_lienzo.draw_rect(Rect2(Vector2.ZERO, vista), Color8(255, 225, 15, int(_alfa_sol * 255)))
	if tipo == Tipo.ARENA:
		_lienzo.draw_rect(Rect2(Vector2.ZERO, vista), Color(0.85, 0.7, 0.4, 0.25))
	var s: SpriteOriginal = _sprite_gota()
	for g: Dictionary in _gotas:
		match tipo:
			Tipo.LLUVIA, Tipo.DILUVIO, Tipo.NIEVE:
				if s:
					# DrawAtomicClima la dibuja dos veces (con su color y en blanco).
					for k: int in 2:
						s.dibujar(_lienzo, g.frame, g.pos, Vector2.ONE, Color(1, 1, 1, g.alfa), g.angulo)
			Tipo.GRANIZO:
				_lienzo.draw_rect(Rect2(g.pos, Vector2(3, 3)), Color(0.85, 0.95, 1.0, 0.9))
			Tipo.ARENA:
				_lienzo.draw_rect(Rect2(g.pos, Vector2(2, 1)), Color(0.8, 0.65, 0.35, 0.8))
	if _destello > 0.0:
		_lienzo.draw_rect(Rect2(Vector2.ZERO, vista), Color(1, 1, 1, _destello))
