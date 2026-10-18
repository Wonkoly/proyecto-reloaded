## Root of a room scene (res://rooms/<Room>.tscn). When such a scene exists the game loads the
## room from it instead of from the extracted JSON, so editing it in Godot changes the game.
##
##   <Room> (GMRoom)            room settings, backgrounds and views
##   ├─ Tiles                   one GMTileDepth per tile depth (TileMapLayers and loose tiles)
##   └─ Instances               GMRoomInstance nodes, in creation order (folders are allowed)
##
## Scenes are created by tools/rooms.sh from the extracted rooms; after that they are the source.
@tool
class_name GMRoom
extends Node2D

@export var width := 640:
	set(v):
		width = v
		queue_redraw()
@export var height := 480:
	set(v):
		height = v
		queue_redraw()
## Steps per second.
@export var speed := 30
@export var persistent := false
@export var caption := ""
@export var bg_colour := Color(0.75, 0.75, 0.75):
	set(v):
		bg_colour = v
		queue_redraw()
@export var clear_screen := true
@export var views_enabled := true
## GML run once when the room starts. Edits need the code to be regenerated (see GMRoomInstance).
@export_multiline var creation_code := ""
## The 8 GM8 background slots: {bg, visible, foreground, x, y, tile_h, tile_v, stretch, hspeed, vspeed}.
@export var backgrounds: Array[Dictionary] = []:
	set(v):
		backgrounds = v
		queue_redraw()
## The 8 GM8 views: {visible, x, y, w, h, port_x, port_y, port_w, port_h, follow, hborder, vborder, hspeed, vspeed}.
@export var views: Array[Dictionary] = []

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var room_rect := Rect2(0, 0, width, height)
	if clear_screen:
		draw_rect(room_rect, bg_colour)
	for b in backgrounds:
		if b.get("visible", false) and b.get("bg") != null and not b.get("foreground", false):
			_draw_background(b, room_rect)
	draw_rect(room_rect, Color(1, 1, 1, 0.6), false, 1.0)
	# The size of the first visible view, as a guide of what fits on screen.
	for v in views:
		if v.get("visible", false):
			draw_rect(Rect2(v.get("x", 0), v.get("y", 0), v.get("w", 320), v.get("h", 180)), Color(0.3, 0.8, 1, 0.5), false, 1.0)
			break

func _draw_background(b: Dictionary, room_rect: Rect2) -> void:
	var tex := GMRoomData.background_texture(b.bg)
	if tex == null:
		return
	var sz := tex.get_size()
	var x0: float = b.get("x", 0)
	var y0: float = b.get("y", 0)
	if b.get("tile_h", false):
		x0 = fposmod(x0, sz.x) - sz.x
	if b.get("tile_v", false):
		y0 = fposmod(y0, sz.y) - sz.y
	var y := y0
	while y < room_rect.size.y:
		var x := x0
		while x < room_rect.size.x:
			draw_texture(tex, Vector2(x, y))
			if not b.get("tile_h", false):
				break
			x += sz.x
		if not b.get("tile_v", false):
			break
		y += sz.y

## The room in the extracted-JSON format the game loads (see GMCore.load_room).
func to_dict() -> Dictionary:
	var tiles := []
	var next_id := [GMTileDepth.LAYER_ID_BASE]
	var tiles_node := get_node_or_null("Tiles")
	if tiles_node:
		for d in tiles_node.get_children():
			if d is GMTileDepth:
				tiles.append_array(d.to_dicts(next_id))
	var insts := []
	var inst_node := get_node_or_null("Instances")
	if inst_node:
		_collect_instances(inst_node, Transform2D.IDENTITY, insts)
	return {"name": name, "width": width, "height": height, "speed": speed, "persistent": persistent,
		"caption": caption, "bg_colour": GMRoomData.color_to_blend(bg_colour) & 0xFFFFFF,
		"clear_screen": clear_screen, "views_enabled": views_enabled, "creation_code": creation_code,
		"backgrounds": backgrounds, "views": views, "tiles": tiles, "instances": insts}

## Instances in tree order; plain nodes in between act as folders (their transform applies).
func _collect_instances(n: Node, xf: Transform2D, out: Array) -> void:
	for c in n.get_children():
		if c is GMRoomInstance:
			var d: Dictionary = c.to_dict()
			if xf != Transform2D.IDENTITY:
				var p: Vector2 = xf * c.position
				d.x = p.x
				d.y = p.y
			out.append(d)
		elif c is Node2D:
			_collect_instances(c, xf * c.transform, out)
		else:
			_collect_instances(c, xf, out)
