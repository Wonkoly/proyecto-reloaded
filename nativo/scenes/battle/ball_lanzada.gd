class_name BallLanzada
extends Node2D
## La Poké Ball lanzada en un combate contra un salvaje (obj_Pokeball). Persigue al rival
## (PokeBallSiguiendo, 10 px/step), al tocarlo lo encierra (PokeBallCollitionPokemon2), cae y se
## menea (PokeBallSprite) y a un tiempo al azar decide si lo captura (PokeBallCapturando).
## Todo va en steps del original (30 por segundo).

signal resuelta(capturado: bool)

const STEP: float = 1.0 / 30.0
const SPRITES_BALL: Array[String] = [
	"spr_poke_ball", "spr_super_ball", "spr_ultra_ball", "spr_master_ball", "spr_safari_ball", "spr_honor_ball",
	"spr_malla_ball", "spr_buceo_ball", "spr_turno_ball", "spr_lujo_ball", "spr_nido_ball", "spr_acopio_ball",
	"spr_star_ball", "spr_parque_ball", "spr_rapid_ball", "spr_nivel_ball", "spr_cebo_ball", "spr_peso_ball",
	"spr_amor_ball", "spr_amigo_ball", "spr_luna_ball", "spr_sana_ball", "spr_ocaso_ball", "spr_veloz_ball",
	"spr_gloria_ball", "spr_black_ball", "spr_ente_ball",
]

var indice: int = 0
var objetivo: BattlePokemon
## % de captura (PokeBallProbabilidad); la Master Ball, 100.
var probabilidad: float = 0.0

var _volando: bool = true
var _altura: int = 10
var _timer: int = -1
var _timer_t: int = 240
var _open: int = 0
var _md: int = -1
var _espera: int = 7
var _frame: int = 0
var _capturado: bool = false
var _en_suelo: bool = false
var _acumulado: float = 0.0
var _sprite_vuelo: SpriteOriginal
var _sprite_abierta: SpriteOriginal
var _sprite_tipo: SpriteOriginal


func _ready() -> void:
	_sprite_vuelo = load("res://assets/extraido/sprites/ui/spr_ball.tres")
	_sprite_abierta = load("res://assets/extraido/sprites/ui/spr_ball_2.tres")
	var ruta: String = "res://assets/extraido/sprites/ui/%s.tres" % SPRITES_BALL[clampi(indice, 0, SPRITES_BALL.size() - 1)]
	_sprite_tipo = load(ruta) if ResourceLoader.exists(ruta) else _sprite_vuelo
	_frame = indice


func _physics_process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP and is_inside_tree():
		_acumulado -= STEP
		_step()
	queue_redraw()


func _step() -> void:
	if _volando:
		var hacia: Vector2 = objetivo.global_position - global_position
		if hacia.length() <= 10.0:
			_encerrar()
		else:
			global_position += hacia.normalized() * 10.0
		return
	if _timer_t <= 210:
		_open = maxi(0, _open - 1)
		_altura = maxi(0, _altura - 1)
	if _md == -1 and _timer_t <= 192:
		_md = 0
	_timer_t -= 1
	if ((probabilidad < 100 and probabilidad > 80) or (probabilidad < 5 and probabilidad > 0)) and _timer_t > 1 and _altura == 0:
		_timer_t -= 1
	if (probabilidad >= 100 or probabilidad <= 0) and _timer_t > 1 and _md != -1 and _altura == 0:
		_timer_t -= 2
	_menear()
	if _timer_t <= 0 and _capturado:
		set_physics_process(false)
		resuelta.emit(true)
		return
	if _timer != -1 and _timer_t - _timer <= 0:
		_timer = -1
		# ceil(random(100 / pos)) = 1: probabilidad pos / 100.
		if probabilidad > 0.0 and randf() * (100.0 / probabilidad) <= 1.0:
			_capturado = true
		else:
			_soltar()


## PokeBallCollitionPokemon2: el rival desaparece dentro de la ball, que se queda ahí.
func _encerrar() -> void:
	_volando = false
	_open = 1
	_timer = ceili(randf() * 200.0)
	objetivo.visible = false
	objetivo.process_mode = Node.PROCESS_MODE_DISABLED
	objetivo.hurtbox.set_deferred("monitorable", false)


## Falla: el rival vuelve a salir y la ball desaparece.
func _soltar() -> void:
	objetivo.visible = true
	objetivo.process_mode = Node.PROCESS_MODE_INHERIT
	objetivo.hurtbox.set_deferred("monitorable", true)
	set_physics_process(false)
	resuelta.emit(false)
	queue_free()


## PokeBallSprite: ya en el suelo, el frame va de 5 a 0 y a 10 moviendo la ball 1 px por frame y para
## 7 steps cada vez que vuelve al centro.
func _menear() -> void:
	if _altura == 0 and _espera > 0:
		_espera -= 1
	if _md == -1 or _altura != 0:
		return
	if not _en_suelo:  # al cambiar al sprite de su tipo empieza en el frame del centro
		_en_suelo = true
		_frame = 5
	if _espera != 0:
		return
	if _md == 0:
		if _frame == 0:
			_frame += 1
			position.x += 1
			_md = 1
		else:
			_frame -= 1
			position.x -= 1
		if _frame == 5:
			_espera = 7
	else:
		if _frame == 10:
			_frame -= 1
			position.x -= 1
			_md = 0
		else:
			_frame += 1
			position.x += 1


func _draw() -> void:
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	var sprite: SpriteOriginal
	var frame: int = _frame
	if _md != -1 and _altura == 0:
		sprite = _sprite_tipo
	else:
		sprite = _sprite_abierta if _open > 0 else _sprite_vuelo
		frame = indice
	if sprite:
		sprite.dibujar(self, frame, Vector2(0, -_altura))
