## Input, sound, window, runtime sprite/background loading, scripts, paths and misc.
class_name GMLibSys
extends GMLibData

# ------------------------------------------------------------------ input
# The main thread pushes events with push_input(); the game thread applies them in io_handle().
# `_live_*` is updated immediately so keyboard_check_direct works inside blocking loops.

static var _input_mutex := Mutex.new()
static var _input_queue: Array = []
static var _live_keys: PackedByteArray = _bytes256()
static var _held: PackedByteArray = _bytes256()
static var _pressed: PackedByteArray = _bytes256()
static var _released: PackedByteArray = _bytes256()
static var _mouse_held: PackedByteArray = _bytes256()
static var _mouse_pressed: PackedByteArray = _bytes256()
static var _mouse_released: PackedByteArray = _bytes256()
static var _screen_mouse := Vector2.ZERO
static var _keyboard_key := 0.0
static var _mouse_button := 0.0
static var _mouse_lastbutton := 0.0
## Main-thread facts the game reads: fullscreen flag, window size/position, display mouse.
static var window_state := {"fullscreen": false, "w": 640, "h": 480, "x": 0, "y": 0, "dmx": 0, "dmy": 0}

static func _bytes256() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(256)
	return b

static func push_input(ev: Array) -> void:
	_input_mutex.lock()
	_input_queue.append(ev)
	if ev[0] == "down":
		_live_keys[ev[1]] = 1
	elif ev[0] == "up":
		_live_keys[ev[1]] = 0
	elif ev[0] == "mouse":
		_screen_mouse = ev[1]
	_input_mutex.unlock()

static func io_handle() -> void:
	_input_mutex.lock()
	var q := _input_queue
	_input_queue = []
	var sm := _screen_mouse
	_input_mutex.unlock()
	for ev in q:
		match ev[0]:
			"down":
				var k: int = ev[1]
				if _held[k] == 0:
					_pressed[k] = 1
				_held[k] = 1
				keyboard_lastkey = float(k)
				_keyboard_key = float(k)
			"up":
				var k: int = ev[1]
				_held[k] = 0
				_released[k] = 1
				if int(_keyboard_key) == k:
					_keyboard_key = 0.0
			"char":
				var c: String = ev[1]
				keyboard_lastchar = c
				if c == "\b":
					keyboard_string = keyboard_string.substr(0, maxi(keyboard_string.length() - 1, 0))
				elif c.unicode_at(0) >= 32:
					keyboard_string = (keyboard_string + c).right(1024)
			"mdown":
				var b: int = ev[1]
				_mouse_held[b] = 1
				_mouse_pressed[b] = 1
				_mouse_button = float(b)
				_mouse_lastbutton = float(b)
			"mup":
				var b: int = ev[1]
				_mouse_held[b] = 0
				_mouse_released[b] = 1
				if int(_mouse_button) == b:
					_mouse_button = 0.0
	_update_mouse_room(sm)

## Screen position -> room coordinates (through the view under the mouse, like GM8).
static func _update_mouse_room(sm: Vector2) -> void:
	if t(view_enabled):
		for k in range(7, -1, -1):
			if not t(view_visible[k]):
				continue
			var port := Rect2(view_xport[k], view_yport[k], view_wport[k], view_hport[k])
			if port.has_point(sm) or k == 0:
				mouse_x = view_xview[k] + (sm.x - port.position.x) * view_wview[k] / maxf(port.size.x, 1.0)
				mouse_y = view_yview[k] + (sm.y - port.position.y) * view_hview[k] / maxf(port.size.y, 1.0)
				return
	mouse_x = sm.x
	mouse_y = sm.y

static func input_step() -> void:
	_pressed.fill(0)
	_released.fill(0)
	_mouse_pressed.fill(0)
	_mouse_released.fill(0)

static func gv_keyboard_key() -> float:
	return _keyboard_key

static func gs_keyboard_key(v: Variant) -> void:
	_keyboard_key = float(v)

static func gs_keyboard_lastkey(v: Variant) -> void:
	keyboard_lastkey = float(v)

static func gs_keyboard_string(v: Variant) -> void:
	keyboard_string = str(v)

static func gv_mouse_button() -> float:
	return _mouse_button

static func gv_mouse_lastbutton() -> float:
	return _mouse_lastbutton

static func _any(b: PackedByteArray) -> bool:
	for i in range(2, 256):
		if b[i] != 0:
			return true
	return false

static func _key_state(b: PackedByteArray, key: Variant) -> float:
	var k := ri(key)
	if k == 1:
		return 1.0 if _any(b) else 0.0
	if k == 0:
		return 0.0 if _any(b) else 1.0
	if k < 0 or k > 255:
		return 0.0
	return float(b[k])

static func f_keyboard_check(s: GMInstance, key: Variant) -> float:
	return _key_state(_held, key)

static func f_keyboard_check_pressed(s: GMInstance, key: Variant) -> float:
	return _key_state(_pressed, key)

static func f_keyboard_check_released(s: GMInstance, key: Variant) -> float:
	return _key_state(_released, key)

static func f_keyboard_check_direct(s: GMInstance, key: Variant) -> float:
	_input_mutex.lock()
	var r := _key_state(_live_keys, key)
	_input_mutex.unlock()
	return r

static func f_keyboard_key_press(s: GMInstance, key: Variant) -> float:
	var k := ri(key) & 0xFF
	if _held[k] == 0:
		_pressed[k] = 1
	_held[k] = 1
	return 0.0

static func f_keyboard_key_release(s: GMInstance, key: Variant) -> float:
	var k := ri(key) & 0xFF
	_held[k] = 0
	_released[k] = 1
	return 0.0

static func f_keyboard_clear(s: GMInstance, key: Variant) -> float:
	var k := ri(key) & 0xFF
	_held[k] = 0
	_pressed[k] = 0
	_released[k] = 0
	return 0.0

static func f_io_clear(s: GMInstance) -> float:
	_held.fill(0)
	_pressed.fill(0)
	_released.fill(0)
	_mouse_held.fill(0)
	_mouse_pressed.fill(0)
	_mouse_released.fill(0)
	return 0.0

static func f_io_handle(s: GMInstance) -> float:
	io_handle()
	return 0.0

static func f_keyboard_wait(s: GMInstance) -> float:
	# Blocks until any key goes down.
	while running:
		_input_mutex.lock()
		var any_down := false
		for ev in _input_queue:
			if ev[0] == "down":
				any_down = true
				break
		_input_mutex.unlock()
		if any_down:
			io_handle()
			return 0.0
		OS.delay_msec(10)
	return 0.0

static func _mouse_state(b: PackedByteArray, button: Variant) -> float:
	var k := ri(button)
	if k == -1:
		return 1.0 if b[1] or b[2] or b[3] else 0.0
	if k == 0:
		return 0.0 if b[1] or b[2] or b[3] else 1.0
	return float(b[clampi(k, 0, 255)])

static func f_mouse_check_button(s: GMInstance, b: Variant) -> float:
	return _mouse_state(_mouse_held, b)

static func f_mouse_check_button_pressed(s: GMInstance, b: Variant) -> float:
	return _mouse_state(_mouse_pressed, b)

static func f_mouse_clear(s: GMInstance, b: Variant) -> float:
	var k := clampi(ri(b), 0, 255)
	_mouse_held[k] = 0
	_mouse_pressed[k] = 0
	_mouse_released[k] = 0
	return 0.0

static func run_input_events() -> void:
	# Keyboard (held), key press and key release events, then mouse button events.
	for kind in [["keyboard_", _held], ["keypress_", _pressed], ["keyrelease_", _released]]:
		var prefix: String = kind[0]
		var state: PackedByteArray = kind[1]
		for ev in event_holders.keys():
			if not ev.begins_with(prefix):
				continue
			var k := int(ev.substr(prefix.length()))
			var active := false
			if k == 1:
				active = _any(state)
			elif k == 0:
				active = not _any(state)
			elif k > 1 and k < 256:
				active = state[k] != 0
			if active:
				run_object_event(ev)
				if scene_change != null:
					return
	# Mouse events over instances: 0-2 held, 3 none, 4-6 pressed, 7-9 released, 10/11 enter/leave (skipped)
	var mouse_map := [[0, _mouse_held, 1], [1, _mouse_held, 2], [2, _mouse_held, 3],
		[4, _mouse_pressed, 1], [5, _mouse_pressed, 2], [6, _mouse_pressed, 3],
		[7, _mouse_released, 1], [8, _mouse_released, 2], [9, _mouse_released, 3]]
	for m in mouse_map:
		var ev := "mouse_%d" % m[0]
		if not event_holders.has(ev) or m[1][m[2]] == 0:
			continue
		for oi in event_holders[ev]:
			for inst in object_list(oi):
				if check_collision_point(inst, mouse_x, mouse_y, true):
					run_event(inst, ev, inst)
	# Global mouse events 50-52 (held), 53-55 (pressed), 56-58 (released)
	var gmap := [[50, _mouse_held, 1], [51, _mouse_held, 2], [52, _mouse_held, 3],
		[53, _mouse_pressed, 1], [54, _mouse_pressed, 2], [55, _mouse_pressed, 3],
		[56, _mouse_released, 1], [57, _mouse_released, 2], [58, _mouse_released, 3]]
	for m in gmap:
		if m[1][m[2]] != 0:
			run_object_event("mouse_%d" % m[0])

static func f_display_mouse_get_x(s: GMInstance) -> float:
	return float(window_state.dmx)

static func f_display_mouse_get_y(s: GMInstance) -> float:
	return float(window_state.dmy)

static func f_display_mouse_set(s: GMInstance, x: Variant, y: Variant) -> float:
	post_command(["warp_mouse_display", Vector2(x, y)])
	return 0.0

static func f_window_mouse_get_x(s: GMInstance) -> float:
	return _screen_mouse.x

static func f_window_mouse_get_y(s: GMInstance) -> float:
	return _screen_mouse.y

static func f_window_mouse_set(s: GMInstance, x: Variant, y: Variant) -> float:
	post_command(["warp_mouse", Vector2(x, y)])
	return 0.0

# ------------------------------------------------------------------ window

static func f_window_get_fullscreen(s: GMInstance) -> float:
	return 1.0 if window_state.fullscreen else 0.0

static func f_window_set_fullscreen(s: GMInstance, v: Variant) -> float:
	window_state.fullscreen = t(v)
	post_command(["fullscreen", t(v)])
	return 0.0

static func f_window_set_cursor(s: GMInstance, c: Variant) -> float:
	post_command(["cursor", ri(c)])
	return 0.0

static var _region_scale := 1.0

static func f_window_set_region_scale(s: GMInstance, sc: Variant, adapt: Variant) -> float:
	_region_scale = float(sc)
	post_command(["region_scale", float(sc), t(adapt)])
	return 0.0

static func f_window_get_region_scale(s: GMInstance) -> float:
	return _region_scale

static func f_window_get_width(s: GMInstance) -> float:
	return float(window_state.w)

static func f_window_get_height(s: GMInstance) -> float:
	return float(window_state.h)

static func f_window_get_x(s: GMInstance) -> float:
	return float(window_state.x)

static func f_window_get_y(s: GMInstance) -> float:
	return float(window_state.y)

static func f_window_set_rectangle(s: GMInstance, x: Variant, y: Variant, w: Variant, h: Variant) -> float:
	post_command(["window_rect", Rect2i(ri(x), ri(y), ri(w), ri(h))])
	return 0.0

# ------------------------------------------------------------------ sound

static var _sound_playing: Dictionary = {}
static var _sound_mutex := Mutex.new()

## Main thread reports which sounds are currently audible.
static func set_sound_playing(state: Dictionary) -> void:
	_sound_mutex.lock()
	_sound_playing = state
	_sound_mutex.unlock()

static func _sound_path(i: int) -> String:
	if i < 0 or i >= GMAssets.sounds.size() or GMAssets.sounds[i] == null:
		return ""
	return GMAssets.sounds[i].path

static func f_sound_play(s: GMInstance, snd: Variant) -> float:
	var i := ri(snd)
	post_command(["snd_play", i, _sound_path(i), false, GMAssets.sounds[i].kind if _sound_path(i) != "" else 0])
	_mark_playing(i)
	return 0.0

static func f_sound_loop(s: GMInstance, snd: Variant) -> float:
	var i := ri(snd)
	post_command(["snd_play", i, _sound_path(i), true, GMAssets.sounds[i].kind if _sound_path(i) != "" else 0])
	_mark_playing(i)
	return 0.0

static func _mark_playing(i: int) -> void:
	# Optimistically playing until the main thread reports otherwise.
	_sound_mutex.lock()
	_sound_playing[i] = true
	_sound_mutex.unlock()

static func f_sound_stop(s: GMInstance, snd: Variant) -> float:
	post_command(["snd_stop", ri(snd)])
	_sound_mutex.lock()
	_sound_playing.erase(ri(snd))
	_sound_mutex.unlock()
	return 0.0

static func f_sound_stop_all(s: GMInstance) -> float:
	post_command(["snd_stop_all"])
	_sound_mutex.lock()
	_sound_playing = {}
	_sound_mutex.unlock()
	return 0.0

static func f_sound_isplaying(s: GMInstance, snd: Variant) -> float:
	_sound_mutex.lock()
	var p: bool = _sound_playing.get(ri(snd), false)
	_sound_mutex.unlock()
	return 1.0 if p else 0.0

static func f_sound_volume(s: GMInstance, snd: Variant, v: Variant) -> float:
	post_command(["snd_volume", ri(snd), float(v)])
	return 0.0

static func f_sound_global_volume(s: GMInstance, v: Variant) -> float:
	post_command(["snd_global_volume", float(v)])
	return 0.0

static func f_sound_fade(s: GMInstance, snd: Variant, v: Variant, ms: Variant) -> float:
	post_command(["snd_fade", ri(snd), float(v), float(ms)])
	return 0.0

static func f_sound_exists(s: GMInstance, snd: Variant) -> float:
	var i := ri(snd)
	return 1.0 if i >= 0 and i < GMAssets.sounds.size() and GMAssets.sounds[i] != null else 0.0

static func f_sound_replace(s: GMInstance, snd: Variant, fname: Variant, kind: Variant, _preload: Variant) -> float:
	var i := ri(snd)
	if i < 0 or i >= GMAssets.sounds.size():
		return 0.0
	var path := real_path(fname)
	if not FileAccess.file_exists(path):
		return 0.0
	if GMAssets.sounds[i] == null:
		GMAssets.sounds[i] = GMAssets.SoundAsset.new()
	GMAssets.sounds[i].path = path
	GMAssets.sounds[i].kind = ri(kind)
	post_command(["snd_replace", i, path])
	return 1.0

# ------------------------------------------------------------------ runtime sprites / backgrounds

## Loads an image file; GIFs are pre-converted to PNG (one horizontal strip of all frames,
## frame count in a sidecar .frames file).
static func _load_image(path: String) -> Image:
	var img := Image.load_from_file(path)
	if img and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

static func _frame_count_hint(path: String, imgnumb: int) -> int:
	var side := path + ".frames"
	if FileAccess.file_exists(side):
		return maxi(1, FileAccess.get_file_as_string(side).strip_edges().to_int())
	return maxi(1, imgnumb)

static func _remove_back(img: Image) -> void:
	# GM8: pixels matching the bottom-left pixel become transparent.
	var key := img.get_pixel(0, img.get_height() - 1)
	for yy in img.get_height():
		for xx in img.get_width():
			var c := img.get_pixel(xx, yy)
			if c.r8 == key.r8 and c.g8 == key.g8 and c.b8 == key.b8:
				img.set_pixel(xx, yy, Color(c, 0.0))

static func _sprite_from_file(fname: Variant, imgnumb: Variant, removeback: Variant, xorig: Variant, yorig: Variant) -> GMSprite:
	var path := real_path(fname)
	if not FileAccess.file_exists(path):
		return null
	var strip := _load_image(path)
	if strip == null:
		return null
	var n := _frame_count_hint(path, ri(imgnumb))
	var orig_has_alpha := path.get_extension().to_lower() == "png" and not FileAccess.file_exists(path + ".frames")
	if t(removeback) and not orig_has_alpha:
		_remove_back(strip)
	var fw := strip.get_width() / n
	var imgs := []
	for i in n:
		imgs.append(strip.get_region(Rect2i(i * fw, 0, fw, strip.get_height())))
	var spr := GMSprite.new()
	spr.name = path.get_file()
	spr.set_images(imgs, ri(xorig), ri(yorig), true)
	return spr

static func f_sprite_add(s: GMInstance, fname: Variant, imgnumb: Variant, removeback: Variant, _smooth: Variant, xorig: Variant, yorig: Variant) -> float:
	var spr := _sprite_from_file(fname, imgnumb, removeback, xorig, yorig)
	if spr == null:
		return -1.0
	GMAssets.sprites.append(spr)
	return float(GMAssets.sprites.size() - 1)

static func f_sprite_replace(s: GMInstance, ind: Variant, fname: Variant, imgnumb: Variant, removeback: Variant, _smooth: Variant, xorig: Variant, yorig: Variant) -> float:
	var spr := _sprite_from_file(fname, imgnumb, removeback, xorig, yorig)
	var i := ri(ind)
	if spr == null or i < 0:
		return 0.0
	while GMAssets.sprites.size() <= i:
		GMAssets.sprites.append(null)
	GMAssets.sprites[i] = spr
	_invalidate_bboxes(i)
	return 1.0

## Loads a GM8 .gmspr file (magic 1234321, zlib body, BGRA frames).
static func f_sprite_add_sprite(s: GMInstance, fname: Variant) -> float:
	var path := real_path(fname)
	if not FileAccess.file_exists(path):
		return -1.0
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() < 8 or raw.decode_u32(0) != 1234321:
		return -1.0
	var d := raw.slice(8).decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if d.is_empty():
		return -1.0
	var ox := d.decode_s32(4)
	var oy := d.decode_s32(8)
	var n := d.decode_u32(12)
	var pos := 16
	var imgs := []
	for i in n:
		var w := d.decode_u32(pos + 4)
		var h := d.decode_u32(pos + 8)
		var ln := d.decode_u32(pos + 12)
		var px := d.slice(pos + 16, pos + 16 + ln)
		for k in range(0, px.size(), 4):
			var b := px[k]
			px[k] = px[k + 2]
			px[k + 2] = b
		imgs.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px))
		pos += 16 + ln
	var spr := GMSprite.new()
	spr.name = path.get_file()
	spr.set_images(imgs, ox, oy, true)
	GMAssets.sprites.append(spr)
	return float(GMAssets.sprites.size() - 1)

static func f_sprite_duplicate(s: GMInstance, ind: Variant) -> float:
	var src := GMAssets.sprite(ind)
	if src == null:
		return -1.0
	var spr := GMSprite.new()
	var imgs := []
	for i in src.frames:
		imgs.append(src.image(i).duplicate())
	spr.set_images(imgs, src.origin_x, src.origin_y, true)
	spr.colliders = src.colliders.duplicate(true)
	spr.per_frame_colliders = src.per_frame_colliders
	spr.bbox_left = src.bbox_left
	spr.bbox_top = src.bbox_top
	spr.bbox_right = src.bbox_right
	spr.bbox_bottom = src.bbox_bottom
	GMAssets.sprites.append(spr)
	return float(GMAssets.sprites.size() - 1)

static func f_sprite_delete(s: GMInstance, ind: Variant) -> float:
	var i := ri(ind)
	if i >= 0 and i < GMAssets.sprites.size():
		GMAssets.sprites[i] = null
	return 0.0

static func _invalidate_bboxes(sprite: int) -> void:
	for inst: GMInstance in instances:
		if int(inst.sprite_index) == sprite or int(inst.mask_index) == sprite:
			inst.bbox_stale = true

static func f_sprite_exists(s: GMInstance, ind: Variant) -> float:
	return 1.0 if GMAssets.sprite(ind) != null else 0.0

static func f_sprite_get_number(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.frames) if spr else 0.0

static func f_sprite_get_width(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.width) if spr else 0.0

static func f_sprite_get_height(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.height) if spr else 0.0

static func f_sprite_get_xoffset(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.origin_x) if spr else 0.0

static func f_sprite_get_yoffset(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.origin_y) if spr else 0.0

static func f_sprite_get_bbox_top(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.bbox_top) if spr else 0.0

static func f_sprite_get_bbox_bottom(s: GMInstance, ind: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	return float(spr.bbox_bottom) if spr else 0.0

static func f_sprite_set_offset(s: GMInstance, ind: Variant, x: Variant, y: Variant) -> float:
	var spr := GMAssets.sprite(ind)
	if spr:
		spr.origin_x = ri(x)
		spr.origin_y = ri(y)
		_invalidate_bboxes(ri(ind))
	return 0.0

static func _bg_from_file(fname: Variant, removeback: Variant) -> GMAssets.BgAsset:
	var path := real_path(fname)
	if not FileAccess.file_exists(path):
		return null
	var img := _load_image(path)
	if img == null:
		return null
	if t(removeback) and path.get_extension().to_lower() != "png":
		_remove_back(img)
	var bg := GMAssets.BgAsset.new()
	bg.name = path.get_file()
	bg.set_image(img)
	return bg

static func f_background_add(s: GMInstance, fname: Variant, removeback: Variant, _smooth: Variant) -> float:
	var bg := _bg_from_file(fname, removeback)
	if bg == null:
		return -1.0
	GMAssets.backgrounds.append(bg)
	return float(GMAssets.backgrounds.size() - 1)

static func f_background_replace(s: GMInstance, ind: Variant, fname: Variant, removeback: Variant, _smooth: Variant) -> float:
	var bg := _bg_from_file(fname, removeback)
	var i := ri(ind)
	if bg == null or i < 0:
		return 0.0
	while GMAssets.backgrounds.size() <= i:
		GMAssets.backgrounds.append(null)
	GMAssets.backgrounds[i] = bg
	return 1.0

static func f_background_delete(s: GMInstance, ind: Variant) -> float:
	var i := ri(ind)
	if i >= 0 and i < GMAssets.backgrounds.size():
		GMAssets.backgrounds[i] = null
	return 0.0

static func f_background_exists(s: GMInstance, ind: Variant) -> float:
	return 1.0 if GMAssets.background(ind) != null else 0.0

static func _tile(id: Variant) -> Dictionary:
	var k := ri(id)
	for td in tiles:
		if td.id == k:
			return td
	return {}

static func f_tile_exists(s: GMInstance, id: Variant) -> float:
	return 0.0 if _tile(id).is_empty() else 1.0

static func f_tile_delete(s: GMInstance, id: Variant) -> float:
	var td := _tile(id)
	if not td.is_empty():
		tiles.erase(td)
	return 0.0

static func f_tile_set_alpha(s: GMInstance, id: Variant, a: Variant) -> float:
	var td := _tile(id)
	if not td.is_empty():
		td.alpha = float(a)
	return 0.0

# ------------------------------------------------------------------ scripts

static func f_script_execute(s: GMInstance, id: Variant, args: Array) -> Variant:
	var c := GMAssets.script_callable(id)
	if not c.is_valid():
		_error("script_execute: no script %s" % id)
		return 0.0
	var n := c.get_argument_count() - 2
	var a := [s, s]
	for i in n:
		a.append(args[i] if i < args.size() else 0.0)
	return c.callv(a)

static func f_script_exists(s: GMInstance, id: Variant) -> float:
	var k := ri(id)
	return 1.0 if k >= 0 and k < GMAssets.script_names.size() and GMAssets.script_names[k] != null else 0.0

static func f_script_get_name(s: GMInstance, id: Variant) -> String:
	var k := ri(id)
	if k >= 0 and k < GMAssets.script_names.size() and GMAssets.script_names[k] != null:
		return GMAssets.script_names[k]
	return ""

static func f_script_get_text(s: GMInstance, id: Variant) -> String:
	return GMAssets.script_raw.get(f_script_get_name(s, id), "")

# ------------------------------------------------------------------ paths (linear/smooth following)

static func _path_point(p: Dictionary, pos: float) -> Vector3:
	var pts: Array = p.points
	if pts.is_empty():
		return Vector3.ZERO
	if pts.size() == 1:
		return Vector3(pts[0][0], pts[0][1], pts[0][2])
	var segs := []
	var total := 0.0
	var n := pts.size() if p.closed else pts.size() - 1
	for i in n:
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % pts.size()]
		var l := Vector2(b[0] - a[0], b[1] - a[1]).length()
		segs.append(l)
		total += l
	var d := clampf(pos, 0.0, 1.0) * total
	for i in n:
		if d <= segs[i] or i == n - 1:
			var a: Array = pts[i]
			var b: Array = pts[(i + 1) % pts.size()]
			var f: float = d / segs[i] if segs[i] > 0.0 else 0.0
			return Vector3(lerpf(a[0], b[0], f), lerpf(a[1], b[1], f), lerpf(a[2], b[2], f))
		d -= segs[i]
	return Vector3(pts[-1][0], pts[-1][1], pts[-1][2])

static func _path_length(p: Dictionary) -> float:
	var pts: Array = p.points
	var total := 0.0
	var n := pts.size() if p.closed else pts.size() - 1
	for i in n:
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % pts.size()]
		total += Vector2(b[0] - a[0], b[1] - a[1]).length()
	return total

static func f_path_start(s: GMInstance, path: Variant, sp: Variant, endaction: Variant, absolute: Variant) -> float:
	var k := ri(path)
	if k < 0 or k >= GMAssets.paths.size():
		return 0.0
	s.path_index = float(k)
	s.path_speed = float(sp)
	s.path_endaction = float(endaction)
	s.path_position = 0.0
	s.path_scale = 1.0
	s.path_orientation = 0.0
	var p: Dictionary = GMAssets.paths[k]
	var start := _path_point(p, 0.0)
	if t(absolute):
		s.path_xstart = start.x
		s.path_ystart = start.y
		s.x = start.x
		s.y = start.y
	else:
		s.path_xstart = s.x - start.x
		s.path_ystart = s.y - start.y
		s.path_xstart = s.x
		s.path_ystart = s.y
	s.v["@path_abs"] = t(absolute)
	s.v["@path_origin"] = Vector2(s.x, s.y) - Vector2(start.x, start.y)
	return 0.0

static func f_path_end(s: GMInstance) -> float:
	s.path_index = -1.0
	return 0.0

static func path_advance(inst: GMInstance) -> bool:
	if inst.path_index < 0.0 or inst.path_speed == 0.0:
		return false
	var p: Dictionary = GMAssets.paths[int(inst.path_index)]
	var length := _path_length(p)
	if length <= 0.0:
		return false
	var pt := _path_point(p, inst.path_position)
	var offset := inst.path_speed * (pt.z / 100.0) / (length * inst.path_scale)
	var npos := inst.path_position + offset
	var ended := false
	if npos <= 0.0 or npos >= 1.0:
		ended = true
		match int(inst.path_endaction):
			1, 2:
				npos = npos - 1.0 if npos >= 1.0 else npos + 1.0
			3:
				inst.path_speed = -inst.path_speed
				npos = clampf(npos, 0.0, 1.0)
			_:
				npos = clampf(npos, 0.0, 1.0)
				inst.path_index = -1.0
	inst.path_position = npos
	var np := _path_point(p, npos)
	var origin: Vector2 = inst.v.get("@path_origin", Vector2.ZERO)
	inst.x = origin.x + np.x * inst.path_scale
	inst.y = origin.y + np.y * inst.path_scale
	return ended

# ------------------------------------------------------------------ misc

static func f_sleep(s: GMInstance, ms: Variant) -> float:
	var m := ri(ms)
	if m > 0:
		OS.delay_msec(m)
	return 0.0

static func gv_current_time() -> float:
	return float((Time.get_ticks_usec() - start_usec) / 1000)

static func _now() -> Dictionary:
	return Time.get_datetime_dict_from_system()

static func gv_current_year() -> float:
	return float(_now().year)

static func gv_current_month() -> float:
	return float(_now().month)

static func gv_current_day() -> float:
	return float(_now().day)

static func gv_current_weekday() -> float:
	return float(_now().weekday)

static func gv_current_hour() -> float:
	return float(_now().hour)

static func gv_current_minute() -> float:
	return float(_now().minute)

static func gv_current_second() -> float:
	return float(_now().second)

static func gv_instance_count() -> float:
	return float(_active_snapshot().size())

static func gv_instance_id() -> float:
	return 0.0

static func gv_fps() -> float:
	return room_speed

static func f_show_image(s: GMInstance, fname: Variant, _full: Variant, delay: Variant) -> float:
	var path := real_path(fname)
	if FileAccess.file_exists(path):
		var img := _load_image(path)
		if img:
			var tex := ImageTexture.create_from_image(img)
			var cmds := [[OP_STATE, false, Color.WHITE],
				[OP_POLY, _rect_pts(0, 0, screen_w, screen_h), _cols4(Color.BLACK)],
				[OP_TEX, tex, Rect2(Vector2.ZERO, img.get_size()), Transform2D(0.0,
					Vector2((screen_w - img.get_width()) / 2.0, (screen_h - img.get_height()) / 2.0)), Color.WHITE]]
			_publish(cmds)
	OS.delay_msec(maxi(ri(delay), 0))
	return 0.0

static func f_show_info(s: GMInstance) -> float:
	return 0.0

static func f_load_info(s: GMInstance, _fname: Variant) -> float:
	return 0.0

static func f_show_error(s: GMInstance, msg: Variant, abort: Variant) -> float:
	push_error("[GML show_error] " + str(msg))
	if t(abort):
		scene_change = ["end"]
	return 0.0

static func f_message_alpha(s: GMInstance, _a: Variant) -> float:
	return 0.0

static func f_message_background(s: GMInstance, _b: Variant) -> float:
	return 0.0

static func f_message_button(s: GMInstance, _b: Variant) -> float:
	return 0.0

static func f_message_button_font(s: GMInstance, _n: Variant, _sz: Variant, _c: Variant, _st: Variant) -> float:
	return 0.0

static func f_message_text_font(s: GMInstance, _n: Variant, _sz: Variant, _c: Variant, _st: Variant) -> float:
	return 0.0

static func f_game_save(s: GMInstance, _fname: Variant) -> float:
	_error("game_save is not supported by the port")
	return 0.0

static func f_game_load(s: GMInstance, _fname: Variant) -> float:
	_error("game_load is not supported by the port")
	return 0.0
