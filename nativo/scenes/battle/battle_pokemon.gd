class_name BattlePokemon
extends CharacterBody2D
## Un Pokémon dentro de la batalla. No lee input: un BattleController hijo le manda la
## dirección (set_direccion) y las órdenes.

signal hp_cambiado(hp: int, hp_max: int)
signal energia_cambiada(energia: int, energia_max: int)
signal debilitado

## Límites de velocidad del original (2-15 px/step).
const VELOCIDAD_MIN: float = 60.0
const VELOCIDAD_MAX: float = 450.0
## Dirección (teclado numérico) de cada sector de 45°: desde la derecha, en sentido horario.
const MIRA_POR_SECTOR: Array[int] = [6, 3, 2, 1, 4, 7, 8, 9]
## Sin dibujo propio, las direcciones de la izquierda usan las de la derecha volteadas.
const ESPEJO: Dictionary[int, int] = {1: 3, 4: 6, 7: 9}

var pokemon: PokemonInstance
var hp_max: int = 1
var energia_max: int = 1
## px/s
var velocidad: float = 0.0
## Vector unitario en una de las 8 direcciones, o cero.
var direccion: Vector2 = Vector2.ZERO
## Hacia dónde mira, en notación de teclado numérico.
var mira: int = 2

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


func puede_moverse() -> bool:
	return pokemon != null and pokemon.hp_actual > 0


func _physics_process(_delta: float) -> void:
	velocity = direccion * velocidad if puede_moverse() else Vector2.ZERO
	move_and_slide()


func _aplicar_pokemon() -> void:
	hp_max = pokemon.calcular_stats()["hp"]
	energia_max = pokemon.calcular_energia_maxima()
	velocidad = clampf(pokemon.calcular_velocidad_batalla(), VELOCIDAD_MIN, VELOCIDAD_MAX)
	sprite.sprite_frames = pokemon.especie.cargar_sprite_frames()
	_actualizar_animacion()
	hp_cambiado.emit(pokemon.hp_actual, hp_max)
	energia_cambiada.emit(pokemon.energia_actual, energia_max)


func _actualizar_animacion() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim: String = _animacion("mover")
	if sprite.animation != anim:
		sprite.animation = anim
	if direccion != Vector2.ZERO:
		sprite.play()
	else:
		# Quieto: el original deja el frame 1 sin animar (Pokemon1Movimiento).
		sprite.stop()
		sprite.frame = mini(1, sprite.sprite_frames.get_frame_count(anim) - 1)


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
