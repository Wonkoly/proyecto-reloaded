class_name Proyectil
extends Area2D
## El proyectil de un ataque (Ataque1/Ataque2 del original). Choca con el Pokémon rival, las
## paredes y los proyectiles rivales.

const RADIO: float = 4.0
## Color provisional por tipo, hasta tener los efectos de cada movimiento.
const COLOR_TIPO: Array[Color] = [
	Color("a8a878"), Color("f08030"), Color("6890f0"), Color("78c850"), Color("f8d030"), Color("98d8d8"),
	Color("c03028"), Color("a040a0"), Color("e0c068"), Color("a890f0"), Color("f85888"), Color("a8b820"),
	Color("b8a038"), Color("705898"), Color("7038f8"), Color("705848"), Color("b8b8d0"), Color("ee99ac"),
]

var move: MoveData
var duenio: BattlePokemon
var direccion: Vector2 = Vector2.RIGHT
var _vida: float = 0.0


func configurar(move_: MoveData, duenio_: BattlePokemon, direccion_: Vector2) -> void:
	move = move_
	duenio = duenio_
	direccion = direccion_.normalized()


func _ready() -> void:
	_vida = move.duracion_proyectil
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += direccion * move.velocidad_proyectil * delta
	_vida -= delta
	if _vida <= 0.0:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIO, COLOR_TIPO[move.tipo])
	draw_circle(Vector2.ZERO, RADIO * 0.5, Color.WHITE)


func _on_body_entered(_body: Node2D) -> void:
	queue_free()  # pared


func _on_area_entered(area: Area2D) -> void:
	if is_queued_for_deletion():
		return
	var otro: Proyectil = area as Proyectil
	if otro:
		# Entre proyectiles rivales sobrevive el de más poder; si empatan, ninguno
		# (Ataque1CollitionAt2). Cada uno decide solo su destino.
		if otro.duenio.lado != duenio.lado and move.poder <= otro.move.poder:
			queue_free()
		return
	var objetivo: BattlePokemon = area.get_parent() as BattlePokemon
	if objetivo and objetivo.lado != duenio.lado and objetivo.puede_recibir_danio():
		var danio: int = FormulasBatalla.calcular_danio(duenio.pokemon, objetivo.pokemon, move,
			GameState.pow_dif(duenio.lado))
		objetivo.recibir_danio(danio)
		queue_free()
