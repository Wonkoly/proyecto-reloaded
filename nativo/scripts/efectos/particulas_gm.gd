class_name ParticulasGM
extends Node2D
## Un sistema de partículas como los de GM8 (part_system), con los efectos de effect_create_*.
## Avanza a 30 steps/s como el original. La arena tiene uno debajo y otro encima de los Pokémon
## (grupos "efectos_debajo" y "efectos_arriba").

const STEP: float = 1.0 / 30.0
const RUTA_FORMAS: String = "res://assets/extraido/sprites/particulas/forma_%d.png"

## Formas de GM8 (pt_shape_*).
enum Forma { PIXEL, DISK, SQUARE, LINE, STAR, CIRCLE, RING, SPHERE, FLARE, SPARK, EXPLOSION, CLOUD, SMOKE, SNOW }
## Efectos de GM8 (ef_*), en el orden de sus constantes.
enum Efecto { EXPLOSION, RING, ELLIPSE, FIREWORK, SMOKE, SMOKEUP, STAR, SPARK, FLARE, CLOUD, RAIN, SNOW }

class Particula:
	var tipo: TipoParticula
	var timer: int = 0
	var vida: int = 0
	var pos: Vector2
	var speed: float
	var direction: float
	var angle: float
	var color: Color
	var alpha: float
	var size: float
	var random_start: int

static var _formas: Array[Texture2D] = []
## Tipos de los efectos, uno por efecto y tamaño (se crean al usarlos).
static var _tipos_efecto: Dictionary[int, Array] = {}

var _particulas: Array[Particula] = []
var _acumulado: float = 0.0


static func arriba(arbol: SceneTree) -> ParticulasGM:
	return arbol.get_first_node_in_group("efectos_arriba") as ParticulasGM


static func debajo(arbol: SceneTree) -> ParticulasGM:
	return arbol.get_first_node_in_group("efectos_debajo") as ParticulasGM


## Color de GM8 (entero BGR); -1 y los negativos son blanco.
static func color_gm(c: int) -> Color:
	if c < 0:
		return Color.WHITE
	return Color8(c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)


static func textura_forma(forma: int) -> Texture2D:
	if _formas.is_empty():
		for i: int in 14:
			_formas.append(load(RUTA_FORMAS % i) if ResourceLoader.exists(RUTA_FORMAS % i) else null)
	return _formas[clampi(forma, 0, 13)]


## part_particles_create: `cantidad` partículas de un tipo en un punto (con color opcional).
func crear(tipo: TipoParticula, posicion: Vector2, cantidad: int = 1, color: Variant = null) -> void:
	for i: int in cantidad:
		var p := Particula.new()
		p.tipo = tipo
		p.pos = posicion
		p.speed = randf_range(tipo.speed_min, tipo.speed_max) if tipo.speed_min < tipo.speed_max else tipo.speed_min
		p.direction = randf_range(tipo.dir_min, tipo.dir_max) if tipo.dir_min < tipo.dir_max else tipo.dir_min
		p.angle = randf_range(tipo.ang_min, tipo.ang_max) if tipo.ang_min < tipo.ang_max else tipo.ang_min
		p.vida = roundi(randf_range(tipo.life_min, tipo.life_max)) if tipo.life_min < tipo.life_max else tipo.life_min
		p.color = color if color is Color else tipo.colores[0]
		p.alpha = tipo.alpha1
		p.size = randf_range(tipo.size_min, tipo.size_max) if tipo.size_min < tipo.size_max else tipo.size_min
		p.random_start = randi() % 100000
		_particulas.append(p)


## part_emitter_burst con un emisor en una región (rectángulo, distribución lineal).
func rafaga(tipo: TipoParticula, region: Rect2, cantidad: int) -> void:
	for i: int in cantidad:
		crear(tipo, region.position + Vector2(randf() * region.size.x, randf() * region.size.y))


## effect_create_above / effect_create_below. tamano: 0 pequeño, 1 mediano, 2 grande.
func efecto(clase: Efecto, posicion: Vector2, tamano: int, color: Color) -> void:
	tamano = clampi(tamano, 0, 2)
	var tipos: Array = _tipos_de_efecto(clase, tamano)
	match clase:
		Efecto.EXPLOSION:
			crear(tipos[0], posicion, 20, color)
			crear(tipos[1], posicion, 1, Color.BLACK)
		Efecto.FIREWORK:
			crear(tipos[0], posicion, [75, 150, 250][tamano], color)
		Efecto.SMOKE, Efecto.SMOKEUP:
			var radio: int = [5, 15, 30][tamano]
			for i: int in [6, 11, 16][tamano]:
				crear(tipos[0], posicion + Vector2(randi_range(-radio, radio - 1), randi_range(-radio, radio - 1)), 1, color)
		Efecto.RAIN, Efecto.SNOW:
			var vista: Rect2 = get_viewport_rect()
			for i: int in ([2, 5, 9] if clase == Efecto.RAIN else [1, 3, 7])[tamano]:
				var x: float = randf() * 1.2 * vista.size.x - (0.0 if clase == Efecto.RAIN else 60.0)
				crear(tipos[0], Vector2(x, randi_range(-30, -12)), 1, color)
		_:
			crear(tipos[0], posicion, 1, color)


func _process(delta: float) -> void:
	_acumulado += delta
	var hubo_step: bool = false
	while _acumulado >= STEP:
		_acumulado -= STEP
		_step()
		hubo_step = true
	if hubo_step or not _particulas.is_empty():
		queue_redraw()


func _step() -> void:
	for p: Particula in _particulas:
		p.timer += 1
	_particulas = _particulas.filter(func(p: Particula) -> bool: return p.timer < p.vida)
	for p: Particula in _particulas:
		var t: TipoParticula = p.tipo
		p.speed = maxf(p.speed + t.speed_incr, 0.0)
		p.direction += t.dir_incr
		p.angle += t.ang_incr
		if t.grav_amount != 0.0:
			var v: Vector2 = Vector2.from_angle(deg_to_rad(-p.direction)) * p.speed \
				+ Vector2.from_angle(deg_to_rad(-t.grav_dir)) * t.grav_amount
			p.speed = v.length()
			p.direction = -rad_to_deg(v.angle())
		var dir: float = p.direction + t.dir_wiggle * _oscilacion(p.timer + p.random_start * 3, 24)
		var spd: float = p.speed + t.speed_wiggle * _oscilacion(p.timer + p.random_start * 4, 20)
		p.pos += Vector2.from_angle(deg_to_rad(-dir)) * spd
		p.size = maxf(p.size + t.size_incr, 0.0)
		var mitad: float = p.timer * 2.0 / p.vida if p.vida >= 1 else 1.0
		if t.colores.size() == 2:
			p.color = t.colores[0].lerp(t.colores[1], mitad / 2.0)
		elif t.colores.size() == 3:
			p.color = t.colores[0].lerp(t.colores[1], mitad) if mitad < 1.0 else t.colores[1].lerp(t.colores[2], mitad - 1.0)
		if mitad >= 1.0:
			p.alpha = (mitad - 1.0) * t.alpha3 + (2.0 - mitad) * t.alpha2
		else:
			p.alpha = mitad * t.alpha2 + (1.0 - mitad) * t.alpha1


## Onda triangular entre -1 y 1 que usa GM8 para el "wiggle".
static func _oscilacion(n: int, periodo: int) -> float:
	var f: float = float(n % periodo) / (periodo / 4.0)
	if f > 2.0:
		f = 4.0 - f
	return f - 1.0


func _draw() -> void:
	for p: Particula in _particulas:
		var t: TipoParticula = p.tipo
		var angulo: float = p.angle + t.ang_wiggle * _oscilacion(p.timer + p.random_start * 2, 16)
		if t.ang_relative:
			angulo += p.direction
		var size: float = p.size + t.size_wiggle * _oscilacion(p.timer + p.random_start, 16)
		var color: Color = Color(p.color, p.alpha)
		draw_set_transform(p.pos, deg_to_rad(-angulo), Vector2(t.xscale, t.yscale) * size)
		if t.sprite:
			draw_texture(t.sprite.frames[0], -t.sprite.origen, color)
		else:
			var tex: Texture2D = textura_forma(t.forma)
			if tex:
				draw_texture(tex, Vector2(-32, -32), color)
	draw_set_transform(Vector2.ZERO)


## Los tipos de cada efecto con los parámetros de GM8 (los crea una sola vez).
static func _tipos_de_efecto(clase: Efecto, tamano: int) -> Array:
	var clave: int = clase * 3 + tamano
	if clave in _tipos_efecto:
		return _tipos_efecto[clave]
	var a := TipoParticula.new()
	var tipos: Array = [a]
	match clase:
		Efecto.EXPLOSION:
			a.forma = Forma.EXPLOSION
			a.orientacion(0, 360).direccion(0, 360).alfa3(0.6, 0.3, 0.0)
			var s: float = [0.1, 0.3, 0.4][tamano]
			var spd: float = [2.0, 4.0, 7.0][tamano]
			a.tamano(s, s, [0.05, 0.1, 0.2][tamano]).velocidad(spd, spd, [-0.1, -0.18, -0.2][tamano])
			a.vida([10, 12, 15][tamano], [15, 17, 20][tamano])
			var b := TipoParticula.new()
			b.forma = Forma.EXPLOSION
			b.orientacion(0, 360).direccion(0, 360).alfa3(0.8, 0.4, 0.0)
			b.tamano(s, s, [0.1, 0.2, 0.4][tamano])
			var vida_b: int = [15, 17, 20][tamano]
			b.vida(vida_b, vida_b)
			tipos.append(b)
		Efecto.RING, Efecto.ELLIPSE:
			a.forma = Forma.RING
			a.alfa3(1.0, 0.5, 0.0)
			var incr: Array = [0.15, 0.25, 0.4] if clase == Efecto.RING else [0.2, 0.35, 0.6]
			a.tamano(0, 0, incr[tamano]).vida([10, 13, 18][tamano], [12, 15, 20][tamano])
			if clase == Efecto.ELLIPSE:
				a.yscale = 0.5
		Efecto.FIREWORK:
			a.forma = Forma.FLARE
			a.tamano(0.1, 0.2).velocidad(0.5, [3.0, 6.0, 8.0][tamano]).direccion(0, 360).alfa3(1.0, 0.7, 0.4)
			a.vida([15, 20, 30][tamano], [25, 30, 40][tamano]).gravedad([0.1, 0.15, 0.17][tamano], 270)
		Efecto.SMOKE, Efecto.SMOKEUP:
			a.forma = Forma.EXPLOSION
			a.tamano([0.2, 0.4, 0.4][tamano], [0.4, 0.7, 1.0][tamano], -0.01).alfa3(0.4, 0.2, 0.0)
			var vida_humo: int = [25, 30, 50][tamano]
			a.vida(vida_humo, vida_humo)
			if clase == Efecto.SMOKEUP:
				a.velocidad([3.0, 5.0, 6.0][tamano], [4.0, 6.0, 7.0][tamano]).direccion(90, 90)
		Efecto.STAR, Efecto.SPARK, Efecto.FLARE:
			a.forma = {Efecto.STAR: Forma.STAR, Efecto.SPARK: Forma.SPARK, Efecto.FLARE: Forma.FLARE}[clase]
			a.orientacion(0, 360)
			var s: float = [0.4, 0.75, 1.2][tamano]
			# ef_star pequeño tiene el tamaño al revés en GM8 (0.4 a 0.3).
			a.tamano(s, 0.3 if clase == Efecto.STAR and tamano == 0 else s, [-0.02, -0.03, -0.04][tamano])
			var vida_e: int = [20, 25, 30][tamano]
			a.vida(vida_e, vida_e)
		Efecto.CLOUD:
			a.forma = Forma.EXPLOSION
			a.yscale = 0.5
			a.alfa3(0.0, 0.3, 0.0).vida(100, 100)
			var s: float = [2.0, 4.0, 8.0][tamano]
			a.tamano(s, s)
		Efecto.RAIN:
			a.forma = Forma.LINE
			a.tamano(0.2, 0.3).orientacion(0, 0, 0, 0, true).velocidad(7, 7).direccion(260, 260)
			a.alfa3(0.4, 0.4, 0.4)
			a.vida(roundi(0.2 * 324), roundi(0.2 * 324))
		Efecto.SNOW:
			a.forma = Forma.SNOW
			a.tamano(0.1, 0.25).alfa3(0.6, 0.6, 0.6).orientacion(0, 360).velocidad(2.5, 3.0)
			a.direccion(240, 300, 0, 20).vida(roundi(0.5 * 324), roundi(0.5 * 324))
	_tipos_efecto[clave] = tipos
	return tipos
