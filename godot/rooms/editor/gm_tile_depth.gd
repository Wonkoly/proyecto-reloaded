## All the tiles of one GM8 depth, as children drawn in order: TileMapLayers (paint on them with
## Godot's TileMap editor) and loose GMRoomTile sprites. Later children are drawn on top.
@tool
class_name GMTileDepth
extends Node2D

## GM8 tile depth: bigger is further back (instances have depths too; obj_Prota is 0).
## (An int: Godot doesn't save floats that are merely close to the default, like 1000001.)
@export var depth := 1000000:
	set(v):
		depth = v
		z_index = GMRoomData.depth_to_z(v)

## Ids for tiles read from layers: they only need to be unique within the room.
const LAYER_ID_BASE := 1_500_000_000

## The tiles as room-JSON entries, in draw order. `next_id` is a one-element counter.
func to_dicts(next_id: Array) -> Array:
	var dep := float(depth)
	var out := []
	for c in get_children():
		if c is GMRoomTile:
			out.append(c.to_dict(dep))
		elif c is TileMapLayer and c.tile_set:
			var cells: Array = c.get_used_cells()
			cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
			var ts: Vector2i = c.tile_set.tile_size
			var off: Vector2 = c.position
			var blend := GMRoomData.color_to_blend(c.modulate)
			for cell: Vector2i in cells:
				var src := c.tile_set.get_source(c.get_cell_source_id(cell)) as TileSetAtlasSource
				if src == null:
					continue
				var ac: Vector2i = c.get_cell_atlas_coords(cell)
				out.append({"bg": src.resource_name, "id": next_id[0], "x": cell.x * ts.x + off.x, "y": cell.y * ts.y + off.y,
					"tx": ac.x * ts.x, "ty": ac.y * ts.y, "w": ts.x, "h": ts.y, "depth": dep,
					"xscale": 1.0, "yscale": 1.0, "blend": blend})
				next_id[0] += 1
	return out
