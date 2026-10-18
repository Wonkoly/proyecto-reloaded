class_name BattlePokemon
extends CharacterBody2D
## Un Pokémon dentro de la batalla. No lee input: un BattleController hijo le manda la
## dirección (set_direccion) y las órdenes (atacar).

signal hp_cambiado(hp: int, hp_max: int)
signal energia_cambiada(energia: int, energia_max: int)
signal debilitado

const ESCENA_PROYECTIL: PackedScene = preload("res://scenes/battle/proyectil.tscn")
## Límites de velocidad del original (2-15 px/step).
const VELOCIDAD_MIN: float = 60.0
const VELOCIDAD_MAX: float = 450.0
## Recarga de energía: +1 por step (BattlePsPpOptimize).
const RECARGA_ENERGIA: float = 30.0
## Cuánto se ve la pose de herido al recibir un golpe (provisional, ver docs).
const DURACION_HERIDO: float = 0.2
## Dirección (teclado numérico) de cada sector de 45°: desde la derecha, en sentido horario.
const MIRA_POR_SECTOR: Array[int] = [6, 3, 2, 1, 4, 7, 8, 9]
## Sin dibujo propio, las direcciones de la izquierda usan las de la derecha volteadas.
const ESPEJO: Dictionary[int, int] = {1: 3, 4: 6, 7: 9}

## 1 = jugador, 2 = rival.
@export var lado: int = 1
## A quién apuntan sus ataques.
var objetivo: BattlePokemon

var pokemon: PokemonInstance
var hp_max: int = 1
var energia_max: int = 1
## px/s
var velocidad: float = 0.0
## Vector unitario en una de las 8 direcciones, o cero.
var direccion: Vector2 = Vector2.ZERO
## Hacia dónde mira, en notación de teclado numérico.
var mira: int = 2

## Energía con decimales (la recarga es continua); pokemon.energia_actual guarda la parte entera.
var _energia: float = 0.0
## Segundos que faltan para poder volver a atacar / moverse / dejar la pose de herido.
var _cooldown: float = 0.0
var _bloqueo: float = 0.0
var _herido: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	if pokemon:
		_aplicar_pokemon()


## Asigna el Pokémon que representa (antes o después de entrar al árbol).
func configurar(p: PokemonInstance) -> void:
	pokemon = p
	if is_node_ready():
		_aplicar_pokemon()


func set_direccion(dir: Vector2) -> void:
	if dir.length() < 0.2:
		direccion = Vector2.ZERO
	else:
		var sector: int = wrapi(roundi(dir.angle() / (PI / 4.0)), 0, 8)
		direccion = Vector2.RIGHT.rotated(sector * PI / 4.0)
		mira = MIRA_POR_SECTOR[sector]
	_actualizar_animacion()


func esta_debilitado() -> bool:
	return pokemon == null or pokemon.hp_actual <= 0


func puede_moverse() -> bool:
	return not esta_debilitado() and _bloqueo <= 0.0


func puede_recibir_danio() -> bool:
	return not esta_debilitado()


## Si puede usar ya el movimiento: sin cooldown y con energía suficiente, o con la barra llena
## aunque no alcance (entonces queda negativa), como PossibleAttack del original.
func puede_atacar(indice: int) -> bool:
	if esta_debilitado() or _cooldown > 0.0 or indice < 0 or indice >= pokemon.movimientos.size():
		return false
	var costo: int = pokemon.movimientos[indice].costo_energia
	return _energia >= costo or _energia >= energia_max


## Usa el movimiento `indice` (0-3). Devuelve false si no pudo.
func atacar(indice: int) -> bool:
	if not puede_atacar(indice):
		return false
	var move: MoveData = pokemon.movimientos[indice]
	_set_energia(_energia - move.costo_energia)
	_cooldown = move.cooldown
	_bloqueo = move.bloqueo_movimiento
	var proyectil: Proyectil = ESCENA_PROYECTIL.instantiate()
	# El original apunta al rival (point_direction al objetivo); sin rival, hacia donde mira.
	var dir: Vector2 = global_position.direction_to(objetivo.global_position) \
		if objetivo and not objetivo.esta_debilitado() else Vector2.RIGHT.rotated(MIRA_POR_SECTOR.find(mira) * PI / 4.0)
	proyectil.configurar(move, self, dir)
	proyectil.global_position = global_position
	get_parent().add_child(proyectil)
	_actualizar_animacion()
	return true


func recibir_danio(cantidad: int) -> void:
	if esta_debilitado() or cantidad <= 0:
		return
	pokemon.hp_actual = maxi(0, pokemon.hp_actual - cantidad)
	_herido = DURACION_HERIDO
	hp_cambiado.emit(pokemon.hp_actual, hp_max)
	if pokemon.hp_actual == 0:
		direccion = Vector2.ZERO
		debilitado.emit()
	_actualizar_animacion()


func _physics_process(delta: float) -> void:
	var estaba_bloqueado: bool = _bloqueo > 0.0 or _herido > 0.0
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloqueo = maxf(0.0, _bloqueo - delta)
	_herido = maxf(0.0, _herido - delta)
	if puede_moverse() and _energia < energia_max:
		_set_energia(minf(_energia + RECARGA_ENERGIA * delta, energia_max))
	if estaba_bloqueado and _bloqueo <= 0.0 and _herido <= 0.0:
		_actualizar_animacion()
	velocity = direccion * velocidad if puede_moverse() else Vector2.ZERO
	move_and_slide()


func _set_energia(valor: float) -> void:
	var antes: int = floori(_energia)
	_energia = valor
	pokemon.energia_actual = floori(_energia)
	if pokemon.energia_actual != antes:
		energia_cambiada.emit(pokemon.energia_actual, energia_max)


func _aplicar_pokemon() -> void:
	hp_max = pokemon.calcular_stats()["hp"]
	energia_max = pokemon.calcular_energia_maxima()
	velocidad = clampf(pokemon.calcular_velocidad_batalla(), VELOCIDAD_MIN, VELOCIDAD_MAX)
	_energia = pokemon.energia_actual
	sprite.sprite_frames = pokemon.especie.cargar_sprite_frames()
	_actualizar_animacion()
	hp_cambiado.emit(pokemon.hp_actual, hp_max)
	energia_cambiada.emit(pokemon.energia_actual, energia_max)


func _actualizar_animacion() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if esta_debilitado() or _herido > 0.0:
		_pose("herido")
	elif _bloqueo > 0.0:
		_pose("ataque")
	else:
		var anim: String = _animacion("mover")
		if sprite.animation != anim:
			sprite.animation = anim
		if direccion != Vector2.ZERO:
			sprite.play()
		else:
			# Quieto: el original deja el frame 1 sin animar (Pokemon1Movimiento).
			sprite.stop()
			sprite.frame = mini(1, sprite.sprite_frames.get_frame_count(anim) - 1)


## Poses de un frame por dirección (ataque_<mira>, herido_<mira>).
func _pose(base: String) -> void:
	var anim: String = _animacion(base)
	sprite.animation = anim if sprite.sprite_frames.has_animation(anim) else _animacion("mover")
	sprite.stop()
	sprite.frame = 0


## Nombre de la animación "<base>_<mira>" que existe; pone flip_h si usa la de la derecha volteada.
func _animacion(base: String) -> String:
	var propia: String = "%s_%d" % [base, mira]
	sprite.flip_h = false
	if sprite.sprite_frames.has_animation(propia):
		return propia
	if mira in ESPEJO:
		sprite.flip_h = true
		return "%s_%d" % [base, ESPEJO[mira]]
	return "%s_2" % base
