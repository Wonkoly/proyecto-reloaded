## Checks that room scenes load as the same room as the extracted JSON (for freshly generated,
## unedited scenes). Run through tools/rooms.sh --check Room... ; prints the differences.
extends SceneTree

func _init() -> void:
	var bad := 0
	for r in OS.get_cmdline_user_args():
		if r.begins_with("--"):
			continue
		var errs := check(r)
		print("%s: %s" % [r, "igual al original" if errs.is_empty() else "%d diferencias" % errs.size()])
		for e in errs.slice(0, 20):
			print("  ", e)
		bad += 1 if not errs.is_empty() else 0
	quit(1 if bad else 0)

func check(r: String) -> Array:
	var errs := []
	var path := "res://rooms/%s.tscn" % GMRoomData.file_name(r)
	var orig = GMRoomData.json("rooms/%s.json" % GMRoomData.file_name(r))
	if not ResourceLoader.exists(path) or not orig is Dictionary:
		return ["falta la escena o el mapa original"]
	var root = (load(path) as PackedScene).instantiate()
	var d: Dictionary = root.to_dict()
	root.free()
	for k in ["width", "height", "speed", "persistent", "caption", "bg_colour", "clear_screen",
			"views_enabled", "creation_code", "backgrounds", "views"]:
		if not _same(orig[k], d[k]):
			errs.append("%s: %s != %s" % [k, orig[k], d[k]])
	if orig.instances.size() != d.instances.size():
		errs.append("instancias: %d != %d" % [orig.instances.size(), d.instances.size()])
	else:
		for i in orig.instances.size():
			if not _same(orig.instances[i], d.instances[i]):
				errs.append("instancia %d: %s != %s" % [i, orig.instances[i], d.instances[i]])
	errs.append_array(_check_tiles(orig.tiles, d.tiles))
	return errs

## Same tiles (ids only where the scene keeps them), and every pair of overlapping tiles of the
## same depth in the same order.
func _check_tiles(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return ["tiles: %d != %d" % [a.size(), b.size()]]
	var keyed := {}
	for i in b.size():
		var k := _tile_key(b[i])
		if not keyed.has(k):
			keyed[k] = []
		keyed[k].append(i)
	var pos := [] # position in b of each tile of a
	for t in a:
		var lst = keyed.get(_tile_key(t))
		if lst == null or lst.is_empty():
			return ["tile %d (%s) no está en la escena" % [int(t.id), _tile_key(t)]]
		var j: int = lst.pop_front()
		if int(b[j].id) < GMTileDepth.LAYER_ID_BASE and int(b[j].id) != int(t.id):
			return ["tile %d: id %d" % [int(t.id), int(b[j].id)]]
		pos.append(j)
	# Overlapping pairs, found through a coarse grid of the tiles' rectangles.
	var errs := []
	var grid := {}
	for i in a.size():
		var r := _rect(a[i])
		for gy in range(floori(r.position.y / 64), floori(r.end.y / 64) + 1):
			for gx in range(floori(r.position.x / 64), floori(r.end.x / 64) + 1):
				var g := Vector3i(gx, gy, int(a[i].depth))
				for k in grid.get(g, []):
					if pos[k] > pos[i] and _rect(a[k]).intersects(r):
						errs.append("orden: tile %d quedó encima de %d" % [int(a[k].id), int(a[i].id)])
				if not grid.has(g):
					grid[g] = []
				grid[g].append(i)
	return errs

func _tile_key(t: Dictionary) -> String:
	return "%s %s %s %d %d %d %d %s %s %s %d" % [t.bg, float(t.x), float(t.y), int(t.tx), int(t.ty),
		int(t.w), int(t.h), float(t.depth), float(t.xscale), float(t.yscale), int(t.blend)]

func _rect(t: Dictionary) -> Rect2:
	return Rect2(float(t.x), float(t.y), float(t.w) * float(t.xscale), float(t.h) * float(t.yscale)).abs()

## Deep equality where numbers compare by value (JSON ints vs Godot floats).
func _same(x: Variant, y: Variant) -> bool:
	if (x is int or x is float) and (y is int or y is float):
		return float(x) == float(y)
	if x is Dictionary and y is Dictionary:
		if x.size() != y.size():
			return false
		for k in x:
			if not y.has(k) or not _same(x[k], y[k]):
				return false
		return true
	if x is Array and y is Array:
		if x.size() != y.size():
			return false
		for i in x.size():
			if not _same(x[i], y[i]):
				return false
		return true
	return typeof(x) == typeof(y) and x == y
