## Particle systems and effects (part_*, effect_*), ported from OpenGMK's particle.rs.
## Attractors, deflectors, changers and destroyers are not ported: the game never uses them.
class_name GMLibFx
extends GMLibSys

class PType:
	var sprite := -1 # >= 0: sprite graphic, else `shape`
	var shape := 0
	var animat := true
	var stretch := false
	var random := false
	var size_min := 1.0
	var size_max := 1.0
	var size_incr := 0.0
	var size_wiggle := 0.0
	var xscale := 1.0
	var yscale := 1.0
	var life_min := 100
	var life_max := 100
	var death_type := 0
	var death_number := 0
	var step_type := 0
	var step_number := 0
	var speed_min := 0.0
	var speed_max := 0.0
	var speed_incr := 0.0
	var speed_wiggle := 0.0
	var dir_min := 0.0
	var dir_max := 0.0
	var dir_incr := 0.0
	var dir_wiggle := 0.0
	var grav_amount := 0.0
	var grav_dir := 270.0
	var ang_min := 0.0
	var ang_max := 0.0
	var ang_incr := 0.0
	var ang_wiggle := 0.0
	var ang_relative := false
	## ["one", c] | ["two", c1, c2] | ["three", c1, c2, c3] | ["rgb", rmin, rmax, gmin, gmax, bmin, bmax]
	## | ["hsv", hmin, hmax, smin, smax, vmin, vmax] | ["mix", c1, c2]
	var colour: Array = ["one", 0xFFFFFF]
	var alpha1 := 1.0
	var alpha2 := 1.0
	var alpha3 := 1.0
	var additive := false

class Particle:
	var ptype := 0
	var timer := 0
	var lifetime := 0
	var x := 0.0
	var y := 0.0
	var speed := 0.0
	var direction := 0.0
	var image_angle := 0.0
	var colour := 0xFFFFFF
	var alpha := 1.0
	var size := 1.0
	var subimage := 0
	var random_start := 0

class Emitter:
	var xmin := 0.0
	var xmax := 0.0
	var ymin := 0.0
	var ymax := 0.0
	var shape := 0 # 0 rectangle, 1 ellipse, 2 diamond, 3 line
	var distribution := 0 # 0 linear, 1 gaussian, 2 inverse gaussian
	var ptype := -1
	var number := 0

class PSystem:
	var id := 0
	var particles: Array = []
	var emitters: Array = [] # Emitter or null
	var draw_old_to_new := true
	var depth := 0.0
	var x := 0.0
	var y := 0.0
	var auto_update := true
	var auto_draw := true

static var _systems: Array = [] # PSystem or null
static var _types: Array = []   # PType or null
static var _draw_order: Array = [] # system ids, sorted stably by depth when drawing
static var _shapes: Array = []  # ImageTexture x14
static var _fx: Dictionary = {} # effect systems and types, created on first effect

# ------------------------------------------------------------------ helpers

static func _sys(id: Variant) -> PSystem:
	var k := ri(id)
	return _systems[k] if k >= 0 and k < _systems.size() else null

static func _pt(id: Variant) -> PType:
	var k := ri(id)
	return _types[k] if k >= 0 and k < _types.size() else null

static func _emitter(ps: Variant, id: Variant) -> Emitter:
	var sy := _sys(ps)
	var k := ri(id)
	if sy == null or k < 0 or k >= sy.emitters.size():
		return null
	return sy.emitters[k]

static func _rnd(n: float) -> float:
	return rng.randf() * n

static func _rnd_int(n: int) -> int:
	return rng.randi() % n if n > 0 else 0

static func _range(lo: float, hi: float, distr := 0) -> float:
	if lo >= hi:
		return lo
	match distr:
		1, 2:
			var x := 0.0
			while true:
				x = _rnd(6.0) - 3.0
				if exp(-x * x * 0.5) > _rnd(1.0):
					break
			if distr == 1:
				return lo + (hi - lo) * (x + 3.0) / 6.0
			if x < 0.0:
				x += 6.0
			return lo + (hi - lo) * x / 6.0
	return _rnd(hi - lo) + lo

static func _colour_lerp(c1: int, c2: int, k: float) -> int:
	var r := roundi((c1 & 0xFF) * (1.0 - k) + (c2 & 0xFF) * k)
	var g := roundi(((c1 >> 8) & 0xFF) * (1.0 - k) + ((c2 >> 8) & 0xFF) * k)
	var b := roundi(((c1 >> 16) & 0xFF) * (1.0 - k) + ((c2 >> 16) & 0xFF) * k)
	return r | (g << 8) | (b << 16)

static func _init_colour(c: Array) -> int:
	match c[0]:
		"rgb":
			return roundi(_range(c[1], c[2])) | (roundi(_range(c[3], c[4])) << 8) | (roundi(_range(c[5], c[6])) << 16)
		"hsv":
			var h := roundi(_range(c[1], c[2])) * 360.0 / 255.0
			var s := roundi(_range(c[3], c[4])) / 255.0
			var v := roundi(_range(c[5], c[6])) / 255.0
			var chroma := v * s
			var hp := fmod(h / 60.0, 6.0)
			var x := chroma * (1.0 - absf(fmod(hp, 2.0) - 1.0))
			var m := v - chroma
			var rgb := [0.0, 0.0, 0.0]
			match int(floorf(hp)):
				0: rgb = [chroma, x, 0.0]
				1: rgb = [x, chroma, 0.0]
				2: rgb = [0.0, chroma, x]
				3: rgb = [0.0, x, chroma]
				4: rgb = [x, 0.0, chroma]
				5: rgb = [chroma, 0.0, x]
			return roundi((rgb[0] + m) * 255.0) | (roundi((rgb[1] + m) * 255.0) << 8) | (roundi((rgb[2] + m) * 255.0) << 16)
		"mix":
			return _colour_lerp(c[1], c[2], _rnd(1.0))
	return c[1]

static func _new_particle(ptype: int, x: float, y: float, colour = null) -> Particle:
	var t := _pt(ptype)
	if t == null:
		return null
	var p := Particle.new()
	p.ptype = ptype
	p.speed = _range(t.speed_min, t.speed_max)
	p.direction = _range(t.dir_min, t.dir_max)
	p.image_angle = _range(t.ang_min, t.ang_max)
	p.lifetime = roundi(_range(t.life_min, t.life_max))
	var c := _init_colour(t.colour) # drawn even when `colour` is given, for RNG parity
	p.alpha = t.alpha1
	p.size = _range(t.size_min, t.size_max)
	if t.sprite >= 0 and t.random:
		p.subimage = _rnd_int(10000)
	p.random_start = _rnd_int(100000)
	p.x = x
	p.y = y
	p.colour = colour if colour != null else c
	return p

static func _create_particles(sy: PSystem, x: float, y: float, ptype: int, colour, number: int) -> void:
	for i in number:
		var p := _new_particle(ptype, x, y, colour)
		if p:
			sy.particles.append(p)

static func _wiggle(v: int, period: int, quarter: float) -> float:
	var f := float(v % period) / quarter
	if f > 2.0:
		f = 4.0 - f
	return f - 1.0

static func _burst(sy: PSystem, em: Emitter, ptype: int, number: int) -> void:
	if number < 0:
		if _rnd_int(-number) != 0:
			return
		number = 1
	for i in number:
		var xs := 0.0
		var ys := 0.0
		while true:
			xs = _range(0.0, 1.0, em.distribution)
			ys = _range(0.0, 1.0, em.distribution)
			if em.distribution == 2 and em.shape != 3:
				if _rnd(1.0) >= 0.5:
					ys = _rnd(1.0)
				else:
					xs = _rnd(1.0)
			var dx := (xs - 0.5) * 2.0
			var dy := (ys - 0.5) * 2.0
			var inside := true
			if em.shape == 1:
				inside = Vector2(dx, dy).length() <= 1.0
			elif em.shape == 2:
				inside = dx + dy <= 1.0
			if inside:
				if em.shape == 3:
					ys = xs
				break
		var p := _new_particle(ptype, (em.xmax - em.xmin) * xs + em.xmin, (em.ymax - em.ymin) * ys + em.ymin)
		if p:
			sy.particles.append(p)

static func _update_system(sy: PSystem) -> void:
	# Lifetimes, step and death particles
	var n := sy.particles.size()
	for i in n:
		var p: Particle = sy.particles[i]
		p.timer += 1
		var t := _pt(p.ptype)
		if t == null:
			continue
		var kind := t.death_type if p.timer >= p.lifetime else t.step_type
		var number := t.death_number if p.timer >= p.lifetime else t.step_number
		if number < 0 and _rnd_int(-number) == 0:
			number = 1
		if number > 0:
			_create_particles(sy, p.x, p.y, kind, null, number)
	sy.particles = sy.particles.filter(func(p): return p.timer < p.lifetime)
	for p: Particle in sy.particles:
		var t := _pt(p.ptype)
		if t == null:
			continue
		# Physics
		p.speed = maxf(p.speed + t.speed_incr, 0.0)
		p.direction += t.dir_incr
		p.image_angle += t.ang_incr
		if t.grav_amount != 0.0:
			var hs := cos(deg_to_rad(p.direction)) * p.speed + cos(deg_to_rad(t.grav_dir)) * t.grav_amount
			var vs := -sin(deg_to_rad(p.direction)) * p.speed - sin(deg_to_rad(t.grav_dir)) * t.grav_amount
			p.speed = sqrt(hs * hs + vs * vs)
			p.direction = -rad_to_deg(atan2(vs, hs))
		var dir := p.direction + t.dir_wiggle * _wiggle(p.timer + p.random_start * 3, 24, 6.0)
		var spd := p.speed + t.speed_wiggle * _wiggle(p.timer + p.random_start * 4, 20, 5.0)
		p.x += cos(deg_to_rad(dir)) * spd
		p.y -= sin(deg_to_rad(dir)) * spd
		# Graphics
		p.size = maxf(p.size + t.size_incr, 0.0)
		var half := float(p.timer * 2) / p.lifetime if p.lifetime >= 1 else 1.0
		match t.colour[0]:
			"two":
				p.colour = _colour_lerp(t.colour[1], t.colour[2], half / 2.0)
			"three":
				p.colour = _colour_lerp(t.colour[1], t.colour[2], half) if half < 1.0 \
					else _colour_lerp(t.colour[2], t.colour[3], half - 1.0)
		if half >= 1.0:
			p.alpha = (half - 1.0) * t.alpha3 + (2.0 - half) * t.alpha2
		else:
			p.alpha = half * t.alpha2 + (1.0 - half) * t.alpha1
	for em in sy.emitters:
		if em != null and em.number != 0:
			_burst(sy, em, em.ptype, em.number)

static func _shape_tex(i: int) -> Texture2D:
	if _shapes.is_empty():
		var raw := FileAccess.get_file_as_bytes(GMAssets.internal("particles.dat"))
		for k in 14:
			var px := PackedByteArray()
			px.resize(64 * 64 * 4)
			px.fill(255)
			for j in 64 * 64:
				px[j * 4 + 3] = raw[64 * 64 * k + j] if raw.size() >= 64 * 64 * (k + 1) else 0
			_shapes.append(ImageTexture.create_from_image(Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, px)))
	return _shapes[i] if i >= 0 and i < _shapes.size() else null

static func _draw_particle(sy: PSystem, p: Particle) -> void:
	var t := _pt(p.ptype)
	if t == null:
		return
	var angle := p.image_angle + t.ang_wiggle * _wiggle(p.timer + p.random_start * 2, 16, 4.0)
	if t.ang_relative:
		angle += p.direction
	var size := p.size + t.size_wiggle * _wiggle(p.timer + p.random_start, 16, 4.0)
	var x := sy.x + p.x
	var y := sy.y + p.y
	if t.sprite >= 0:
		var spr := GMAssets.sprite(t.sprite)
		if spr == null or spr.frames == 0:
			return
		var sub := p.subimage
		if t.animat:
			sub += spr.frames * p.timer / p.lifetime if t.stretch and p.lifetime > 0 else p.timer
		_draw_sprite_raw(spr, posmod(sub, spr.frames), x, y, t.xscale * size, t.yscale * size, angle, p.colour, p.alpha)
		return
	var tex := _shape_tex(t.shape)
	if tex == null:
		return
	var xf := _view * Transform2D(deg_to_rad(-angle), Vector2(t.xscale * size, t.yscale * size), 0.0, Vector2(x, y)) \
		* Transform2D(0.0, Vector2(-32, -32))
	_tex(tex, Rect2(0, 0, 64, 64), xf, gm_color(p.colour, p.alpha))

# ------------------------------------------------------------------ runtime hooks

## Auto-drawn systems, deepest first (stable, like GM8's draw order).
static func particle_systems_by_depth() -> Array:
	var out := []
	for id in _draw_order:
		var sy := _sys(id)
		if sy and sy.auto_draw:
			out.append(sy)
	var idx := {}
	for i in out.size():
		idx[out[i]] = i
	out.sort_custom(func(a, b): return a.depth > b.depth or (a.depth == b.depth and idx[a] < idx[b]))
	return out

static func particle_system_draw(sy: PSystem) -> void:
	if sy.draw_old_to_new:
		for p in sy.particles:
			_draw_particle(sy, p)
	else:
		for i in range(sy.particles.size() - 1, -1, -1):
			_draw_particle(sy, sy.particles[i])

static func particles_auto_update() -> void:
	for sy in _systems:
		if sy != null and sy.auto_update:
			_update_system(sy)

static func effects_clear() -> void:
	if not _fx.is_empty():
		_systems[_fx.below].particles.clear()
		_systems[_fx.above].particles.clear()

# ------------------------------------------------------------------ effects

static func _effect_types(n: int) -> Array:
	var out := []
	for i in n:
		out.append(int(f_part_type_create(null)))
	return out

static func _create_effect(kind: int, x: float, y: float, size: int, col: int, below: bool) -> void:
	if _fx.is_empty():
		_fx.below = int(f_part_system_create(null))
		_fx.above = int(f_part_system_create(null))
		_systems[_fx.below].depth = 100000.0
		_systems[_fx.above].depth = -100000.0
		_fx.explosion = _effect_types(6)
		for k in ["ring", "ellipse", "firework", "smoke", "smokeup", "star", "spark", "flare", "cloud"]:
			_fx[k] = _effect_types(3)
		_fx.rain = _effect_types(1)[0]
		_fx.snow = _effect_types(1)[0]
	var sy: PSystem = _systems[_fx.below if below else _fx.above]
	var fm := maxf(30.0 / room_speed, 1.0) # fps_mod
	var sz := 0 if size == 0 else (2 if size == 2 else 1)
	var life := func(v: float) -> int: return roundi(v / fm)
	match kind:
		0: # explosion
			var id1: int = _fx.explosion[sz * 2]
			var id2: int = _fx.explosion[sz * 2 + 1]
			var t := _pt(id1)
			t.shape = 10; t.sprite = -1
			t.size_wiggle = 0.0
			t.ang_min = 0.0; t.ang_max = 360.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = false
			t.dir_min = 0.0; t.dir_max = 360.0; t.dir_incr = 0.0; t.dir_wiggle = 0.0
			t.speed_wiggle = 0.0
			t.alpha1 = 0.6; t.alpha2 = 0.3; t.alpha3 = 0.0
			var p1: Array = [[0.1, 0.05, 2.0, -0.1, 10, 15], [0.3, 0.1, 4.0, -0.18, 12, 17], [0.4, 0.2, 7.0, -0.2, 15, 20]][sz]
			t.size_min = p1[0]; t.size_incr = fm * p1[1]
			t.speed_min = fm * p1[2]; t.speed_incr = fm * p1[3]
			t.life_min = life.call(p1[4]); t.life_max = life.call(p1[5])
			t.size_max = t.size_min
			t.speed_max = t.speed_min
			t = _pt(id2)
			t.shape = 10; t.sprite = -1
			t.ang_min = 0.0; t.ang_max = 360.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = false
			t.dir_min = 0.0; t.dir_max = 360.0; t.dir_incr = 0.0; t.dir_wiggle = 0.0
			t.speed_wiggle = 0.0
			t.alpha1 = 0.8; t.alpha2 = 0.4; t.alpha3 = 0.0
			var p2: Array = [[0.1, 0.1, 15], [0.3, 0.2, 17], [0.4, 0.4, 20]][sz]
			t.size_min = p2[0]; t.size_incr = fm * p2[1]; t.life_min = life.call(p2[2])
			t.size_max = t.size_min
			t.life_max = t.life_min
			_create_particles(sy, x, y, id1, col, 20)
			_create_particles(sy, x, y, id2, 0, 1)
		1, 2: # ring, ellipse
			var id: int = (_fx.ring if kind == 1 else _fx.ellipse)[sz]
			var t := _pt(id)
			t.shape = 6; t.sprite = -1
			t.alpha1 = 1.0; t.alpha2 = 0.5; t.alpha3 = 0.0
			t.size_min = 0.0; t.size_max = 0.0; t.size_wiggle = 0.0
			if kind == 2:
				t.xscale = 1.0; t.yscale = 0.5
			var incr: Array = [0.15, 0.25, 0.4] if kind == 1 else [0.2, 0.35, 0.6]
			var lifes: Array = [[10, 12], [13, 15], [18, 20]][sz]
			t.size_incr = fm * incr[sz]
			t.life_min = life.call(lifes[0]); t.life_max = life.call(lifes[1])
			_create_particles(sy, x, y, id, col, 1)
		3: # firework
			var id: int = _fx.firework[sz]
			var t := _pt(id)
			t.shape = 8; t.sprite = -1
			t.size_min = 0.1; t.size_max = 0.2; t.size_incr = 0.0; t.size_wiggle = 0.0
			t.speed_min = fm * 0.5; t.speed_incr = 0.0; t.speed_wiggle = 0.0
			t.dir_min = 0.0; t.dir_max = 360.0; t.dir_incr = 0.0; t.dir_wiggle = 0.0
			t.alpha1 = 1.0; t.alpha2 = 0.7; t.alpha3 = 0.4
			t.grav_dir = 270.0
			var p: Array = [[3.0, 15, 25, 0.1, 75], [6.0, 20, 30, 0.15, 150], [8.0, 30, 40, 0.17, 250]][sz]
			t.speed_max = fm * p[0]
			t.life_min = life.call(p[1]); t.life_max = life.call(p[2])
			t.grav_amount = p[3]
			_create_particles(sy, x, y, id, col, p[4])
		4, 5: # smoke, smokeup
			var id: int = (_fx.smoke if kind == 4 else _fx.smokeup)[sz]
			var t := _pt(id)
			t.shape = 10; t.sprite = -1
			t.size_incr = fm * -0.01; t.size_wiggle = 0.0
			t.alpha1 = 0.4; t.alpha2 = 0.2; t.alpha3 = 0.0
			if kind == 5:
				t.speed_incr = 0.0; t.speed_wiggle = 0.0
				t.dir_min = 90.0; t.dir_max = 90.0; t.dir_incr = 0.0; t.dir_wiggle = 0.0
				var sp: Array = [[3.0, 4.0], [5.0, 6.0], [6.0, 7.0]][sz]
				t.speed_min = fm * sp[0]; t.speed_max = fm * sp[1]
			var p: Array = [[0.2, 0.4, 25, 6, 9, 5], [0.4, 0.7, 30, 11, 29, 15], [0.4, 1.0, 50, 16, 59, 30]][sz]
			t.size_min = p[0]; t.size_max = p[1]
			t.life_min = life.call(p[2]); t.life_max = t.life_min
			for i in p[3]:
				var dx: int = _rnd_int(p[4]) - p[5]
				var dy: int = _rnd_int(p[4]) - p[5]
				_create_particles(sy, x + dx, y + dy, id, col, 1)
		6: # star
			var id: int = _fx.star[sz]
			var t := _pt(id)
			t.shape = 4; t.sprite = -1
			t.size_wiggle = 0.0
			t.ang_min = 0.0; t.ang_max = 360.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = false
			var p: Array = [[0.4, 0.3, -0.02, 20], [0.75, 0.75, -0.03, 25], [1.2, 1.2, -0.04, 30]][sz]
			t.size_min = p[0]; t.size_max = p[1] # small is "0.4 to 0.3", as in GM8
			t.size_incr = fm * p[2]
			t.life_min = life.call(p[3]); t.life_max = t.life_min
			_create_particles(sy, x, y, id, col, 1)
		7, 8: # spark, flare
			var id: int = (_fx.spark if kind == 7 else _fx.flare)[sz]
			var t := _pt(id)
			t.shape = 9 if kind == 7 else 8; t.sprite = -1
			t.size_wiggle = 0.0
			t.ang_min = 0.0; t.ang_max = 360.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = false
			var p: Array = [[0.4, -0.02, 20], [0.75, -0.03, 25], [1.2, -0.04, 30]][sz]
			t.size_min = p[0]; t.size_incr = p[1] / fm; t.life_min = life.call(p[2])
			t.size_max = t.size_min
			t.life_max = t.life_min
			_create_particles(sy, x, y, id, col, 1)
		9: # cloud
			var id: int = _fx.cloud[sz]
			var t := _pt(id)
			t.shape = 10; t.sprite = -1
			t.size_incr = 0.0; t.size_wiggle = 0.0
			t.xscale = 1.0; t.yscale = 0.5
			t.alpha1 = 0.0; t.alpha2 = 0.3; t.alpha3 = 0.0
			t.life_min = life.call(100); t.life_max = t.life_min
			t.size_min = [2.0, 4.0, 8.0][sz]; t.size_max = t.size_min
			_create_particles(sy, x, y, id, col, 1)
		10: # rain
			var t := _pt(_fx.rain)
			t.shape = 3; t.sprite = -1
			t.size_min = 0.2; t.size_max = 0.3; t.size_incr = 0.0; t.size_wiggle = 0.0
			t.ang_min = 0.0; t.ang_max = 0.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = true
			t.speed_min = fm * 7.0; t.speed_max = t.speed_min; t.speed_incr = 0.0; t.speed_wiggle = 0.0
			t.dir_min = 260.0; t.dir_max = 260.0; t.dir_incr = 0.0; t.dir_wiggle = 0.0
			t.alpha1 = 0.4; t.alpha2 = 0.4; t.alpha3 = 0.4
			t.life_min = roundi(0.2 / fm * _room_height); t.life_max = t.life_min
			for i in [2, 5, 9][sz]:
				_create_particles(sy, _rnd(1.2) * _room_width, _rnd_int(19) - 30, _fx.rain, col, 1)
		11: # snow
			var t := _pt(_fx.snow)
			t.shape = 13; t.sprite = -1
			t.size_min = 0.1; t.size_max = 0.25; t.size_incr = 0.0; t.size_wiggle = 0.0
			t.alpha1 = 0.6; t.alpha2 = 0.6; t.alpha3 = 0.6
			t.ang_min = 0.0; t.ang_max = 360.0; t.ang_incr = 0.0; t.ang_wiggle = 0.0; t.ang_relative = false
			t.speed_min = fm * 2.5; t.speed_max = fm * 3.0; t.speed_incr = 0.0; t.speed_wiggle = 0.0
			t.dir_min = 240.0; t.dir_max = 300.0; t.dir_incr = 0.0; t.dir_wiggle = 20.0
			t.life_min = roundi(0.5 / fm * _room_height); t.life_max = t.life_min
			for i in [1, 3, 7][sz]:
				_create_particles(sy, _rnd(1.2) * _room_width - 60.0, _rnd_int(19) - 30, _fx.snow, col, 1)

static func f_effect_create_above(s: GMInstance, kind: Variant, x: Variant, y: Variant, size: Variant, col: Variant) -> float:
	_create_effect(ri(kind), float(x), float(y), ri(size), ri(col), false)
	return 0.0

static func f_effect_create_below(s: GMInstance, kind: Variant, x: Variant, y: Variant, size: Variant, col: Variant) -> float:
	_create_effect(ri(kind), float(x), float(y), ri(size), ri(col), true)
	return 0.0

static func f_effect_clear(s: GMInstance) -> float:
	effects_clear()
	return 0.0

# ------------------------------------------------------------------ systems

static func f_part_system_create(s: GMInstance) -> float:
	var sy := PSystem.new()
	var id := _systems.find(null)
	if id < 0:
		id = _systems.size()
		_systems.append(sy)
	else:
		_systems[id] = sy
	sy.id = id
	_draw_order.append(id)
	return float(id)

static func f_part_system_destroy(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		_systems[sy.id] = null
		_draw_order.erase(sy.id)
	return 0.0

static func f_part_system_exists(s: GMInstance, ps: Variant) -> float:
	return 1.0 if _sys(ps) else 0.0

static func f_part_system_clear(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		var fresh := PSystem.new()
		fresh.id = sy.id
		_systems[sy.id] = fresh
	return 0.0

static func f_part_system_draw_order(s: GMInstance, ps: Variant, old_to_new: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.draw_old_to_new = t(old_to_new)
	return 0.0

static func f_part_system_depth(s: GMInstance, ps: Variant, d: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.depth = float(d)
	return 0.0

static func f_part_system_position(s: GMInstance, ps: Variant, x: Variant, y: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.x = float(x)
		sy.y = float(y)
	return 0.0

static func f_part_system_automatic_update(s: GMInstance, ps: Variant, v: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.auto_update = t(v)
	return 0.0

static func f_part_system_automatic_draw(s: GMInstance, ps: Variant, v: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.auto_draw = t(v)
	return 0.0

static func f_part_system_update(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		_update_system(sy)
	return 0.0

static func f_part_system_drawit(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		particle_system_draw(sy)
	return 0.0

static func f_part_particles_create(s: GMInstance, ps: Variant, x: Variant, y: Variant, pt: Variant, n: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		_create_particles(sy, float(x), float(y), ri(pt), null, ri(n))
	return 0.0

static func f_part_particles_create_color(s: GMInstance, ps: Variant, x: Variant, y: Variant, pt: Variant, col: Variant, n: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		_create_particles(sy, float(x), float(y), ri(pt), ri(col), ri(n))
	return 0.0

static func f_part_particles_clear(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.particles.clear()
	return 0.0

static func f_part_particles_count(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	return float(sy.particles.size()) if sy else 0.0

# ------------------------------------------------------------------ types

static func f_part_type_create(s: GMInstance) -> float:
	var id := _types.find(null)
	if id < 0:
		id = _types.size()
		_types.append(PType.new())
	else:
		_types[id] = PType.new()
	return float(id)

static func f_part_type_destroy(s: GMInstance, pt: Variant) -> float:
	if _pt(pt):
		_types[ri(pt)] = null
	return 0.0

static func f_part_type_exists(s: GMInstance, pt: Variant) -> float:
	return 1.0 if _pt(pt) else 0.0

static func f_part_type_clear(s: GMInstance, pt: Variant) -> float:
	if _pt(pt):
		_types[ri(pt)] = PType.new()
	return 0.0

static func f_part_type_shape(s: GMInstance, pt: Variant, shape: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.shape = ri(shape)
		p.sprite = -1
	return 0.0

static func f_part_type_sprite(s: GMInstance, pt: Variant, spr: Variant, animat: Variant, stretch: Variant, random: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.sprite = ri(spr)
		p.animat = t(animat)
		p.stretch = t(stretch)
		p.random = t(random)
	return 0.0

static func f_part_type_size(s: GMInstance, pt: Variant, lo: Variant, hi: Variant, incr: Variant, wiggle: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.size_min = float(lo); p.size_max = float(hi); p.size_incr = float(incr); p.size_wiggle = float(wiggle)
	return 0.0

static func f_part_type_scale(s: GMInstance, pt: Variant, xs: Variant, ys: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.xscale = float(xs); p.yscale = float(ys)
	return 0.0

static func f_part_type_orientation(s: GMInstance, pt: Variant, lo: Variant, hi: Variant, incr: Variant, wiggle: Variant, relative: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.ang_min = float(lo); p.ang_max = float(hi); p.ang_incr = float(incr); p.ang_wiggle = float(wiggle)
		p.ang_relative = t(relative)
	return 0.0

static func f_part_type_color1(s: GMInstance, pt: Variant, c: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["one", ri(c)]
	return 0.0

static func f_part_type_color2(s: GMInstance, pt: Variant, c1: Variant, c2: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["two", ri(c1), ri(c2)]
	return 0.0

static func f_part_type_color3(s: GMInstance, pt: Variant, c1: Variant, c2: Variant, c3: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["three", ri(c1), ri(c2), ri(c3)]
	return 0.0

static func f_part_type_color_mix(s: GMInstance, pt: Variant, c1: Variant, c2: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["mix", ri(c1), ri(c2)]
	return 0.0

static func f_part_type_color_rgb(s: GMInstance, pt: Variant, r1: Variant, r2: Variant, g1: Variant, g2: Variant, b1: Variant, b2: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["rgb", ri(r1), ri(r2), ri(g1), ri(g2), ri(b1), ri(b2)]
	return 0.0

static func f_part_type_color_hsv(s: GMInstance, pt: Variant, h1: Variant, h2: Variant, s1: Variant, s2: Variant, v1: Variant, v2: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.colour = ["hsv", ri(h1), ri(h2), ri(s1), ri(s2), ri(v1), ri(v2)]
	return 0.0

static func f_part_type_alpha1(s: GMInstance, pt: Variant, a: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.alpha1 = float(a); p.alpha2 = float(a); p.alpha3 = float(a)
	return 0.0

static func f_part_type_alpha2(s: GMInstance, pt: Variant, a1: Variant, a2: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.alpha1 = float(a1); p.alpha2 = (float(a1) + float(a2)) / 2.0; p.alpha3 = float(a2)
	return 0.0

static func f_part_type_alpha3(s: GMInstance, pt: Variant, a1: Variant, a2: Variant, a3: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.alpha1 = float(a1); p.alpha2 = float(a2); p.alpha3 = float(a3)
	return 0.0

static func f_part_type_blend(s: GMInstance, pt: Variant, additive: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.additive = t(additive) # stored; drawn with normal blending for now
	return 0.0

static func f_part_type_life(s: GMInstance, pt: Variant, lo: Variant, hi: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.life_min = ri(lo); p.life_max = ri(hi)
	return 0.0

static func f_part_type_step(s: GMInstance, pt: Variant, n: Variant, kind: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.step_number = ri(n); p.step_type = ri(kind)
	return 0.0

static func f_part_type_death(s: GMInstance, pt: Variant, n: Variant, kind: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.death_number = ri(n); p.death_type = ri(kind)
	return 0.0

static func f_part_type_speed(s: GMInstance, pt: Variant, lo: Variant, hi: Variant, incr: Variant, wiggle: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.speed_min = float(lo); p.speed_max = float(hi); p.speed_incr = float(incr); p.speed_wiggle = float(wiggle)
	return 0.0

static func f_part_type_direction(s: GMInstance, pt: Variant, lo: Variant, hi: Variant, incr: Variant, wiggle: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.dir_min = float(lo); p.dir_max = float(hi); p.dir_incr = float(incr); p.dir_wiggle = float(wiggle)
	return 0.0

static func f_part_type_gravity(s: GMInstance, pt: Variant, amount: Variant, dir: Variant) -> float:
	var p := _pt(pt)
	if p:
		p.grav_amount = float(amount); p.grav_dir = float(dir)
	return 0.0

# ------------------------------------------------------------------ emitters

static func f_part_emitter_create(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy == null:
		return -1.0
	var id := sy.emitters.find(null)
	if id < 0:
		id = sy.emitters.size()
		sy.emitters.append(Emitter.new())
	else:
		sy.emitters[id] = Emitter.new()
	return float(id)

static func f_part_emitter_destroy(s: GMInstance, ps: Variant, pe: Variant) -> float:
	if _emitter(ps, pe):
		_sys(ps).emitters[ri(pe)] = null
	return 0.0

static func f_part_emitter_destroy_all(s: GMInstance, ps: Variant) -> float:
	var sy := _sys(ps)
	if sy:
		sy.emitters.clear()
	return 0.0

static func f_part_emitter_exists(s: GMInstance, ps: Variant, pe: Variant) -> float:
	return 1.0 if _emitter(ps, pe) else 0.0

static func f_part_emitter_clear(s: GMInstance, ps: Variant, pe: Variant) -> float:
	if _emitter(ps, pe):
		_sys(ps).emitters[ri(pe)] = Emitter.new()
	return 0.0

static func f_part_emitter_region(s: GMInstance, ps: Variant, pe: Variant, x1: Variant, x2: Variant, y1: Variant, y2: Variant, shape: Variant, distr: Variant) -> float:
	var em := _emitter(ps, pe)
	if em:
		em.xmin = float(x1); em.xmax = float(x2); em.ymin = float(y1); em.ymax = float(y2)
		em.shape = ri(shape) if ri(shape) in [1, 2, 3] else 0
		em.distribution = ri(distr) if ri(distr) in [1, 2] else 0
	return 0.0

static func f_part_emitter_burst(s: GMInstance, ps: Variant, pe: Variant, pt: Variant, n: Variant) -> float:
	var em := _emitter(ps, pe)
	if em:
		_burst(_sys(ps), em, ri(pt), ri(n))
	return 0.0

static func f_part_emitter_stream(s: GMInstance, ps: Variant, pe: Variant, pt: Variant, n: Variant) -> float:
	var em := _emitter(ps, pe)
	if em:
		em.ptype = ri(pt)
		em.number = ri(n)
	return 0.0
