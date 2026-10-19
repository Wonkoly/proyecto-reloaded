class_name AtaqueVisual
extends RefCounted
## Estado visual de un ataque con las variables y funciones de GM8 que usa el código traducido
## del original (data/extraido/visuales/visuales_ataques.gd, generado por tools/gml_visual.py).
## Unidades del original: px/step, grados en sentido antihorario, colores BGR enteros.

const RUTA_GENERADO: String = "res://data/extraido/visuales/visuales_ataques.gd"
const RUTA_SPRITES: String = "res://assets/extraido/sprites/efectos/%d.tres"
## spr_atack: el sprite por defecto del ataque, que no se dibuja (DrawAtaque1).
const SPRITE_INVISIBLE: int = 1

static var _generado: GDScript
static var _sprites: Dictionary[int, SpriteOriginal] = {}

# Variables de la instancia del ataque (mismos nombres que en GM8).
var index: float = 0
var x: float = 0
var y: float = 0
var xprevious: float = 0
var yprevious: float = 0
var direction: float = 0
var speed: float = 0
var hspeed: float = 0
var vspeed: float = 0
var friction: float = 0
var image_angle: float = 0
var image_xscale: float = 1
var image_yscale: float = 1
var image_alpha: float = 1
var image_blend: float = 0xFFFFFF
var image_speed: float = 1
var image_index: float = 0
var visible: float = 1
var sprite_index: float = SPRITE_INVISIBLE
var POKECREATOR: float = 1
var dir: float = 0
# Variables de EfectoEspecial.
var spr: float = -1
var shape: float = -1
var size: float = -1
var spd: float = -1
var col: float = -1
var life: float = -1
var COLOR: float = -1
var COL: float = -1
# Del Pokémon que lanzó el ataque.
var creator_x: float = 0
var creator_y: float = 0
var creator_mira: float = 2
var creator_image_xscale: float = 1
var creator_image_yscale: float = 1
var creator_bbox_bottom: float = 0
var creator_bbox_top: float = 0
var creator_vel: float = 0
## Variables propias o locales que usa cada movimiento.
var vars: Dictionary = {}
## El último efecto creado (z en el original), que algunos movimientos siguen ajustando.
var z: Variant = null

var pt: TipoParticula
var _region: Rect2 = Rect2()
var _forma_region: int = 0
var _arriba: ParticulasGM
var _debajo: ParticulasGM


func _init(arriba: ParticulasGM, debajo: ParticulasGM) -> void:
	_arriba = arriba
	_debajo = debajo


static func generado() -> GDScript:
	if _generado == null and ResourceLoader.exists(RUTA_GENERADO):
		var g: GDScript = load(RUTA_GENERADO)
		if g and g.can_instantiate():
			_generado = g
	return _generado


static func sprite(id: int) -> SpriteOriginal:
	if id not in _sprites:
		_sprites[id] = load(RUTA_SPRITES % id) if ResourceLoader.exists(RUTA_SPRITES % id) else null
	return _sprites[id]


## EfectoEspecial + EffectAtackCreate: al lanzar el ataque.
func crear() -> void:
	var g: GDScript = generado()
	if g:
		g.especial(self)
		g.crear(self)


## EffectAtack: cada step (el emisor sigue al ataque).
func paso() -> void:
	var g: GDScript = generado()
	if g and pt:
		region(x, x, y, y, 2, 0)
		g.paso(self)


# Funciones de GM8 --------------------------------------------------------------------------

func z_get(campo: String) -> Variant:
	return z.get(campo) if z is Object and is_instance_valid(z) else 0


func z_set(campo: String, valor: Variant) -> void:
	if z is Object and is_instance_valid(z):
		z.set(campo, valor)


## Igualdad de GML: compara como números (true = 1, false = 0).
func eq(a: Variant, b: Variant) -> bool:
	return float(a) == float(b)


func round_gm(v: float) -> float:
	var r: float = roundf(v)
	if absf(v - floorf(v) - 0.5) < 1e-9 and fmod(r, 2.0) != 0.0:
		r -= signf(v)
	return r


func frac(v: float) -> float:
	return v - floorf(v) if v >= 0.0 else v - ceilf(v)


func lengthdir_x(largo: float, angulo: float) -> float:
	return largo * cos(deg_to_rad(angulo))


func lengthdir_y(largo: float, angulo: float) -> float:
	return -largo * sin(deg_to_rad(angulo))


func point_direction(x1: float, y1: float, x2: float, y2: float) -> float:
	return fposmod(rad_to_deg(atan2(-(y2 - y1), x2 - x1)), 360.0)


func make_color_rgb(r: float, g: float, b: float) -> float:
	return int(r) | (int(g) << 8) | (int(b) << 16)


func make_color_hsv(h: float, s: float, v: float) -> float:
	var c: Color = Color.from_hsv(h / 255.0, s / 255.0, v / 255.0)
	return make_color_rgb(c.r8, c.g8, c.b8)


func merge_color(c1: float, c2: float, t: float) -> float:
	var a: Color = ParticulasGM.color_gm(int(c1))
	var b: Color = ParticulasGM.color_gm(int(c2))
	var m: Color = a.lerp(b, t)
	return make_color_rgb(m.r8, m.g8, m.b8)


# Partículas (part_type_* sobre pt1, part_emitter_* sobre el emisor del ataque) -----------

func pt_create() -> void:
	pt = TipoParticula.new()


func pt_shape(forma: float) -> void:
	pt.forma = int(forma)
	pt.sprite = null


func pt_sprite(id: float, _animar: float = 0, _estirar: float = 0, _azar: float = 0) -> void:
	pt.sprite = sprite(int(id))


func pt_size(minimo: float, maximo: float, incr: float, wiggle: float) -> void:
	pt.tamano(minimo, maximo, incr, wiggle)


func pt_scale(sx: float, sy: float) -> void:
	pt.xscale = sx
	pt.yscale = sy


func pt_speed(minimo: float, maximo: float, incr: float, wiggle: float) -> void:
	pt.velocidad(minimo, maximo, incr, wiggle)


func pt_direction(minimo: float, maximo: float, incr: float, wiggle: float) -> void:
	pt.direccion(minimo, maximo, incr, wiggle)


func pt_orientation(minimo: float, maximo: float, incr: float, wiggle: float, relativa: float) -> void:
	pt.orientacion(minimo, maximo, incr, wiggle, relativa != 0.0)


func pt_life(minimo: float, maximo: float) -> void:
	pt.vida(int(minimo), int(maximo))


func pt_gravity(cantidad: float, direccion_: float) -> void:
	pt.gravedad(cantidad, direccion_)


func pt_color1(c: float) -> void:
	pt.colores = [ParticulasGM.color_gm(int(c))]


func pt_color2(c1: float, c2: float) -> void:
	pt.colores = [ParticulasGM.color_gm(int(c1)), ParticulasGM.color_gm(int(c2))]


func pt_color3(c1: float, c2: float, c3: float) -> void:
	pt.colores = [ParticulasGM.color_gm(int(c1)), ParticulasGM.color_gm(int(c2)), ParticulasGM.color_gm(int(c3))]


func pt_alpha1(a: float) -> void:
	pt.alfa3(a, a, a)


func pt_alpha2(a1: float, a2: float) -> void:
	pt.alfa2(a1, a2)


func pt_alpha3(a1: float, a2: float, a3: float) -> void:
	pt.alfa3(a1, a2, a3)


func pt_blend(aditivo: float) -> void:
	pt.aditivo = aditivo != 0.0


func region(xmin: float, xmax: float, ymin: float, ymax: float, forma: float = 0, _distribucion: float = 0) -> void:
	_region = Rect2(xmin, ymin, xmax - xmin, ymax - ymin)
	_forma_region = int(forma)


func burst(cantidad: float) -> void:
	if pt == null or _arriba == null:
		return
	for i: int in int(cantidad):
		_arriba.crear(pt, _punto_region())


## Un punto al azar dentro de la región del emisor según su forma (rectángulo, elipse, rombo, línea).
func _punto_region() -> Vector2:
	var r: Rect2 = _region
	if r.size == Vector2.ZERO:
		return r.position
	for intento: int in 50:
		var u: Vector2 = Vector2(randf(), randf())
		if _forma_region == 3:
			u.y = u.x
		var d: Vector2 = (u - Vector2(0.5, 0.5)) * 2.0
		if (_forma_region == 1 and d.length() > 1.0) or (_forma_region == 2 and absf(d.x) + absf(d.y) > 1.0):
			continue
		return r.position + u * r.size
	return r.get_center()


func effect_above(clase: float, px: float, py: float, tamano: float, c: float) -> void:
	if _arriba:
		_arriba.efecto(int(clase) as ParticulasGM.Efecto, Vector2(px, py), int(tamano), ParticulasGM.color_gm(int(c)))


func effect_below(clase: float, px: float, py: float, tamano: float, c: float) -> void:
	if _debajo:
		_debajo.efecto(int(clase) as ParticulasGM.Efecto, Vector2(px, py), int(tamano), ParticulasGM.color_gm(int(c)))


## effect_create_sprite del original: un EfectoAlpha en la posición del ataque.
func effect_sprite(id: float, blend: float = 0, resta: float = 0, aumento: float = 0, alfa: float = 0,
		escala: float = 0, angulo: float = 0, velocidad_imagen: float = 0) -> EfectoSprite:
	var e: EfectoSprite = effect_alpha(x, y)
	e.sprite_index = id
	e.image_blend = blend
	e.WHT = 1.0 if int(blend) == 0xFFFFFF else 0.0
	e.RESTA = resta
	e.aumento = aumento
	e.image_alpha = alfa
	if escala > 0.0:
		e.image_xscale = escala
		e.image_yscale = escala
	e.image_angle = angulo
	if velocidad_imagen > 0.0:
		e.anim = 1
		e.image_speed = velocidad_imagen
	return e


## instance_create(x, y, EfectoAlpha).
func effect_alpha(px: float, py: float) -> EfectoSprite:
	var e := EfectoSprite.new()
	e.x = px
	e.y = py
	if _arriba:
		_arriba.add_child(e)
	return e
