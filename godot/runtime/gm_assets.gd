## All game assets: loaded from the exported game folder (`root`) and the generated code.
class_name GMAssets
extends RefCounted

class BgAsset:
	var name := ""
	var width := 0
	var height := 0
	var path := ""
	var _tex: Texture2D
	var _img: Image
	func texture() -> Texture2D:
		if _tex == null and path != "":
			_img = Image.load_from_file(path)
			_tex = ImageTexture.create_from_image(_img)
		return _tex
	func set_image(img: Image) -> void:
		_img = img
		width = img.get_width()
		height = img.get_height()
		_tex = ImageTexture.create_from_image(img)

class FontAsset:
	var name := ""
	var sys_name := ""
	var size := 12
	var bold := false
	var italic := false
	var path := ""
	## char code -> [x, y, w, h, offset, advance]
	var glyphs: Dictionary = {}
	var line_height := 0
	var _tex: Texture2D
	func texture() -> Texture2D:
		if _tex == null and path != "":
			_tex = ImageTexture.create_from_image(Image.load_from_file(path))
		return _tex

class SoundAsset:
	var name := ""
	var path := ""
	var kind := 0
	var volume := 1.0
	var pan := 0.0

## Folder with `_internal/` (assets from the exe) and the original `data/` folder.
static var root := ""
static var index: Dictionary = {}
static var settings: Dictionary = {}
static var sprites: Array = []
static var backgrounds: Array = []
static var fonts: Array = []
static var sounds: Array = []
static var objects: Array = []
static var room_names: Array = []
static var room_order: Array = []
static var script_names: Array = []
static var script_raw: Dictionary = {}
static var paths: Array = []
static var _rooms: Dictionary = {}
static var _scripts: Dictionary = {}
static var _script_ids: Dictionary = {}

static func internal(rel: String) -> String:
	return root.path_join("_internal").path_join(rel)

static func _json(rel: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(internal(rel)))

static func load_all(game_root: String) -> void:
	root = game_root
	index = _json("index.json")
	settings = _json("settings.json")
	script_raw = _json("scripts_raw.json")
	room_order = _json("room_order.json")
	paths = _json("paths.json")
	room_names = index.rooms
	script_names = index.scripts
	for i in script_names.size():
		if script_names[i] != null:
			_script_ids[script_names[i]] = i

	for n in index.sprites:
		var spr := GMSprite.new()
		if n != null:
			var dir := internal("sprites").path_join(_file_name(n))
			var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))
			spr.name = n
			spr._dir = dir
			spr.frames = int(m.frames)
			spr.width = int(m.width) if m.width != null else 0
			spr.height = int(m.height) if m.height != null else 0
			spr.origin_x = int(m.origin_x)
			spr.origin_y = int(m.origin_y)
			spr.per_frame_colliders = m.per_frame_colliders
			_load_colliders(spr, m.colliders, dir)
		sprites.append(spr if n != null else null)

	for n in index.backgrounds:
		var bg := BgAsset.new()
		if n != null:
			bg.name = n
			bg.path = internal("backgrounds").path_join(_file_name(n) + ".png")
			if FileAccess.file_exists(bg.path):
				var img := Image.load_from_file(bg.path)
				bg.width = img.get_width()
				bg.height = img.get_height()
			else:
				bg.path = ""
		backgrounds.append(bg if n != null else null)

	for n in index.fonts:
		if n == null:
			fonts.append(null)
			continue
		var f := FontAsset.new()
		var m: Dictionary = _json("fonts/%s.json" % _file_name(n))
		f.name = n
		f.sys_name = m.sys_name
		f.size = int(m.size)
		f.bold = m.bold
		f.italic = m.italic
		var p := internal("fonts").path_join(_file_name(n) + ".png")
		f.path = p if FileAccess.file_exists(p) else ""
		for g in m.glyphs:
			# The dump stores the glyph map as u32; offsets can be negative.
			var vals := [int(g.x), int(g.y), int(g.w), int(g.h), int(g.offset), int(g.advance)]
			for k in vals.size():
				if vals[k] >= 2147483648:
					vals[k] -= 4294967296
			f.glyphs[int(g.char)] = vals
			f.line_height = maxi(f.line_height, int(g.h))
		fonts.append(f)

	var smeta: Dictionary = _json("sounds/sounds.json")
	for n in index.sounds:
		if n == null:
			sounds.append(null)
			continue
		var s := SoundAsset.new()
		var m: Dictionary = smeta.get(n, {})
		s.name = n
		if m.get("has_data", false):
			s.path = internal("sounds").path_join(m.file)
		s.kind = int(m.get("kind", 0))
		s.volume = float(m.get("volume", 1.0))
		s.pan = float(m.get("pan", 0.0))
		sounds.append(s)

	_load_objects()

static func _load_colliders(spr: GMSprite, cols: Array, dir: String) -> void:
	var first := true
	for i in cols.size():
		var c: Dictionary = cols[i]
		var col := {"left": int(c.left), "top": int(c.top), "right": int(c.right), "bottom": int(c.bottom),
			"w": int(c.w), "h": int(c.h), "full": c.full, "mask": PackedByteArray()}
		if not c.full:
			var img := Image.load_from_file(dir.path_join("mask%d.png" % i))
			img.convert(Image.FORMAT_L8)
			col.mask = img.get_data()
		spr.colliders.append(col)
		if first:
			spr.bbox_left = col.left
			spr.bbox_top = col.top
			spr.bbox_right = col.right
			spr.bbox_bottom = col.bottom
			first = false
		else:
			spr.bbox_left = mini(spr.bbox_left, col.left)
			spr.bbox_top = mini(spr.bbox_top, col.top)
			spr.bbox_right = maxi(spr.bbox_right, col.right)
			spr.bbox_bottom = maxi(spr.bbox_bottom, col.bottom)

static var _events_index: Dictionary = {}

static func _load_objects() -> void:
	_events_index = JSON.parse_string(FileAccess.get_file_as_string("res://gen/events.json"))
	var names: Array = index.objects
	objects.resize(names.size())
	for i in names.size():
		if names[i] == null:
			continue
		var m: Dictionary = _json("objects/%s.json" % _file_name(names[i]))
		var o := GMObject.new()
		o.index = i
		o.name = names[i]
		o.sprite_index = float(names_lookup("sprites", m.sprite))
		o.mask_index = float(names_lookup("sprites", m.mask))
		o.solid = m.solid
		o.visible = m.visible
		o.depth = float(m.depth)
		o.persistent = m.persistent
		o.parent = names_lookup("objects", m.parent)
		for ev in _events_index.get(o.name, []):
			o.own_events[ev] = i
		objects[i] = o
	# Ancestors, then inherited event tables (own events win over the parent's).
	for o: GMObject in objects:
		if o == null:
			continue
		var p := o.index
		var guard := 0
		while p >= 0 and guard < 64:
			o.ancestors.append(p)
			var po: GMObject = objects[p]
			p = po.parent if po else -1
			guard += 1
		for a in range(o.ancestors.size() - 1, -1, -1):
			var ao: GMObject = objects[o.ancestors[a]]
			for ev in ao.own_events:
				o.events[ev] = ao.own_events[ev]
	for o: GMObject in objects:
		if o != null:
			o.children = _descendants(o.index)

static func _descendants(idx: int) -> Array[int]:
	var out: Array[int] = [idx]
	for o: GMObject in objects:
		if o != null and o.parent == idx and o.index != idx:
			out.append_array(_descendants(o.index))
	return out

static func names_lookup(kind: String, n: Variant) -> int:
	if n == null:
		return -1
	return (index[kind] as Array).find(n)

static func _file_name(n: String) -> String:
	var out := ""
	for c in n:
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c == "_" or c == "-") else "_"
	return out

static func sprite(i: float) -> GMSprite:
	var k := int(i)
	if k < 0 or k >= sprites.size():
		return null
	return sprites[k]

static func background(i: float) -> BgAsset:
	var k := int(i)
	if k < 0 or k >= backgrounds.size():
		return null
	return backgrounds[k]

static func font(i: float) -> FontAsset:
	var k := int(i)
	if k < 0 or k >= fonts.size():
		return null
	return fonts[k]

static func object(i: float) -> GMObject:
	var k := int(i)
	if k < 0 or k >= objects.size():
		return null
	return objects[k]

static func room(i: float) -> Dictionary:
	var k := int(i)
	if k < 0 or k >= room_names.size() or room_names[k] == null:
		return {}
	if not _rooms.has(k):
		_rooms[k] = _json("rooms/%s.json" % _file_name(room_names[k]))
	return _rooms[k]

## Callable for a compiled object event; the object's generated script loads on first use.
static func event_callable(owner: int, ev: String) -> Callable:
	var o: GMObject = objects[owner]
	var c = o.callables.get(ev)
	if c == null:
		if o.code == null:
			o.code = load("res://gen/objects/O_%s.gd" % o.name)
		c = Callable(o.code, "e_" + ev)
		o.callables[ev] = c
	return c

static func object_script_paths() -> Array:
	var out := []
	for o: GMObject in objects:
		if o != null and not o.own_events.is_empty():
			out.append("res://gen/objects/O_%s.gd" % o.name)
	return out

static func script_paths() -> Array:
	var out := []
	for n in script_names:
		if n != null:
			out.append("res://gen/scripts/S_%s.gd" % n)
	return out

## Script index -> Callable to its generated static function (S_<name>.f).
static func script_callable(i: float) -> Callable:
	var k := int(i)
	if _scripts.has(k):
		return _scripts[k]
	var c := Callable()
	if k >= 0 and k < script_names.size() and script_names[k] != null:
		c = Callable(load("res://gen/scripts/S_%s.gd" % script_names[k]), "f")
	_scripts[k] = c
	return c

static func script_id(n: String) -> int:
	return _script_ids.get(n, -1)
