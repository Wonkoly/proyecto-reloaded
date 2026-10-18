## Instances, collisions, motion and rooms (ports of the matching OpenGMK kernel functions).
class_name GMLibInst
extends GMLibDraw

# ------------------------------------------------------------------ collision core

static func _mask_sprite(inst: GMInstance) -> GMSprite:
	return GMAssets.sprite(inst.mask_index if inst.mask_index >= 0.0 else inst.sprite_index)

static func check_collision(a: GMInstance, b: GMInstance) -> bool:
	if a == b:
		return false
	var s1 := _mask_sprite(a)
	var s2 := _mask_sprite(b)
	a.update_bbox()
	b.update_bbox()
	var ab: Array = a._bbox
	var bb: Array = b._bbox
	if ab[2] < bb[0] or bb[2] < ab[0] or ab[3] < bb[1] or bb[3] < ab[1]:
		return false
	if s1 == null or s2 == null:
		return false
	var c1 := s1.collider(a.image_index)
	var c2 := s2.collider(b.image_index)
	if c1.is_empty() or c2.is_empty():
		return false
	var x1 := ri(a.x)
	var y1 := ri(a.y)
	var x2 := ri(b.x)
	var y2 := ri(b.y)
	var r1 := deg_to_rad(a.image_angle)
	var r2 := deg_to_rad(b.image_angle)
	var sn1 := sin(r1)
	var cs1 := cos(r1)
	var sn2 := sin(r2)
	var cs2 := cos(r2)
	var top: int = maxi(ab[1], bb[1])
	var bottom: int = mini(ab[3], bb[3])
	var left: int = maxi(ab[0], bb[0])
	var right: int = mini(ab[2], bb[2])
	# Fast path: both masks are solid rectangles and unrotated -> the bbox overlap is the answer.
	if c1.full and c2.full and r1 == 0.0 and r2 == 0.0:
		return true
	for yy in range(top, bottom + 1):
		for xx in range(left, right + 1):
			if GMSprite.point_in_collider(c1, xx, yy, x1, y1, s1.origin_x, s1.origin_y, a.image_xscale, a.image_yscale, sn1, cs1) \
					and GMSprite.point_in_collider(c2, xx, yy, x2, y2, s2.origin_x, s2.origin_y, b.image_xscale, b.image_yscale, sn2, cs2):
				return true
	return false

static func check_collision_point(inst: GMInstance, x: float, y: float, precise: bool) -> bool:
	inst.update_bbox()
	var bb: Array = inst._bbox
	if bb[2] < x or x < bb[0] or bb[3] < y or y < bb[1]:
		return false
	if not precise:
		return true
	var spr := _mask_sprite(inst)
	if spr == null:
		return false
	var c := spr.collider(inst.image_index)
	if c.is_empty():
		return false
	var r := deg_to_rad(inst.image_angle)
	return GMSprite.point_in_collider(c, ri(x), ri(y), ri(inst.x), ri(inst.y), spr.origin_x, spr.origin_y,
		inst.image_xscale, inst.image_yscale, sin(r), cos(r))

static func check_collision_line(inst: GMInstance, x1: float, y1: float, x2: float, y2: float, precise: bool) -> bool:
	inst.update_bbox()
	var bl := float(inst._bbox[0])
	var bt := float(inst._bbox[1])
	var br := float(inst._bbox[2])
	var bb := float(inst._bbox[3])
	if br + 1.0 <= minf(x1, x2) or maxf(x1, x2) < bl or bb + 1.0 <= minf(y1, y2) or maxf(y1, y2) < bt:
		return false
	if x2 < x1:
		var tx := x1; x1 = x2; x2 = tx
		var ty := y1; y1 = y2; y2 = ty
	if x1 < bl:
		y1 = (y2 - y1) * (bl - x1) / (x2 - x1) + y1
		x1 = bl
	if x2 > br + 1.0:
		var nx2 := br + 1.0
		y2 = (y2 - y1) * (nx2 - x2) / (x2 - x1) + y2
		x2 = nx2
	if (bt > y1 and bt > y2) or (y1 >= bb + 1.0 and y2 >= bb + 1.0):
		return false
	if not precise:
		return true
	var spr := _mask_sprite(inst)
	if spr == null:
		return false
	var c := spr.collider(inst.image_index)
	if c.is_empty():
		return false
	var ix := float(ri(inst.x))
	var iy := float(ri(inst.y))
	var r := deg_to_rad(inst.image_angle)
	var sn := sin(r)
	var cs := cos(r)
	var ax := ri(x1)
	var ay := ri(y1)
	var bx := ri(x2)
	var by := ri(y2)
	var vert := absi(bx - ax) < absi(by - ay)
	if vert and by < ay:
		var t1 := ax; ax = bx; bx = t1
		var t2 := ay; ay = by; by = t2
	var count := (by - ay if vert else bx - ax) + 1
	for i in count:
		var px: float
		var py: float
		if count == 1:
			px = ax
			py = ay
		elif vert:
			px = ax + i * float(bx - ax) / float(by - ay)
			py = ay + i
		else:
			px = ax + i
			py = ay + i * float(by - ay) / float(bx - ax)
		px -= ix
		py -= iy
		var rx := px * cs - py * sn
		var ry := px * sn + py * cs
		var mx := int(spr.origin_x + floorf(rx / inst.image_xscale))
		var my := int(spr.origin_y + floorf(ry / inst.image_yscale))
		if mx >= c.left and my >= c.top and mx <= c.right and my <= c.bottom:
			if c.full:
				return true
			var idx: int = my * c.w + mx
			if idx >= 0 and idx < c.mask.size() and c.mask[idx] != 0:
				return true
	return false

# ------------------------------------------------------------------ collision grids
# Geometric queries against an object would test every instance of it (a city has 700+ water
# tiles, and obj_pared has 900 descendant objects): each queried object gets a grid of its
# instances' bounding boxes instead. Instances that move, appear or disappear are marked dirty
# (GMCore.inst_changed) and re-placed on the next query. Results are unchanged; candidates come
# back in identity (insertion) order.

const GRID_CELL := 64

class Grid:
	var cells: Dictionary = {} # Vector2i -> Array[GMInstance]
	var big: Array = []        # instances spanning too many cells
	var where: Dictionary = {} # GMInstance -> Array of cell keys, or [] when in `big`
	var dirty: Dictionary = {} # GMInstance -> true

static var _grids: Dictionary = {} # object index -> Grid

static func _grid_insert(g: Grid, i: GMInstance) -> void:
	i.update_bbox()
	var bb: Array = i._bbox
	if bb[0] == -100000:
		return # no sprite or mask: never collides
	var cx0: int = floori(bb[0] / float(GRID_CELL))
	var cy0: int = floori(bb[1] / float(GRID_CELL))
	var cx1: int = floori(bb[2] / float(GRID_CELL))
	var cy1: int = floori(bb[3] / float(GRID_CELL))
	if (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > 16:
		g.big.append(i)
		g.where[i] = []
		return
	var keys := []
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cy)
			keys.append(key)
			if g.cells.has(key):
				g.cells[key].append(i)
			else:
				g.cells[key] = [i]
	g.where[i] = keys

static func _grid_remove(g: Grid, i: GMInstance) -> void:
	var keys = g.where.get(i)
	if keys == null:
		return
	g.where.erase(i)
	if keys.is_empty():
		g.big.erase(i)
	for key in keys:
		g.cells[key].erase(i)

static func _grid(k: int) -> Grid:
	var g: Grid = _grids.get(k)
	var t0 := Time.get_ticks_usec()
	suspend_changes += 1 # update_bbox here isn't a change
	if g == null:
		g = Grid.new()
		_grids[k] = g
		for i: GMInstance in identity_list(k):
			_grid_insert(g, i)
	elif not g.dirty.is_empty():
		for i: GMInstance in g.dirty:
			_grid_remove(g, i)
			if not i.gone and i.obj and i.obj.ancestors.has(k):
				_grid_insert(g, i)
		g.dirty.clear()
	suspend_changes -= 1
	if GMPerf.enabled:
		GMPerf.add_obj("grid", k, Time.get_ticks_usec() - t0)
	return g

## Instances of object `k` whose bbox may touch the rectangle, in identity order.
static func _grid_candidates(k: int, l: float, t: float, r: float, b: float) -> Array:
	var g := _grid(k)
	var cx0 := floori(minf(l, r) / GRID_CELL)
	var cx1 := floori(maxf(l, r) / GRID_CELL)
	var cy0 := floori(minf(t, b) / GRID_CELL)
	var cy1 := floori(maxf(t, b) / GRID_CELL)
	if (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > 256:
		return identity_list(k) # huge area: just test everything
	var out: Array = g.big.duplicate()
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var c = g.cells.get(Vector2i(cx, cy))
			if c != null:
				out.append_array(c)
	if out.size() > 1:
		out.sort_custom(func(x, y): return x.seq < y.seq)
		var uniq := [out[0]]
		for n in range(1, out.size()):
			if out[n] != out[n - 1]:
				uniq.append(out[n])
		return uniq
	return out

## Instances of `obj` (all / object / instance id) that may touch the rectangle, in identity order.
static func _area_list(obj: Variant, l: float, t: float, r: float, b: float) -> Array:
	var k := ri(obj)
	if k == -3:
		return _active_snapshot()
	if k < 0:
		return []
	if k < 100000:
		return _grid_candidates(k, l, t, r, b)
	var i = by_id.get(k)
	return [i] if i and not i.gone else []

## The caller's bbox as if it stood at x, y (it is moved there and back, without counting as a change).
static func _bbox_at(s: GMInstance, x: float, y: float) -> Array:
	var ox := s.x
	var oy := s.y
	suspend_changes += 1
	s.x = x
	s.y = y
	s.update_bbox()
	var bb: Array = s._bbox.duplicate()
	s.x = ox
	s.y = oy
	suspend_changes -= 1
	return bb

## First instance of `obj` (all / object / instance id) satisfying `pred`.
static func find_instance_with(obj: Variant, pred: Callable) -> GMInstance:
	var k := ri(obj)
	var lst: Array
	if k == -3:
		lst = _active_snapshot()
	elif k < 0:
		return null
	elif k < 100000:
		lst = identity_list(k)
	else:
		var i = by_id.get(k)
		lst = [i] if i and not i.gone else []
	for i in lst:
		if pred.call(i):
			return i
	return null

static func _moved_check(s: GMInstance, x: float, y: float, f: Callable) -> Variant:
	var ox := s.x
	var oy := s.y
	suspend_changes += 1 # a temporary move, undone below
	s.x = x
	s.y = y
	var r = f.call()
	s.x = ox
	s.y = oy
	suspend_changes -= 1
	return r

# ------------------------------------------------------------------ collision functions

static func f_place_meeting(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	if ri(obj) == -1:
		return 0.0
	return 1.0 if _place_find(s, float(x), float(y), obj, false) else 0.0

## First instance of `obj` colliding with `s` placed at x, y.
static func _place_find(s: GMInstance, x: float, y: float, obj: Variant, not_self: bool) -> GMInstance:
	var bb := _bbox_at(s, x, y)
	var cands := _area_list(obj, bb[0], bb[1], bb[2], bb[3])
	if cands.is_empty():
		return null
	var ox := s.x
	var oy := s.y
	suspend_changes += 1
	s.x = x
	s.y = y
	var found: GMInstance = null
	for i: GMInstance in cands:
		if not i.gone and (not not_self or i != s) and check_collision(s, i):
			found = i
			break
	s.x = ox
	s.y = oy
	suspend_changes -= 1
	return found

static func f_place_free(s: GMInstance, x: Variant, y: Variant) -> float:
	var hit = _moved_check(s, x, y, func():
		for i in _active_snapshot():
			if i.solid and check_collision(s, i):
				return true
		return false)
	return 0.0 if hit else 1.0

static func f_place_empty(s: GMInstance, x: Variant, y: Variant) -> float:
	var hit = _moved_check(s, x, y, func():
		for i in _active_snapshot():
			if check_collision(s, i):
				return true
		return false)
	return 0.0 if hit else 1.0

static func f_instance_place(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	var found := _place_find(s, float(x), float(y), obj, true)
	return found.id if found else -4.0

static func f_position_meeting(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	var k := ri(obj)
	if k == -1:
		return 1.0 if check_collision_point(s, x, y, true) else 0.0
	return 1.0 if _point_find(float(x), float(y), obj) else 0.0

static func _point_find(x: float, y: float, obj: Variant) -> GMInstance:
	for i: GMInstance in _area_list(obj, x, y, x, y):
		if not i.gone and check_collision_point(i, x, y, true):
			return i
	return null

static func f_instance_position(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	var found := _point_find(float(x), float(y), obj)
	return found.id if found else -4.0

static func f_collision_line(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant, obj: Variant, prec: Variant, notme: Variant) -> float:
	var excl := t(notme)
	var precise := t(prec)
	for i: GMInstance in _area_list(obj, float(x1), float(y1), float(x2), float(y2)):
		if not i.gone and (not excl or i != s) and check_collision_line(i, x1, y1, x2, y2, precise):
			return i.id
	return -4.0

static func _inst_distance(a: GMInstance, b: GMInstance) -> float:
	a.update_bbox()
	b.update_bbox()
	var dx := 0
	var dy := 0
	if a._bbox[0] > b._bbox[2]:
		dx = a._bbox[0] - b._bbox[2]
	elif b._bbox[0] > a._bbox[2]:
		dx = b._bbox[0] - a._bbox[2]
	if a._bbox[1] > b._bbox[3]:
		dy = a._bbox[1] - b._bbox[3]
	elif b._bbox[1] > a._bbox[3]:
		dy = b._bbox[1] - a._bbox[3]
	return sqrt(float(dx * dx + dy * dy))

static func f_distance_to_object(s: GMInstance, obj: Variant) -> float:
	var best := 1000000.0
	var k := ri(obj)
	var lst: Array = with_iter(s, s, obj) if k != -1 else [s]
	for i in lst:
		if i != s or k == -1:
			best = minf(best, _inst_distance(s, i))
	return best

static func f_distance_to_point(s: GMInstance, x: Variant, y: Variant) -> float:
	s.update_bbox()
	var dx := 0.0
	var dy := 0.0
	if x > s._bbox[2]:
		dx = x - s._bbox[2]
	elif x < s._bbox[0]:
		dx = x - s._bbox[0]
	if y > s._bbox[3]:
		dy = y - s._bbox[3]
	elif y < s._bbox[1]:
		dy = y - s._bbox[1]
	return sqrt(dx * dx + dy * dy)

# ------------------------------------------------------------------ instance functions

static func f_instance_create(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	var inst := create_instance(x, y, ri(obj))
	run_event(inst, "create", inst)
	return inst.id

static func f_instance_destroy(s: GMInstance) -> float:
	destroy_instance(s)
	return 0.0

static func f_instance_exists(s: GMInstance, obj: Variant) -> float:
	var k := ri(obj)
	match k:
		-1: return 0.0 if s.gone else 1.0
		-2: return 1.0
		-3: return 1.0 if not _active_snapshot().is_empty() else 0.0
	if k < 0:
		return 0.0
	if k <= 100000:
		var o := GMAssets.object(k)
		if o == null:
			return 0.0
		for c in o.children:
			for i: GMInstance in by_object.get(c, []):
				if not i.gone:
					return 1.0
		return 0.0
	var i = by_id.get(k)
	return 1.0 if i and not i.gone else 0.0

static func f_instance_number(s: GMInstance, obj: Variant) -> float:
	var k := ri(obj)
	if k == -1 or k == -2:
		return 1.0
	if k == -3:
		return float(_active_snapshot().size())
	if k < 0:
		return 0.0
	return float(identity_list(k).size())

static func f_instance_find(s: GMInstance, obj: Variant, n: Variant) -> float:
	var k := ri(obj)
	var idx := ri(n)
	if idx < 0:
		return -4.0
	var lst: Array
	if k == -3:
		lst = _active_snapshot()
	elif k < 0:
		return -4.0
	elif k < 100000:
		lst = identity_list(k)
	else:
		var i = by_id.get(k)
		return i.id if i and not i.gone and idx == 0 else -4.0
	return lst[idx].id if idx < lst.size() else -4.0

static func f_instance_nearest(s: GMInstance, x: Variant, y: Variant, obj: Variant) -> float:
	var best: GMInstance = null
	var bd := 10000000000.0
	for i in with_iter(s, s, obj):
		var dx: float = i.x - x
		var dy: float = i.y - y
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = i
	return best.id if best else -4.0

static func f_instance_change(s: GMInstance, obj: Variant, perf: Variant) -> float:
	if t(perf):
		run_event(s, "destroy", s)
	var o := GMAssets.object(ri(obj))
	if o == null:
		return 0.0
	var old_k := int(s.object_index)
	by_object[old_k].erase(s)
	s.object_index = float(o.index)
	s.obj = o
	s.sprite_index = o.sprite_index
	s.mask_index = o.mask_index
	s.depth = o.depth
	s.solid = o.solid
	s.visible = o.visible
	s.persistent = o.persistent
	if not by_object.has(o.index):
		by_object[o.index] = []
	by_object[o.index].append(s)
	presence_ver += 1
	next_instance_id += 1
	if t(perf):
		run_event(s, "create", s)
	return 0.0

static func _set_active(s: GMInstance, o: GMInstance, obj: Variant, active: bool) -> void:
	var k := ri(obj)
	var lst: Array
	match k:
		-1: lst = [s]
		-2: lst = [o]
		-3: lst = instances.duplicate()
		_:
			if k >= 100000:
				var i = by_id.get(k)
				lst = [i] if i else []
			elif k >= 0:
				var fam := GMAssets.object(k)
				lst = instances.filter(func(i): return fam and fam.children.has(int(i.object_index)))
	for i: GMInstance in lst:
		if i == null or i.destroyed:
			continue
		i.deactivated = not active
		i.gone = not active

static func f_instance_deactivate_object(s: GMInstance, obj: Variant) -> float:
	_set_active(s, s, obj, false)
	return 0.0

static func f_instance_activate_object(s: GMInstance, obj: Variant) -> float:
	_set_active(s, s, obj, true)
	return 0.0

# ------------------------------------------------------------------ motion

static func process_speeds() -> void:
	# No events run here, so the order doesn't matter and no snapshot is needed
	# (keys() is a copy, so erasing while iterating is fine).
	for inst: GMInstance in moving.keys():
		if inst.gone:
			continue
		var fr := inst.friction
		if fr == 0.0 and inst.gravity == 0.0 and inst._hspeed == 0.0 and inst._vspeed == 0.0 \
				and inst.path_index < 0.0:
			inst.motion_idle = true # nothing to do here or in the frame's motion pass
			moving.erase(inst)
			continue
		if fr != 0.0:
			var sp := inst.speed
			if sp >= 0.0:
				if fr > sp:
					inst.speed = 0.0
				elif sp != 0.0:
					inst.speed = sp - fr
			else:
				if fr > -sp:
					inst.speed = 0.0
				elif sp != 0.0:
					inst.speed = sp + fr
		if inst.gravity != 0.0:
			var gd := deg_to_rad(inst.gravity_direction)
			inst.set_hvspeed(inst.hspeed + cos(gd) * inst.gravity, inst.vspeed - sin(gd) * inst.gravity)

## Applies hspeed/vspeed and advances paths. Returns true if the path ended.
static func apply_motion(inst: GMInstance) -> bool:
	if inst.hspeed != 0.0 or inst.vspeed != 0.0:
		inst.x += inst.hspeed
		inst.y += inst.vspeed
	return GM.path_advance(inst)

static func f_move_towards_point(s: GMInstance, x: Variant, y: Variant, sp: Variant) -> float:
	s.set_speed_direction(sp, rad_to_deg(atan2(s.y - float(y), float(x) - s.x)))
	return 0.0

static func _collides(s: GMInstance, solids_only: bool) -> bool:
	for i: GMInstance in _active_snapshot():
		if (not solids_only or i.solid) and check_collision(s, i):
			return true
	return false

## GM8 bouncing (OpenGMK's movement.rs: bounce and bounce_advanced).
static func _bounce(s: GMInstance, solids_only: bool, advanced: bool) -> void:
	var hit := false
	if _collides(s, solids_only):
		s.x = s.xprevious
		s.y = s.yprevious
		hit = true
	var ox := s.x
	var oy := s.y
	if advanced:
		var start := float(roundi(s.direction / 10.0) * 10)
		var sides := []
		for step in [-10.0, 10.0]:
			var side := start
			for i in 36:
				side += step
				s.x = ox + s.speed * cos(deg_to_rad(side))
				s.y = oy - s.speed * sin(deg_to_rad(side))
				if not _collides(s, solids_only):
					break
				hit = true
			sides.append(side)
		if hit:
			s.direction = sides[0] + sides[1] + 180.0 - start
	else:
		s.x = ox + s.hspeed
		var bx := _collides(s, solids_only)
		s.x = ox
		s.y = oy + s.vspeed
		var by := _collides(s, solids_only)
		if bx:
			s.hspeed = -s.hspeed
		if by:
			s.vspeed = -s.vspeed
		if not bx and not by:
			s.x = ox + s.hspeed
			if _collides(s, solids_only):
				var h := -s.hspeed
				var v := -s.vspeed
				s.hspeed = h
				s.vspeed = v
	s.x = ox
	s.y = oy

static func f_move_bounce_all(s: GMInstance, adv: Variant) -> float:
	_bounce(s, false, t(adv))
	return 0.0

static func f_move_bounce_solid(s: GMInstance, adv: Variant) -> float:
	_bounce(s, true, t(adv))
	return 0.0

## OpenGMK's pathfinding::potential_step with GM8's default mp_potential_settings (30, 10, 3, true).
static func f_mp_potential_step_object(s: GMInstance, gx: Variant, gy: Variant, sp: Variant, obj: Variant) -> float:
	var x := float(gx)
	var y := float(gy)
	var step := float(sp)
	var ox := s.x
	var oy := s.y
	if ox == x and oy == y:
		return 1.0
	var coll := func() -> bool: return f_place_meeting(s, s.x, s.y, obj) != 0.0
	var try_move := func(tx: float, ty: float) -> bool:
		s.x = tx
		s.y = ty
		if coll.call():
			s.x = ox
			s.y = oy
			return false
		return true
	var direction := fposmod(rad_to_deg(atan2(oy - y, x - ox)), 360.0)
	if Vector2(ox - x, oy - y).length() <= step:
		if try_move.call(x, y):
			s._direction = direction
			return 1.0
		return 0.0
	var diff := 0.0
	while true:
		var dir := fposmod(direction - diff, 360.0)
		var change := fposmod(dir - s.direction, 360.0)
		if change <= 30.0 or change >= 330.0:
			var xs := step * cos(deg_to_rad(dir))
			var ys := -step * sin(deg_to_rad(dir))
			if try_move.call(ox + xs * 3.0, oy + ys * 3.0):
				if try_move.call(ox + xs, oy + ys):
					s._direction = dir
					return 0.0
				s.x = ox
				s.y = oy
		# 0, 10, -10, 20, -20, ... up to 170
		if diff <= 0.0:
			diff = -diff + 10.0
			if diff >= 180.0:
				break
		else:
			diff = -diff
	s._direction = s.direction + 30.0
	return 0.0

static func run_bound_events() -> void:
	# Outside room (other_0) and boundary (other_1) events.
	for ev in ["other_0", "other_1"]:
		for oi in present_holders(ev):
			for inst: GMInstance in object_list(oi):
				inst.update_bbox()
				var bb: Array = inst._bbox
				if ev == "other_0":
					if bb[2] < 0 or bb[0] > _room_width or bb[3] < 0 or bb[1] > _room_height:
						run_event(inst, ev, inst)
				else:
					if bb[0] < 0 or bb[2] > _room_width or bb[1] < 0 or bb[3] > _room_height:
						run_event(inst, ev, inst)

static func run_collisions() -> void:
	for ev in event_holders:
		if not ev.begins_with("collision_"):
			continue
		var target := int(ev.substr(10))
		var tobj := GMAssets.object(target)
		if tobj == null:
			continue
		for oi in present_holders(ev):
			if GMDev.noclip and oi == 14 and target == 1: # dev `atravesar`: obj_Prota vs obj_pared
				continue
			var _pt0 := Time.get_ticks_usec()
			for a: GMInstance in object_list(oi):
				if a.gone:
					continue
				a.update_bbox()
				var ab: Array = a._bbox
				for b: GMInstance in _grid_candidates(target, ab[0], ab[1], ab[2], ab[3]):
					if a.gone:
						break
					if b.gone or not check_collision(a, b):
						continue
					if a.solid or b.solid:
						for i in [a, b]:
							i.x = i.xprevious
							i.y = i.yprevious
					run_event(a, ev, b)
					var back := "collision_%d" % oi
					if b.obj and b.obj.events.has(back) and not event_holders.get(back, []).has(int(b.object_index)):
						run_event(b, back, a)
					if a.solid or b.solid:
						apply_motion(a)
						apply_motion(b)
						if not a.gone and not b.gone and check_collision(a, b):
							for i in [a, b]:
								i.x = i.xprevious
								i.y = i.yprevious
			if GMPerf.enabled:
				GMPerf.add_obj(ev, oi, Time.get_ticks_usec() - _pt0)

# ------------------------------------------------------------------ rooms

static func f_room_goto(s: GMInstance, r: Variant) -> float:
	scene_change = ["room", ri(r)]
	return 0.0

static func f_room_restart(s: GMInstance) -> float:
	scene_change = ["room", int(room)]
	return 0.0

static func f_game_restart(s: GMInstance) -> float:
	scene_change = ["restart"]
	return 0.0

static func f_game_end(s: GMInstance) -> float:
	scene_change = ["end"]
	return 0.0

static func f_room_set_code(s: GMInstance, r: Variant, code: Variant) -> float:
	room_code_override[ri(r)] = str(code)
	return 0.0

static func f_room_set_persistent(s: GMInstance, r: Variant, val: Variant) -> float:
	var k := ri(r)
	if k == int(room):
		_room_persistent = t(val)
	else:
		var rd := GMAssets.room(k)
		if not rd.is_empty():
			rd.persistent = t(val)
	return 0.0

static func f_object_set_parent(s: GMInstance, obj: Variant, parent: Variant) -> float:
	var o := GMAssets.object(ri(obj))
	if o == null:
		return 0.0
	o.parent = ri(parent)
	# Rebuild inheritance-derived tables for everyone.
	for oo: GMObject in GMAssets.objects:
		if oo == null:
			continue
		oo.ancestors = []
		oo.events = {}
	for oo: GMObject in GMAssets.objects:
		if oo == null:
			continue
		var p := oo.index
		var guard := 0
		while p >= 0 and guard < 64:
			oo.ancestors.append(p)
			var po := GMAssets.object(p)
			p = po.parent if po else -1
			guard += 1
		for a in range(oo.ancestors.size() - 1, -1, -1):
			var ao := GMAssets.object(oo.ancestors[a])
			for ev in ao.own_events:
				oo.events[ev] = ao.own_events[ev]
	for oo: GMObject in GMAssets.objects:
		if oo != null:
			oo.children = GMAssets._descendants(oo.index)
	build_event_holders()
	return 0.0

static func f_object_get_parent(s: GMInstance, obj: Variant) -> float:
	var o := GMAssets.object(ri(obj))
	return float(o.parent) if o else -1.0

const EV_NAMES := ["create", "destroy", "alarm", "step", "collision", "keyboard", "mouse", "other", "draw",
	"keypress", "keyrelease", "trigger"]

static func _event_key(ev: int, sub: int) -> String:
	match ev:
		0, 1, 8:
			return EV_NAMES[ev]
		3:
			return ["step_normal", "step_begin", "step_end"][sub] if sub >= 0 and sub < 3 else "step_normal"
	return "%s_%d" % [EV_NAMES[ev], sub]

static func f_object_event_clear(s: GMInstance, obj: Variant, ev: Variant, sub: Variant) -> float:
	var o := GMAssets.object(ri(obj))
	if o == null:
		return 0.0
	var key := _event_key(ri(ev), ri(sub))
	o.own_events.erase(key)
	o.dynamic_events.erase(key)
	for oo: GMObject in GMAssets.objects:
		if oo and oo.ancestors.has(o.index):
			oo.events.erase(key)
			for a in range(oo.ancestors.size() - 1, -1, -1):
				var ao := GMAssets.object(oo.ancestors[a])
				if ao.own_events.has(key):
					oo.events[key] = ao.own_events[key]
	build_event_holders()
	return 0.0

static func f_object_event_add(s: GMInstance, obj: Variant, ev: Variant, sub: Variant, code: Variant) -> float:
	var o := GMAssets.object(ri(obj))
	if o == null:
		return 0.0
	var key := _event_key(ri(ev), ri(sub))
	var src := str(code)
	var c := Callable(GMCore, "_dyn_event").bind(src)
	o.own_events[key] = c
	for oo: GMObject in GMAssets.objects:
		if oo and oo.ancestors.has(o.index):
			var nearest := -1
			for a in oo.ancestors:
				if GMAssets.object(a).own_events.has(key):
					nearest = a
					break
			if nearest == o.index:
				oo.events[key] = c
	build_event_holders()
	return 0.0
