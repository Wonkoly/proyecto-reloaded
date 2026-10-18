## Creates room scenes (res://rooms/<Room>.tscn) from the extracted rooms. Run through tools/rooms.sh:
##   godot --headless --path godot --script res://rooms/editor/make_scenes.gd -- [--force] Room...
## Existing scenes are kept (they may have been edited) unless --force is given.
extends SceneTree

var _bg_index: Dictionary = {}    # background name -> GM index (used as the atlas source id)
var _referenced: Dictionary = {}  # tile ids that appear in the game's code -> true

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var force := "--force" in args
	var rooms := Array(args).filter(func(a): return not a.begins_with("--"))
	var idx = GMRoomData.json("index.json")
	if idx == null:
		printerr("no game data in ", GMRoomData.game_root())
		quit(1)
		return
	for i in idx.backgrounds.size():
		if idx.backgrounds[i] != null:
			_bg_index[idx.backgrounds[i]] = i
	_scan_tile_refs("res://gen")
	var failed := 0
	for r in rooms:
		var path := "res://rooms/%s.tscn" % GMRoomData.file_name(r)
		if ResourceLoader.exists(path) and not force:
			print("%s: ya existe, no se toca (usa --force para regenerarla)" % path)
			continue
		var d = GMRoomData.json("rooms/%s.json" % GMRoomData.file_name(r))
		if not d is Dictionary:
			printerr("no existe el mapa ", r)
			failed += 1
			continue
		var root := build(d)
		var packed := PackedScene.new()
		packed.pack(root)
		var err := ResourceSaver.save(packed, path)
		root.free()
		if err != OK:
			printerr("no se pudo guardar ", path, ": ", error_string(err))
			failed += 1
		else:
			print("%s: %d instancias, %d tiles" % [path, d.instances.size(), d.tiles.size()])
	quit(1 if failed else 0)

## Tile ids written in the generated code (the game deletes or fades some tiles by id): those
## tiles stay loose nodes so they keep their id.
func _scan_tile_refs(dir: String) -> void:
	var re := RegEx.create_from_string("\\b(10[0-9]{6})(\\.0)?\\b")
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			for m in re.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
				_referenced[int(m.get_string(1))] = true
	for sub in DirAccess.get_directories_at(dir):
		_scan_tile_refs(dir.path_join(sub))

func build(d: Dictionary) -> GMRoom:
	var root := GMRoom.new()
	root.name = d.name
	if String(root.name) != d.name:
		push_warning("el nombre del mapa %s no es válido como nombre de nodo" % d.name)
	root.width = int(d.width)
	root.height = int(d.height)
	root.speed = int(d.speed)
	root.persistent = d.persistent
	root.caption = d.caption
	root.bg_colour = GMRoomData.blend_to_color(int(d.bg_colour) | 0xFF000000)
	root.clear_screen = d.clear_screen
	root.views_enabled = d.views_enabled
	root.creation_code = d.creation_code
	var bgs: Array[Dictionary] = []
	bgs.assign(d.backgrounds)
	root.backgrounds = bgs
	var views: Array[Dictionary] = []
	views.assign(d.views)
	root.views = views

	var tiles_node := Node2D.new()
	tiles_node.name = "Tiles"
	root.add_child(tiles_node)
	var by_depth := {}
	for t in d.tiles:
		var dep := float(t.depth)
		if not by_depth.has(dep):
			by_depth[dep] = []
		by_depth[dep].append(t)
	var depths := by_depth.keys()
	depths.sort()
	depths.reverse() # back to front, like they are drawn
	var tilesets := {} # tile size -> TileSet shared by this room's layers
	for dep in depths:
		var dn := GMTileDepth.new()
		dn.name = "Depth %d" % dep if dep == floorf(dep) else "Depth %s" % dep
		dn.depth = int(dep)
		tiles_node.add_child(dn)
		_place_tiles(dn, by_depth[dep], tilesets)

	var inst_node := Node2D.new()
	inst_node.name = "Instances"
	root.add_child(inst_node)
	for idata in d.instances:
		var n := GMRoomInstance.new()
		n.from_dict(idata)
		n.name = idata.object
		inst_node.add_child(n, true)

	_set_owner(root, root)
	return root

func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)

## Puts the tiles of one depth into TileMapLayers and loose GMRoomTiles, keeping the draw order:
## a tile may only join an earlier layer if nothing placed after that layer overlaps it.
func _place_tiles(dn: GMTileDepth, tiles: Array, tilesets: Dictionary) -> void:
	var segs := [] # {layer: TileMapLayer or null, size, cells: {}, rects: []}
	for t in tiles:
		var rect := Rect2(float(t.x), float(t.y), float(t.w) * float(t.xscale), float(t.h) * float(t.yscale)).abs()
		var size := int(t.w)
		# Layers may be shifted off the origin (many rooms put tiles at 8 px on a 16 px grid).
		var off := Vector2i(posmod(int(t.x), size), posmod(int(t.y), size)) if size > 0 else Vector2i.ZERO
		var cell := (Vector2i(int(t.x), int(t.y)) - off) / size if size > 0 else Vector2i.ZERO
		var atlas := _atlas_coords(t, tilesets) if _grid_ok(t) else Vector2i(-1, -1)
		var placed := false
		if atlas.x >= 0:
			for k in range(segs.size() - 1, -1, -1):
				var s: Dictionary = segs[k]
				if s.layer != null and s.size == size and s.off == off and not s.cells.has(cell):
					s.layer.set_cell(cell, _bg_index[t.bg], atlas)
					s.cells[cell] = true
					placed = true
					break
				if _overlaps(s, rect):
					break
			if not placed:
				var layer := TileMapLayer.new()
				layer.name = "Tiles %dpx" % size + ("" if off == Vector2i.ZERO else " +%d+%d" % [off.x, off.y])
				layer.tile_set = tilesets[size]
				layer.position = Vector2(off)
				dn.add_child(layer, true)
				layer.set_cell(cell, _bg_index[t.bg], atlas)
				segs.append({"layer": layer, "size": size, "off": off, "cells": {cell: true}, "rects": []})
		else:
			var n := GMRoomTile.new()
			n.from_dict(t)
			n.name = "Tile %d" % int(t.id)
			dn.add_child(n, true)
			if segs.is_empty() or segs[-1].layer != null:
				segs.append({"layer": null, "size": 0, "off": Vector2i.ZERO, "cells": {}, "rects": []})
			segs[-1].rects.append(rect)

func _overlaps(s: Dictionary, r: Rect2) -> bool:
	if s.layer == null:
		for o: Rect2 in s.rects:
			if o.intersects(r):
				return true
		return false
	var sz: int = s.size
	r.position -= Vector2(s.off)
	for cy in range(floori(r.position.y / sz), ceili(r.end.y / sz)):
		for cx in range(floori(r.position.x / sz), ceili(r.end.x / sz)):
			if s.cells.has(Vector2i(cx, cy)):
				return true
	return false

## A plain square tile, which a TileMapLayer (on its grid, maybe shifted) can hold.
func _grid_ok(t: Dictionary) -> bool:
	var w := int(t.w)
	return w > 0 and w == int(t.h) and float(t.xscale) == 1.0 and float(t.yscale) == 1.0 \
		and int(t.blend) == 0xFFFFFFFF and int(t.tx) % w == 0 and int(t.ty) % w == 0 and _bg_index.has(t.bg) \
		and not _referenced.has(int(t.id))

## The tile's atlas coordinates in the room's TileSet for its size (adding the tileset as an atlas
## source the first time), or (-1, -1) if the tile isn't fully inside the image.
func _atlas_coords(t: Dictionary, tilesets: Dictionary) -> Vector2i:
	var size := int(t.w)
	if not tilesets.has(size):
		var ts := TileSet.new()
		ts.tile_size = Vector2i(size, size)
		tilesets[size] = ts
	var tset: TileSet = tilesets[size]
	var sid: int = _bg_index[t.bg]
	if not tset.has_source(sid):
		var tex := GMRoomData.background_texture(t.bg)
		if tex == null:
			return Vector2i(-1, -1)
		var src := TileSetAtlasSource.new()
		src.resource_name = t.bg
		src.texture = tex
		src.texture_region_size = Vector2i(size, size)
		var grid := Vector2i(tex.get_size()) / size
		for y in grid.y:
			for x in grid.x:
				src.create_tile(Vector2i(x, y))
		tset.add_source(src, sid)
	var src := tset.get_source(sid) as TileSetAtlasSource
	var ac := Vector2i(int(t.tx) / size, int(t.ty) / size)
	return ac if src.has_tile(ac) else Vector2i(-1, -1)
