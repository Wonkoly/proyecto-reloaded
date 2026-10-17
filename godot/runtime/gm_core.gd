## GameMaker 8 runtime core: global state, helpers used by generated code, instances,
## events, rooms and the main loop. Built-in GML functions live in the GMLib* classes that
## extend this one; generated code calls everything through the final class `GM`.
##
## The game logic runs on its own thread (GM8 code blocks with sleep()/screen_redraw()),
## producing draw-command frames that the main thread renders (see gm_screen.gd).
class_name GMCore
extends RefCounted

const EPS := 1e-13

# ------------------------------------------------------------------ global state

## Game globals (global.x).
static var g: Dictionary = {}
static var instances: Array = []            # all instances, insertion order
static var by_object: Dictionary = {}       # object index -> Array of instances (insertion order)
static var by_id: Dictionary = {}           # instance id -> instance
static var next_instance_id := 100001
static var tiles: Array = []                # Dictionary per tile
static var next_tile_id := 10000001
static var event_holders: Dictionary = {}   # event name -> Array[int] of objects having it
static var scene_change: Variant = null     # null | ["room", n] | ["restart"] | ["end"]
static var stored_rooms: Dictionary = {}    # room index -> saved RoomState
static var room_code_override: Dictionary = {} # room index -> code string (room_set_code)
static var game_start := true
static var running := true
static var rng := RandomNumberGenerator.new()
static var start_usec := 0
static var _preloader: Thread

# Built-in global variables (names match GML).
static var room := 0.0
static var room_speed := 30.0
static var score := 0.0
static var lives := -1.0
static var health := 100.0
static var mouse_x := 0.0
static var mouse_y := 0.0
static var keyboard_lastkey := 0.0
static var keyboard_lastchar := ""
static var keyboard_string := ""
static var working_directory := ""
static var game_id := 0.0
static var error_occurred := 0.0
static var error_last := ""
static var transition_kind := 0.0
static var transition_steps := 80.0
static var background_color := 0.0
static var background_showcolor := 1.0
static var view_enabled := 0.0
static var view_current := 0.0
static var cursor_sprite := -1.0
static var debug_mode := 0.0
static var secure_mode := 0.0
static var gamemaker_registered := 1.0
static var gamemaker_pro := 1.0
static var gamemaker_version := 800.0
static var event_type := 0.0
static var event_number := 0.0
static var event_object := 0.0
static var event_action := 0.0
static var view_visible: Array = _arr8(0.0)
static var view_xview: Array = _arr8(0.0)
static var view_yview: Array = _arr8(0.0)
static var view_wview: Array = _arr8(640.0)
static var view_hview: Array = _arr8(480.0)
static var view_xport: Array = _arr8(0.0)
static var view_yport: Array = _arr8(0.0)
static var view_wport: Array = _arr8(640.0)
static var view_hport: Array = _arr8(480.0)
static var view_angle: Array = _arr8(0.0)
static var view_hborder: Array = _arr8(32.0)
static var view_vborder: Array = _arr8(32.0)
static var view_hspeed: Array = _arr8(-1.0)
static var view_vspeed: Array = _arr8(-1.0)
static var view_object: Array = _arr8(-1.0)
static var background_visible: Array = _arr8(0.0)
static var background_foreground: Array = _arr8(0.0)
static var background_index: Array = _arr8(-1.0)
static var background_x: Array = _arr8(0.0)
static var background_y: Array = _arr8(0.0)
static var background_width: Array = _arr8(0.0)
static var background_height: Array = _arr8(0.0)
static var background_htiled: Array = _arr8(0.0)
static var background_vtiled: Array = _arr8(0.0)
static var background_xscale: Array = _arr8(1.0)
static var background_yscale: Array = _arr8(1.0)
static var background_hspeed: Array = _arr8(0.0)
static var background_vspeed: Array = _arr8(0.0)
static var background_blend: Array = _arr8(16777215.0)
static var background_alpha: Array = _arr8(1.0)

# Current room properties.
static var _room_width := 640.0
static var _room_height := 480.0
static var _room_persistent := false
static var _room_caption := ""

static func _arr8(v: float) -> Array:
	var a := []
	a.resize(8)
	a.fill(v)
	return a

# ------------------------------------------------------------------ value helpers

## GM truthiness: reals >= 0.5 are true, strings are false.
static func t(v: Variant) -> bool:
	return v is float and v >= 0.5 or v is int and v >= 1 or v is bool and v

static func eq(a: Variant, b: Variant) -> bool:
	if a is String or b is String:
		return a is String and b is String and a == b
	return absf(a - b) < EPS

static func ne(a: Variant, b: Variant) -> bool:
	return not eq(a, b)

static func lt(a: Variant, b: Variant) -> bool:
	if a is String and b is String:
		return a < b
	return (a - b) <= -EPS

static func le(a: Variant, b: Variant) -> bool:
	if a is String and b is String:
		return a <= b
	return (a - b) < EPS

static func gt(a: Variant, b: Variant) -> bool:
	if a is String and b is String:
		return a > b
	return (a - b) >= EPS

static func ge(a: Variant, b: Variant) -> bool:
	if a is String and b is String:
		return a >= b
	return (a - b) > -EPS

## Comparison where one side is a string literal: a real on the other side never matches.
static func s_cmp(a: Variant, b: Variant, op: String) -> bool:
	if not (a is String and b is String):
		return op == "!="
	match op:
		"==": return a == b
		"!=": return a != b
		"<": return a < b
		"<=": return a <= b
		">": return a > b
	return a >= b

## GM8 real -> int conversion (banker's rounding). Strings convert to 0.
static func ri(v: Variant) -> int:
	if v is String:
		return 0
	var f: float = v
	var fl := floorf(f)
	var d := f - fl
	if d < 0.5:
		return int(fl)
	if d > 0.5:
		return int(fl) + 1
	return int(fl) if int(fl) % 2 == 0 else int(fl) + 1

## Banker's rounding as a float.
static func rf(v: float) -> float:
	return float(ri(v))

static func band(a: Variant, b: Variant) -> float:
	return float(ri(a) & ri(b))

static func bor(a: Variant, b: Variant) -> float:
	return float(ri(a) | ri(b))

static func bxor(a: Variant, b: Variant) -> float:
	return float(ri(a) ^ ri(b))

static func shl(a: Variant, b: Variant) -> float:
	return float(ri(a) << ri(b))

static func shr(a: Variant, b: Variant) -> float:
	return float(ri(a) >> ri(b))

static func bnot(a: Variant) -> float:
	return float(~ri(a))

## Switch with constant labels: exact lookup, tolerating GM's epsilon for near-integers.
static func sw_lookup(table: Dictionary, v: Variant, default_idx: int) -> int:
	if table.has(v):
		return table[v]
	if v is float:
		var r := roundf(v)
		if absf(r - v) < EPS and table.has(r):
			return table[r]
	return default_idx

## Returns the first value; extra script arguments were evaluated for side effects only.
static func first(v: Variant, _rest: Array) -> Variant:
	return v

# --- variables that are arrays somewhere in the game

static func vget(d: Dictionary, n: String) -> Variant:
	var v = d.get(n, 0.0)
	if v is GMArray:
		return v.get_at(0, 0)
	return v

static func vset(d: Dictionary, n: String, val: Variant) -> void:
	var cur = d.get(n)
	if cur is GMArray:
		cur.set_at(0, 0, val)
	else:
		d[n] = val

static func aget(d: Dictionary, n: String, i: int, j: int) -> Variant:
	var v = d.get(n, 0.0)
	if v is GMArray:
		return v.get_at(i, j)
	return v if i == 0 and j == 0 else 0.0

static func aset(d: Dictionary, n: String, i: int, j: int, val: Variant) -> void:
	var v = d.get(n)
	if not (v is GMArray):
		var arr := GMArray.new()
		if v != null:
			arr.set_at(0, 0, v)
		d[n] = arr
		v = arr
	v.set_at(i, j, val)

# Local variables that are arrays: the local holds a GMArray (or a scalar / null).
static func lget(l: Variant) -> Variant:
	if l is GMArray:
		return l.get_at(0, 0)
	return 0.0 if l == null else l

static func lset(l: Variant, val: Variant) -> Variant:
	if l is GMArray:
		l.set_at(0, 0, val)
		return l
	return val

static func laget(l: Variant, i: int, j: int) -> Variant:
	if l is GMArray:
		return l.get_at(i, j)
	if i == 0 and j == 0:
		return 0.0 if l == null else l
	return 0.0

static func laset(l: Variant, i: int, j: int, val: Variant) -> Variant:
	if not (l is GMArray):
		var arr := GMArray.new()
		if l != null:
			arr.set_at(0, 0, l)
		l = arr
	l.set_at(i, j, val)
	return l

# --- field access on other instances: target.field

const INSTANCE_BUILTINS := {
	"x": 1, "y": 1, "xprevious": 1, "yprevious": 1, "xstart": 1, "ystart": 1, "hspeed": 1, "vspeed": 1,
	"direction": 1, "speed": 1, "friction": 1, "gravity": 1, "gravity_direction": 1, "object_index": 1,
	"id": 1, "solid": 1, "visible": 1, "persistent": 1, "depth": 1, "bbox_left": 1, "bbox_right": 1,
	"bbox_top": 1, "bbox_bottom": 1, "sprite_index": 1, "image_index": 1, "image_single": 1,
	"image_number": 1, "sprite_width": 1, "sprite_height": 1, "sprite_xoffset": 1, "sprite_yoffset": 1,
	"image_xscale": 1, "image_yscale": 1, "image_angle": 1, "image_alpha": 1, "image_blend": 1,
	"image_speed": 1, "mask_index": 1, "path_index": 1, "path_position": 1, "path_positionprevious": 1,
	"path_speed": 1, "path_scale": 1, "path_orientation": 1, "path_endaction": 1, "timeline_index": 1,
	"timeline_position": 1, "timeline_speed": 1, "timeline_running": 1, "timeline_loop": 1,
}
const BOOL_BUILTINS := {"solid": 1, "visible": 1, "persistent": 1, "timeline_running": 1, "timeline_loop": 1}

static func inst_get(inst: GMInstance, field: String) -> Variant:
	if INSTANCE_BUILTINS.has(field):
		if field == "alarm":
			return inst.alarm[0]
		var v = inst.get(field)
		return float(v) if v is bool else v
	return vget(inst.v, field)

static func inst_set(inst: GMInstance, field: String, val: Variant) -> void:
	if INSTANCE_BUILTINS.has(field):
		if BOOL_BUILTINS.has(field):
			inst.set(field, t(val))
		else:
			inst.set(field, val)
	elif field == "alarm":
		inst.alarm[0] = val
	else:
		vset(inst.v, field, val)

## Instances a field access refers to (self/other/object/instance id).
static func _targets(s: GMInstance, o: GMInstance, target: Variant, for_write: bool) -> Array:
	var k := ri(target)
	if k == -1:
		return [s]
	if k == -2:
		return [o] if o else []
	if k == -3:
		return _active_snapshot() if for_write else _first_or_empty(_active_snapshot())
	if k >= 100000:
		var i = by_id.get(k)
		return [i] if i and not i.gone else []
	if k >= 0:
		var lst := identity_list(k)
		return lst if for_write else _first_or_empty(lst)
	return []

static func _first_or_empty(a: Array) -> Array:
	return [a[0]] if not a.is_empty() else []

static func fget(s: GMInstance, o: GMInstance, target: Variant, field: String) -> Variant:
	if ri(target) == -5:
		return vget(g, field)
	var ts := _targets(s, o, target, false)
	if ts.is_empty():
		_error("Unknown variable %s (no instance %s)" % [field, target])
		return 0.0
	return inst_get(ts[0], field)

static func fset(s: GMInstance, o: GMInstance, target: Variant, field: String, val: Variant) -> void:
	if ri(target) == -5:
		vset(g, field, val)
		return
	for i in _targets(s, o, target, true):
		inst_set(i, field, val)

static func faget(s: GMInstance, o: GMInstance, target: Variant, field: String, i: int, j: int) -> Variant:
	if ri(target) == -5:
		return aget(g, field, i, j)
	var ts := _targets(s, o, target, false)
	if ts.is_empty():
		return 0.0
	if field == "alarm":
		return ts[0].alarm[i]
	return aget(ts[0].v, field, i, j)

static func faset(s: GMInstance, o: GMInstance, target: Variant, field: String, i: int, j: int, val: Variant) -> void:
	if ri(target) == -5:
		aset(g, field, i, j, val)
		return
	for inst in _targets(s, o, target, true):
		if field == "alarm":
			inst.alarm[i] = val
		else:
			aset(inst.v, field, i, j, val)

## Instances a `with (target)` iterates, snapshotted like GM8's iterators.
static func with_iter(s: GMInstance, o: GMInstance, target: Variant) -> Array:
	var k := ri(target)
	if k == -1:
		return [s]
	if k == -2:
		return [o] if o else []
	if k == -3:
		return _active_snapshot()
	if k >= 100000:
		var i = by_id.get(k)
		return [i] if i and not i.gone else []
	if k >= 0:
		return identity_list(k)
	return []

static func _active_snapshot() -> Array:
	var out := []
	for i: GMInstance in instances:
		if not i.gone:
			out.append(i)
	return out

## Active instances of an object or any of its descendants, in insertion order.
static func identity_list(obj_index: int) -> Array:
	var o := GMAssets.object(obj_index)
	if o == null:
		return []
	if o.children.size() == 1:
		return object_list(obj_index)
	var out := []
	for i: GMInstance in instances:
		if not i.gone and o.children.has(int(i.object_index)):
			out.append(i)
	return out

## Active instances of exactly this object, in insertion order.
static func object_list(obj_index: int) -> Array:
	var out := []
	for i: GMInstance in by_object.get(obj_index, []):
		if not i.gone:
			out.append(i)
	return out

static func _error(msg: String) -> void:
	error_occurred = 1.0
	error_last = msg
	push_warning("[GML] " + msg)

# ------------------------------------------------------------------ instances

static func create_instance(x: float, y: float, obj_index: int, id := -1) -> GMInstance:
	var o := GMAssets.object(obj_index)
	var inst := GMInstance.new()
	if id < 0:
		id = next_instance_id
		next_instance_id += 1
	inst.id = float(id)
	inst.object_index = float(obj_index)
	inst.obj = o
	inst.x = x
	inst.y = y
	inst.xstart = x
	inst.ystart = y
	inst.xprevious = x
	inst.yprevious = y
	if o:
		inst.sprite_index = o.sprite_index
		inst.mask_index = o.mask_index
		inst.solid = o.solid
		inst.visible = o.visible
		inst.depth = o.depth
		inst.persistent = o.persistent
	_insert(inst)
	return inst

static func _insert(inst: GMInstance) -> void:
	instances.append(inst)
	var k := int(inst.object_index)
	if not by_object.has(k):
		by_object[k] = []
	by_object[k].append(inst)
	by_id[int(inst.id)] = inst

## Removes destroyed instances from the lists (end of step, like GM8).
static func purge_destroyed() -> void:
	var keep := []
	var any := false
	for i: GMInstance in instances:
		if i.destroyed:
			any = true
			by_id.erase(int(i.id))
		else:
			keep.append(i)
	if not any:
		return
	instances = keep
	for k in by_object.keys():
		var lst: Array = by_object[k]
		var nl := []
		for i: GMInstance in lst:
			if not i.destroyed:
				nl.append(i)
		by_object[k] = nl

static func destroy_instance(inst: GMInstance, run_event := true) -> void:
	if inst.destroyed:
		return
	if run_event:
		run_event(inst, "destroy", inst)
	inst.destroyed = true
	inst.gone = true

# ------------------------------------------------------------------ events

static func build_event_holders() -> void:
	event_holders = {}
	for o: GMObject in GMAssets.objects:
		if o == null:
			continue
		for ev in o.own_events:
			if not event_holders.has(ev):
				event_holders[ev] = []
			var lst: Array = event_holders[ev]
			for c in o.children:
				if not lst.has(c):
					lst.append(c)

## Runs an event on one instance if its object (or an ancestor) defines it.
## Like GM8, nothing runs while a room change is pending.
static func run_event(inst: GMInstance, ev: String, other: GMInstance) -> void:
	if scene_change != null or inst.gone:
		return
	var o: GMObject = inst.obj
	if o == null:
		return
	var c = o.events.get(ev)
	if c == null:
		return
	if c is int:
		c = GMAssets.event_callable(c, ev)
	c.call(inst, other)

## Runs an event on every instance of every object that has it.
static func run_object_event(ev: String) -> void:
	var holders = event_holders.get(ev)
	if holders == null:
		return
	for obj_index in holders:
		for inst in object_list(obj_index):
			run_event(inst, ev, inst)

## Runs an "other" event on all instances in draw (insertion) order.
static func run_other_event(sub: int) -> void:
	var ev := "other_%d" % sub
	for inst in _active_snapshot():
		run_event(inst, ev, inst)

static func event_inherited(s: GMInstance, o: GMInstance, obj_index: int, ev: String) -> void:
	var obj := GMAssets.object(obj_index)
	if obj == null or obj.parent < 0:
		return
	var parent := GMAssets.object(obj.parent)
	var c = parent.events.get(ev) if parent else null
	if c is int:
		c = GMAssets.event_callable(c, ev)
	if c != null:
		c.call(s, o)

## Executes a code string built at runtime (object_event_add / room_set_code). The game only
## builds "Script();Script();" lists and a fixed set of snippets precompiled into RoomCode.
static func run_code_string(s: GMInstance, o: GMInstance, code: String) -> void:
	if code.strip_edges() == "":
		return
	var pre: Dictionary = room_code().DYNAMIC
	if pre.has(code):
		Callable(room_code(), pre[code]).call(s, o)
		return
	for part in code.split(";", false):
		part = part.strip_edges()
		if part.ends_with("()"):
			var id := GMAssets.script_id(part.substr(0, part.length() - 2))
			if id >= 0:
				GMAssets.script_callable(id).call(s, o)
				continue
		if part != "":
			_error("dynamic code not precompiled: " + code)
			return

# ------------------------------------------------------------------ generated code access

static var _room_code: Script
static var _sc: Array = []

## Generated room/instance creation code (gen/RoomCode.gd), loaded on first use.
static func room_code() -> Script:
	if _room_code == null:
		_room_code = load("res://gen/RoomCode.gd")
	return _room_code

## Script by index, used by generated code: G.sc(id).call(s, o, args...).
static func sc(id: int) -> Callable:
	var c = _sc[id]
	if c == null:
		c = GMAssets.script_callable(id)
		_sc[id] = c
	return c

## Compiles every generated script on a low-priority thread so that first use doesn't stall
## the game (GDScript compilation of the whole game takes a while).
static func _preload_all() -> void:
	var paths := GMAssets.object_script_paths() + GMAssets.script_paths()
	for p in paths:
		if not running:
			return
		load(p)

# ------------------------------------------------------------------ rooms

static func gv_room_width() -> float:
	return _room_width

static func gv_room_height() -> float:
	return _room_height

static func gv_room_persistent() -> float:
	return 1.0 if _room_persistent else 0.0

static func gv_room_caption() -> String:
	return _room_caption

static func gs_room(v: Variant) -> void:
	scene_change = ["room", ri(v)]

static func gs_room_persistent(v: Variant) -> void:
	_room_persistent = t(v)

static func gs_room_caption(v: Variant) -> void:
	_room_caption = str(v)

static func gs_room_speed(v: Variant) -> void:
	room_speed = maxf(1.0, float(v))

static func _capture_room_state() -> Dictionary:
	return {
		"instances": instances.filter(func(i): return not i.persistent and not i.destroyed),
		"tiles": tiles.duplicate(),
		"width": _room_width, "height": _room_height, "speed": room_speed, "caption": _room_caption,
		"persistent": _room_persistent, "colour": background_color, "show_colour": background_showcolor,
		"views_enabled": view_enabled, "views": _views_backup(), "bgs": _bgs_backup(),
	}

static func _views_backup() -> Array:
	return [view_visible.duplicate(), view_xview.duplicate(), view_yview.duplicate(), view_wview.duplicate(),
		view_hview.duplicate(), view_xport.duplicate(), view_yport.duplicate(), view_wport.duplicate(),
		view_hport.duplicate(), view_angle.duplicate(), view_hborder.duplicate(), view_vborder.duplicate(),
		view_hspeed.duplicate(), view_vspeed.duplicate(), view_object.duplicate()]

static func _views_restore(b: Array) -> void:
	view_visible = b[0]; view_xview = b[1]; view_yview = b[2]; view_wview = b[3]; view_hview = b[4]
	view_xport = b[5]; view_yport = b[6]; view_wport = b[7]; view_hport = b[8]; view_angle = b[9]
	view_hborder = b[10]; view_vborder = b[11]; view_hspeed = b[12]; view_vspeed = b[13]; view_object = b[14]

static func _bgs_backup() -> Array:
	return [background_visible.duplicate(), background_foreground.duplicate(), background_index.duplicate(),
		background_x.duplicate(), background_y.duplicate(), background_htiled.duplicate(),
		background_vtiled.duplicate(), background_xscale.duplicate(), background_yscale.duplicate(),
		background_hspeed.duplicate(), background_vspeed.duplicate(), background_blend.duplicate(),
		background_alpha.duplicate()]

static func _bgs_restore(b: Array) -> void:
	background_visible = b[0]; background_foreground = b[1]; background_index = b[2]; background_x = b[3]
	background_y = b[4]; background_htiled = b[5]; background_vtiled = b[6]; background_xscale = b[7]
	background_yscale = b[8]; background_hspeed = b[9]; background_vspeed = b[10]; background_blend = b[11]
	background_alpha = b[12]

## Port of OpenGMK's Game::load_room.
static func load_room(room_index: int) -> void:
	var rd := GMAssets.room(room_index)
	if rd.is_empty():
		push_error("load_room: no room %d" % room_index)
		return
	scene_change = null
	if OS.is_debug_build():
		print("[GM] room %s (%d ms)" % [rd.name, (Time.get_ticks_usec() - start_usec) / 1000])

	# Room end for everyone; a room change can't be requested during it.
	run_other_event(5)
	scene_change = null

	var persistent_insts := instances.filter(func(i): return i.persistent and not i.destroyed)
	if _room_persistent and not game_start:
		stored_rooms[int(room)] = _capture_room_state()

	var stored = stored_rooms.get(room_index)
	stored_rooms.erase(room_index)
	instances = []
	by_object = {}
	by_id = {}
	tiles = []
	room = float(room_index)
	GM.input_step()
	GM.effects_clear()

	var new_insts := []
	if stored != null:
		_room_width = stored.width
		_room_height = stored.height
		room_speed = stored.speed
		_room_caption = stored.caption
		_room_persistent = stored.persistent
		background_color = stored.colour
		background_showcolor = stored.show_colour
		view_enabled = stored.views_enabled
		_views_restore(stored.views)
		_bgs_restore(stored.bgs)
		tiles = stored.tiles
		for i: GMInstance in stored.instances:
			_insert(i)
	else:
		_room_width = float(rd.width)
		_room_height = float(rd.height)
		room_speed = float(rd.speed)
		_room_caption = rd.caption
		_room_persistent = rd.persistent
		background_color = float(rd.bg_colour)
		background_showcolor = 1.0 if rd.clear_screen else 0.0
		view_enabled = 1.0 if rd.views_enabled else 0.0
		for k in 8:
			var vw: Dictionary = rd.views[k] if k < rd.views.size() else {}
			view_visible[k] = 1.0 if vw.get("visible", false) else 0.0
			view_xview[k] = float(vw.get("x", 0)); view_yview[k] = float(vw.get("y", 0))
			view_wview[k] = float(vw.get("w", 640)); view_hview[k] = float(vw.get("h", 480))
			view_xport[k] = float(vw.get("port_x", 0)); view_yport[k] = float(vw.get("port_y", 0))
			view_wport[k] = float(vw.get("port_w", 640)); view_hport[k] = float(vw.get("port_h", 480))
			view_angle[k] = 0.0
			view_hborder[k] = float(vw.get("hborder", 32)); view_vborder[k] = float(vw.get("vborder", 32))
			view_hspeed[k] = float(vw.get("hspeed", -1)); view_vspeed[k] = float(vw.get("vspeed", -1))
			var follow = vw.get("follow")
			view_object[k] = float(GMAssets.names_lookup("objects", follow)) if follow != null else -1.0
			var b: Dictionary = rd.backgrounds[k] if k < rd.backgrounds.size() else {}
			background_visible[k] = 1.0 if b.get("visible", false) else 0.0
			background_foreground[k] = 1.0 if b.get("foreground", false) else 0.0
			var bgn = b.get("bg")
			background_index[k] = float(GMAssets.names_lookup("backgrounds", bgn)) if bgn != null else -1.0
			background_x[k] = float(b.get("x", 0)); background_y[k] = float(b.get("y", 0))
			background_htiled[k] = 1.0 if b.get("tile_h", false) else 0.0
			background_vtiled[k] = 1.0 if b.get("tile_v", false) else 0.0
			background_xscale[k] = 1.0; background_yscale[k] = 1.0
			background_hspeed[k] = float(b.get("hspeed", 0)); background_vspeed[k] = float(b.get("vspeed", 0))
			background_blend[k] = 16777215.0; background_alpha[k] = 1.0
		for td in rd.tiles:
			var bgi := GMAssets.names_lookup("backgrounds", td.bg)
			tiles.append({"id": int(td.id), "bg": bgi, "x": float(td.x), "y": float(td.y),
				"tx": int(td.tx), "ty": int(td.ty), "w": int(td.w), "h": int(td.h), "depth": float(td.depth),
				"xscale": float(td.xscale), "yscale": float(td.yscale), "blend": int(td.blend) & 0xFFFFFF,
				"alpha": float(int(td.blend) >> 24) / 255.0, "visible": true})
		for idata in rd.instances:
			var id := int(idata.id)
			if by_id.has(id):
				continue
			var oi := GMAssets.names_lookup("objects", idata.object)
			if oi < 0:
				continue
			var inst := create_instance(float(idata.x), float(idata.y), oi, id)
			inst.image_xscale = float(idata.xscale)
			inst.image_yscale = float(idata.yscale)
			inst.image_blend = float(int(idata.blend) & 0xFFFFFF)
			inst.image_alpha = float(int(idata.blend) >> 24) / 255.0
			inst.image_angle = float(idata.angle)
			new_insts.append([inst, idata])

	for i: GMInstance in persistent_insts:
		var clash = by_id.get(int(i.id))
		if clash:
			clash.destroyed = true
			clash.gone = true
		_insert(i)
	purge_destroyed()

	for pair in new_insts:
		var inst: GMInstance = pair[0]
		if inst.gone:
			continue
		if GMAssets.settings.get("swap_creation_events", false):
			run_event(inst, "create", inst)
		if pair[1].creation_code.strip_edges() != "":
			Callable(room_code(), "i_%d" % int(inst.id)).call(inst, inst)
		if not GMAssets.settings.get("swap_creation_events", false):
			run_event(inst, "create", inst)

	if game_start:
		run_other_event(2)
		game_start = false

	if stored == null:
		var dummy := GMInstance.new()
		dummy.id = -100.0
		if room_code_override.has(room_index):
			run_code_string(dummy, dummy, room_code_override[room_index])
		elif rd.creation_code.strip_edges() != "":
			Callable(room_code(), "r_" + GMAssets._file_name(rd.name)).call(dummy, dummy)

	run_other_event(4)
	GM.screen_set_size()
	if scene_change == null:
		GM.draw_frame()

static func restart_game() -> void:
	scene_change = null
	run_other_event(5)
	run_other_event(3)
	instances = []
	by_object = {}
	by_id = {}
	stored_rooms = {}
	g = {}
	game_start = true
	load_room(int(GMAssets.room_order[0]) if GMAssets.room_order[0] is float else GMAssets.names_lookup("rooms", GMAssets.room_order[0]))

static func handle_scene_change() -> void:
	var guard := 0
	while scene_change != null and guard < 100:
		guard += 1
		var sc: Array = scene_change
		match sc[0]:
			"room":
				load_room(sc[1])
			"restart":
				restart_game()
			"end":
				scene_change = null
				run_other_event(5)
				run_other_event(3)
				running = false
				GM.post_command(["quit"])
				return

# ------------------------------------------------------------------ main loop

static func boot(game_root: String) -> void:
	start_usec = Time.get_ticks_usec()
	rng.randomize()
	GMAssets.load_all(game_root)
	working_directory = game_root
	game_id = float(GMAssets.settings.game_id)
	next_instance_id = int(GMAssets.settings.last_instance_id) + 1
	next_tile_id = int(GMAssets.settings.last_tile_id) + 1
	build_event_holders()
	_sc.resize(GMAssets.script_names.size())
	_preloader = Thread.new()
	_preloader.start(_preload_all, Thread.PRIORITY_LOW)
	var first = GMAssets.room_order[0]
	room = float(GMAssets.names_lookup("rooms", first))
	load_room(int(room))
	handle_scene_change()

## The game thread: runs frames at room_speed until the game ends.
static func run(game_root: String) -> void:
	boot(game_root)
	var next_tick := Time.get_ticks_usec()
	while running:
		GM.io_handle()
		frame()
		handle_scene_change()
		next_tick += int(1000000.0 / maxf(1.0, room_speed))
		var now := Time.get_ticks_usec()
		if next_tick > now:
			OS.delay_usec(next_tick - now)
		else:
			next_tick = now

## Port of OpenGMK's Game::frame.
static func frame() -> void:
	for inst: GMInstance in instances:
		if not inst.gone:
			inst.xprevious = inst.x
			inst.yprevious = inst.y
			inst.path_positionprevious = clampf(inst.path_position, 0.0, 1.0)

	run_object_event("step_begin")
	if scene_change != null: return

	_run_alarms()
	if scene_change != null: return
	GM.run_input_events()
	if scene_change != null: return

	run_object_event("step_normal")
	if scene_change != null: return

	GM.process_speeds()
	for inst in _active_snapshot():
		if GM.apply_motion(inst):
			run_event(inst, "other_8", inst)

	GM.run_bound_events()
	if scene_change != null: return
	GM.run_collisions()
	if scene_change != null: return

	run_object_event("step_end")
	if scene_change != null: return

	GM.particles_auto_update()
	purge_destroyed()

	GM.draw_frame()

	for k in 8:
		background_x[k] += background_hspeed[k]
		background_y[k] += background_vspeed[k]

	for inst in _active_snapshot():
		var spr := GMAssets.sprite(inst.sprite_index)
		var n := float(spr.frames) if spr else 0.0
		inst.image_index += inst.image_speed
		if inst.image_index >= n:
			inst.image_index -= n
			run_event(inst, "other_7", inst)

	GM.input_step()

static func _run_alarms() -> void:
	for a in 12:
		var holders = event_holders.get("alarm_%d" % a)
		if holders == null:
			continue
		var ev := "alarm_%d" % a
		for obj_index in holders:
			for inst in object_list(obj_index):
				var al: float = inst.alarm[a]
				if al >= 0.0:
					al -= 1.0
					inst.alarm[a] = al
					if absf(al) < EPS:
						run_event(inst, ev, inst)

## Target of object_event_add events: runs the code string bound at registration.
static func _dyn_event(s: GMInstance, o: GMInstance, src: String) -> void:
	run_code_string(s, o, src)
