## A single tile that doesn't fit a tile layer: a tile size other than square, scaled, tinted,
## off the grid, or one the game's code refers to by id (TileDestruye, TileSetAlpha).
## region_rect is the part of the background it shows; the depth is its parent's (GMTileDepth).
@tool
class_name GMRoomTile
extends Sprite2D

## Background (tileset) name, e.g. Tiles_W1.
@export var background := "":
	set(v):
		background = v
		if Engine.is_editor_hint():
			texture = GMRoomData.background_texture(v)
## GM8 tile id (0 = none: the game gets a fresh one when the room loads).
@export var gm_id := 0

func _init() -> void:
	centered = false
	region_enabled = true

func to_dict(depth: float) -> Dictionary:
	return {"bg": background, "id": gm_id, "x": position.x, "y": position.y,
		"tx": int(region_rect.position.x), "ty": int(region_rect.position.y),
		"w": int(region_rect.size.x), "h": int(region_rect.size.y), "depth": depth,
		"xscale": scale.x, "yscale": scale.y, "blend": GMRoomData.color_to_blend(modulate)}

func from_dict(d: Dictionary) -> void:
	background = d.bg
	if texture == null:
		texture = GMRoomData.background_texture(d.bg)
	gm_id = int(d.id)
	position = Vector2(float(d.x), float(d.y))
	region_rect = Rect2(float(d.tx), float(d.ty), float(d.w), float(d.h))
	scale = Vector2(float(d.xscale), float(d.yscale))
	modulate = GMRoomData.blend_to_color(int(d.blend))
