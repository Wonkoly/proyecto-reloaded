class_name Jugador
extends CharacterBody2D
## El protagonista en el overworld (obj_Prota: ProtaMovimiento, ProtaSetSprite). Movimiento libre
## por píxel en 8 direcciones (en diagonal, velocidad / √2), a 90 px/s andando, 120 corriendo y 60
## lento; quieto deja el frame 1 sin animar.

const VELOCIDAD_ANDAR: float = 90.0     # 3 px/step
const VELOCIDAD_CORRER: float = 120.0   # 4 px/step
const VELOCIDAD_LENTO: float = 60.0     # 2 px/step
## image_speed (frames por step) × 30.
const FPS_ANDAR: float = 6.0
const FPS_CORRER: float = 7.5
const FPS_LENTO: float = 4.5
## Vista del original: 320×180 y la sigue con un borde horizontal de 120 px (hborder).
const BORDE_VISTA: float = 120.0

@export var sprite_abajo: SpriteOriginal
@export var sprite_arriba: SpriteOriginal
@export var sprite_derecha: SpriteOriginal

## Notación de teclado numérico, como mira en el original.
var mira: int = 2
var _frame: float = 1.0
var _moviendose: bool = false

@onready var camara: Camera2D = $Camera2D


func _ready() -> void:
	var mapa: Mapa = _mapa()
	if mapa:
		camara.limit_left = 0
		camara.limit_top = 0
		camara.limit_right = mapa.tamano.x
		camara.limit_bottom = mapa.tamano.y
	camara.drag_left_margin = 1.0 - BORDE_VISTA / 160.0
	camara.drag_right_margin = camara.drag_left_margin
	camara.reset_smoothing()


func _physics_process(delta: float) -> void:
	var x: float = Input.get_axis("mover_izquierda", "mover_derecha")
	var y: float = Input.get_axis("mover_arriba", "mover_abajo")
	var dir: Vector2 = Vector2(signf(x) if absf(x) > 0.3 else 0.0, signf(y) if absf(y) > 0.3 else 0.0)
	var velocidad: float = VELOCIDAD_ANDAR
	var fps: float = FPS_ANDAR
	if Input.is_action_pressed("correr"):
		velocidad = VELOCIDAD_CORRER
		fps = FPS_CORRER
	elif Input.is_action_pressed("andar_lento"):
		velocidad = VELOCIDAD_LENTO
		fps = FPS_LENTO
	_moviendose = dir != Vector2.ZERO
	if _moviendose:
		mira = {Vector2(0, 1): 2, Vector2(0, -1): 8, Vector2(-1, 0): 4, Vector2(1, 0): 6,
			Vector2(1, 1): 3, Vector2(-1, 1): 1, Vector2(1, -1): 9, Vector2(-1, -1): 7}[dir]
		var frames: int = _sprite().frames.size() if _sprite() else 1
		_frame = fmod(_frame + fps * delta, frames)
	else:
		_frame = 1.0
	velocity = dir.normalized() * velocidad
	move_and_slide()
	queue_redraw()


func _sprite() -> SpriteOriginal:
	if mira == 2:
		return sprite_abajo
	if mira == 8:
		return sprite_arriba
	return sprite_derecha


func _draw() -> void:
	var s: SpriteOriginal = _sprite()
	if s:
		# Izquierda (1, 4, 7): el sprite de la derecha volteado (ProtaSetSprite).
		s.dibujar(self, int(_frame), Vector2.ZERO, Vector2(-1 if mira in [1, 4, 7] else 1, 1))


func _mapa() -> Mapa:
	var n: Node = get_parent()
	while n and not n is Mapa:
		n = n.get_parent()
	return n as Mapa
