## Particle systems and effects (part_*, effect_*).
## TODO(port): parameters are stored but particles are not simulated/drawn yet; the real
## implementation will port OpenGMK's particle.rs (shapes come from its particles.dat).
class_name GMLibFx
extends GMLibSys

static var _systems: Dictionary = {}
static var _types: Dictionary = {}
static var _emitters: Dictionary = {}
static var _next_ps := 0
static var _next_pt := 0
static var _next_pe := 0

class PSystem:
	var id := 0
	var depth := 0.0

static func particle_systems_by_depth() -> Array:
	var out := _systems.values()
	out.sort_custom(func(a, b): return a.depth > b.depth)
	return out

static func particle_system_draw(_ps) -> void:
	pass

static func particles_auto_update() -> void:
	pass

static func effects_clear() -> void:
	pass

static func f_effect_clear(s: GMInstance) -> float:
	effects_clear()
	return 0.0

static func f_effect_create_above(s: GMInstance, _kind: Variant, _x: Variant, _y: Variant, _size: Variant, _col: Variant) -> float:
	return 0.0

static func f_effect_create_below(s: GMInstance, _kind: Variant, _x: Variant, _y: Variant, _size: Variant, _col: Variant) -> float:
	return 0.0

static func f_part_system_create(s: GMInstance) -> float:
	var ps := PSystem.new()
	ps.id = _next_ps
	_next_ps += 1
	_systems[ps.id] = ps
	return float(ps.id)

static func f_part_system_destroy(s: GMInstance, ps: Variant) -> float:
	_systems.erase(ri(ps))
	return 0.0

static func f_part_system_depth(s: GMInstance, ps: Variant, d: Variant) -> float:
	var sy = _systems.get(ri(ps))
	if sy:
		sy.depth = float(d)
	return 0.0

static func f_part_type_create(s: GMInstance) -> float:
	var id := _next_pt
	_next_pt += 1
	_types[id] = {}
	return float(id)

static func _pt_set(pt: Variant, key: String, vals: Array) -> float:
	var t = _types.get(ri(pt))
	if t != null:
		t[key] = vals
	return 0.0

static func f_part_type_shape(s: GMInstance, pt: Variant, a: Variant) -> float:
	return _pt_set(pt, "shape", [a])
static func f_part_type_sprite(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant, d: Variant) -> float:
	return _pt_set(pt, "sprite", [a, b, c, d])
static func f_part_type_size(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant, d: Variant) -> float:
	return _pt_set(pt, "size", [a, b, c, d])
static func f_part_type_scale(s: GMInstance, pt: Variant, a: Variant, b: Variant) -> float:
	return _pt_set(pt, "scale", [a, b])
static func f_part_type_orientation(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant, d: Variant, e: Variant) -> float:
	return _pt_set(pt, "orientation", [a, b, c, d, e])
static func f_part_type_color1(s: GMInstance, pt: Variant, a: Variant) -> float:
	return _pt_set(pt, "color", [a])
static func f_part_type_color2(s: GMInstance, pt: Variant, a: Variant, b: Variant) -> float:
	return _pt_set(pt, "color", [a, b])
static func f_part_type_color3(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant) -> float:
	return _pt_set(pt, "color", [a, b, c])
static func f_part_type_alpha1(s: GMInstance, pt: Variant, a: Variant) -> float:
	return _pt_set(pt, "alpha", [a])
static func f_part_type_alpha2(s: GMInstance, pt: Variant, a: Variant, b: Variant) -> float:
	return _pt_set(pt, "alpha", [a, b])
static func f_part_type_life(s: GMInstance, pt: Variant, a: Variant, b: Variant) -> float:
	return _pt_set(pt, "life", [a, b])
static func f_part_type_speed(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant, d: Variant) -> float:
	return _pt_set(pt, "speed", [a, b, c, d])
static func f_part_type_direction(s: GMInstance, pt: Variant, a: Variant, b: Variant, c: Variant, d: Variant) -> float:
	return _pt_set(pt, "direction", [a, b, c, d])

static func f_part_emitter_create(s: GMInstance, ps: Variant) -> float:
	var id := _next_pe
	_next_pe += 1
	_emitters[id] = {"ps": ri(ps)}
	return float(id)

static func f_part_emitter_destroy(s: GMInstance, _ps: Variant, pe: Variant) -> float:
	_emitters.erase(ri(pe))
	return 0.0

static func f_part_emitter_destroy_all(s: GMInstance, ps: Variant) -> float:
	for k in _emitters.keys():
		if _emitters[k].ps == ri(ps):
			_emitters.erase(k)
	return 0.0

static func f_part_emitter_region(s: GMInstance, _ps: Variant, pe: Variant, x1: Variant, x2: Variant, y1: Variant, y2: Variant, shape: Variant, distr: Variant) -> float:
	var e = _emitters.get(ri(pe))
	if e != null:
		e.region = [x1, x2, y1, y2, shape, distr]
	return 0.0

static func f_part_emitter_burst(s: GMInstance, _ps: Variant, _pe: Variant, _pt: Variant, _n: Variant) -> float:
	return 0.0
