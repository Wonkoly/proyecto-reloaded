class_name Proyectil
extends Area2D
## El ataque en el campo (Ataque1/Ataque2 del original). Según el modo del movimiento es un
## proyectil, el propio Pokémon lanzándose contra el rival (contacto) o solo un efecto sobre sí
## mismo (estado). Avanza a 30 steps/s como el original; su aspecto lo dan las animaciones
## traducidas del original (AtaqueVisual). Choca con el Pokémon rival, las paredes y los
## proyectiles rivales.

const STEP: float = 1.0 / 30.0
## Contacto: el ataque dura 15 steps y va a la velocidad del Pokémon + 5 px/step (GolpeaAtack).
const DURACION_CONTACTO: int = 15
const EXTRA_CONTACTO: float = 5.0
## Estado: desaparece a los 2 steps sin chocar.
const DURACION_ESTADO: int = 2
## Movimientos que dibujan líneas entre el Pokémon y el ataque (DrawAtaque1): 4 o 7 líneas.
const LINEAS_4: Array[int] = [19, 44, 57, 134, 223, 675, 570, 700, 760]
const LINEAS_7: Array[int] = [440, 644, 699]
const COLOR_LINEAS: Dictionary[int, int] = {
	19: 5086551, 223: 0xFFFFFF, 675: 0x800080, 440: 52235, 644: 33023, 699: 4157846, 700: 0, 760: 0x4A9CD5,
}

var move: MoveData
var duenio: BattlePokemon
var direccion: Vector2 = Vector2.RIGHT
var visual: AtaqueVisual
var _steps_restantes: int = 0
var _acumulado: float = 0.0


func configurar(move_: MoveData, duenio_: BattlePokemon, direccion_: Vector2) -> void:
	move = move_
	duenio = duenio_
	direccion = direccion_.normalized()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	visual = AtaqueVisual.new(ParticulasGM.arriba(get_tree()), ParticulasGM.debajo(get_tree()))
	var v: AtaqueVisual = visual
	v.index = move.id_original
	v.x = global_position.x
	v.y = global_position.y
	v.direction = fposmod(-rad_to_deg(direccion.angle()), 360.0)
	v.speed = move.velocidad_proyectil * STEP
	v.POKECREATOR = duenio.lado
	_actualizar_creador()
	_steps_restantes = roundi(move.duracion_proyectil / STEP)
	match move.modo:
		MoveData.Modo.CONTACTO, MoveData.Modo.ESPECIAL:
			v.speed = duenio.velocidad * STEP + EXTRA_CONTACTO
			_steps_restantes = DURACION_CONTACTO
			duenio.embestir(DURACION_CONTACTO * STEP)
		MoveData.Modo.ESTADO:
			v.speed = 0.0
			_steps_restantes = DURACION_ESTADO
			set_deferred("monitoring", false)
	v.crear()


func _physics_process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP and not is_queued_for_deletion():
		_acumulado -= STEP
		_step()


func _step() -> void:
	var v: AtaqueVisual = visual
	_actualizar_creador()
	v.xprevious = v.x
	v.yprevious = v.y
	v.paso()
	# Movimiento de GM8: speed/direction (+ hspeed/vspeed) y fricción.
	v.x += v.speed * cos(deg_to_rad(v.direction)) + v.hspeed
	v.y -= v.speed * sin(deg_to_rad(v.direction)) - v.vspeed
	if v.friction != 0.0:
		v.speed = maxf(v.speed - v.friction, 0.0)
	if move.modo in [MoveData.Modo.CONTACTO, MoveData.Modo.ESPECIAL] and is_instance_valid(duenio):
		# El Pokémon va con el ataque (EffectAtack: creator.x = x), sin atravesar paredes.
		duenio.move_and_collide(Vector2(v.x, v.y) - duenio.global_position)
		v.x = duenio.global_position.x
		v.y = duenio.global_position.y
	global_position = Vector2(v.x, v.y)
	var s: SpriteOriginal = AtaqueVisual.sprite(int(v.sprite_index))
	if s:
		v.image_index = fmod(v.image_index + v.image_speed, s.frames.size())
	queue_redraw()
	_steps_restantes -= 1
	if _steps_restantes <= 0:
		queue_free()


func _actualizar_creador() -> void:
	if not is_instance_valid(duenio):
		return
	visual.creator_x = duenio.global_position.x
	visual.creator_y = duenio.global_position.y
	visual.creator_mira = duenio.mira
	visual.creator_vel = duenio.velocidad * STEP


func _draw() -> void:
	var v: AtaqueVisual = visual
	if v == null:
		return
	if AtaqueVisual.generado() == null:
		draw_circle(Vector2.ZERO, 4.0, Color.WHITE)  # sin las animaciones extraídas
		return
	var s: SpriteOriginal = AtaqueVisual.sprite(int(v.sprite_index))
	if s and int(v.sprite_index) != AtaqueVisual.SPRITE_INVISIBLE and v.visible != 0.0:
		s.dibujar(self, int(v.image_index), Vector2.ZERO, Vector2(v.image_xscale, v.image_yscale),
			Color(ParticulasGM.color_gm(int(v.image_blend)), v.image_alpha), v.image_angle)
	_dibujar_lineas()


## DrawAtaque1: algunos movimientos (rayos) dibujan líneas desde el Pokémon hasta el ataque.
func _dibujar_lineas() -> void:
	var idx: int = int(visual.index)
	if not is_instance_valid(duenio) or (idx not in LINEAS_4 and idx not in LINEAS_7):
		return
	var color: Color = ParticulasGM.color_gm(COLOR_LINEAS.get(idx, int(visual.col)))
	var desde: Vector2 = duenio.global_position - global_position
	var diagonal: bool = duenio.mira == 3 or duenio.mira == 7
	var desplazamientos: Array[int] = [2, 3, -2, -3]
	if idx in LINEAS_7:
		desplazamientos = [0, 1, -1, 2, 3, -2, -3]
	for d: int in desplazamientos:
		var o: Vector2 = Vector2(d, -d) if diagonal else Vector2(d, d)
		draw_line(desde + o, o, color)


func _on_body_entered(_body: Node2D) -> void:
	if move.modo == MoveData.Modo.PROYECTIL:
		queue_free()  # pared


func _on_area_entered(area: Area2D) -> void:
	if is_queued_for_deletion() or move.modo == MoveData.Modo.ESTADO:
		return
	var otro: Proyectil = area as Proyectil
	if otro:
		# Entre proyectiles rivales sobrevive el de más poder; si empatan, ninguno
		# (Ataque1CollitionAt2). Cada uno decide solo su destino.
		if otro.duenio.lado != duenio.lado and move.poder <= otro.move.poder and otro.move.modo != MoveData.Modo.ESTADO:
			queue_free()
		return
	var objetivo: BattlePokemon = area.get_parent() as BattlePokemon
	if objetivo and objetivo.lado != duenio.lado and objetivo.puede_recibir_danio():
		var danio: int = FormulasBatalla.danio_en_batalla(duenio, objetivo, move)
		objetivo.recibir_golpe(move, danio, Efectividad.multiplicador(move.tipo, objetivo.pokemon.especie.tipos))
		objetivo.efectos_de_golpe(move, duenio, danio)
		queue_free()
