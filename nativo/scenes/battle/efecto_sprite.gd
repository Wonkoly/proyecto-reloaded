class_name EfectoSprite
extends Node2D
## Un sprite que se desvanece (objeto EfectoAlpha del original: DefineEfectoAlpha, EfectoAlphaStep,
## DrawEfectoAlpha). Variables con los nombres de GM8; avanza a 30 steps/s.

const STEP: float = 1.0 / 30.0
const SHADER_BLANCO: String = "shader_type canvas_item; void fragment() { COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a) * vec4(1.0, 1.0, 1.0, COLOR.a); }"

static var _material_blanco: ShaderMaterial

var x: float = 0
var y: float = 0
var depth: float = 0
var sprite_index: float = -1
var image_index: float = 0
var image_speed: float = 0
var image_alpha: float = 1
var image_blend: float = 0xFFFFFF
var image_xscale: float = 1
var image_yscale: float = 1
var image_angle: float = 0
var direction: float = 0
var speed: float = 0
var hspeed: float = 0
var vspeed: float = 0
var friction: float = 0
## Alfa que pierde por step.
var RESTA: float = 0.2
## Cuánto crece por step.
var aumento: float = 0
var gira: float = 0
## 1: desaparece al terminar la animación; 2: se queda en el último frame.
var anim: float = 0
## Dibujarlo como silueta blanca.
var WHT: float = 0
var target: Variant = null
var visible_gm: float = 1
var _acumulado: float = 0.0


func _ready() -> void:
	position = Vector2(x, y)


func _process(delta: float) -> void:
	_acumulado += delta
	while _acumulado >= STEP and is_inside_tree():
		_acumulado -= STEP
		_step()
	position = Vector2(x, y)
	queue_redraw()


func _step() -> void:
	# Movimiento de GM8 (speed/direction, fricción).
	if speed != 0.0:
		x += speed * cos(deg_to_rad(direction))
		y -= speed * sin(deg_to_rad(direction))
		speed = maxf(absf(speed) - friction, 0.0) * signf(speed)
	image_alpha -= RESTA
	if image_alpha <= 0.0:
		queue_free()
		return
	image_angle += gira
	if aumento != 0.0:
		image_xscale += aumento * signf(image_xscale)
		image_yscale += aumento * signf(image_yscale)
	if target is Node2D and is_instance_valid(target):
		x = (target as Node2D).global_position.x
		y = (target as Node2D).global_position.y
	var s: SpriteOriginal = AtaqueVisual.sprite(int(sprite_index))
	if s and image_speed != 0.0:
		image_index += image_speed
		if image_index >= s.frames.size():
			if anim == 1.0:
				queue_free()
			elif anim == 2.0:
				image_speed = 0.0
				image_index = s.frames.size() - 1
			else:
				image_index = fmod(image_index, s.frames.size())


func _draw() -> void:
	var s: SpriteOriginal = AtaqueVisual.sprite(int(sprite_index))
	if s == null or visible_gm == 0.0:
		return
	if WHT != 0.0:
		if _material_blanco == null:
			var shader := Shader.new()
			shader.code = SHADER_BLANCO
			_material_blanco = ShaderMaterial.new()
			_material_blanco.shader = shader
		material = _material_blanco
	var c: Color = Color(ParticulasGM.color_gm(int(image_blend)), image_alpha)
	draw_set_transform(Vector2.ZERO, deg_to_rad(-image_angle), Vector2(image_xscale, image_yscale))
	draw_texture(s.frames[int(image_index) % s.frames.size()], -s.origen, c)
	draw_set_transform(Vector2.ZERO)
