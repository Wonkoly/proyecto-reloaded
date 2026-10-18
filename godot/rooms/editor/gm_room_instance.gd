## One instance placed in a room scene. Position, rotation and scale are the node's own; the
## object, id and creation code are properties. In the editor it draws the object's sprite
## (or a marker with its name if it has none, like walls and controllers).
@tool
class_name GMRoomInstance
extends Node2D

## Object name (obj_Prota, obj_pared…). The inspector suggests the game's objects.
@export var object := "":
	set(v):
		object = v
		_refresh()
## GM8 instance id. The game's code refers to some instances by id, so keep it; new and
## duplicated instances get a fresh one automatically.
@export var gm_id := 0
## GML run when the instance is created (before its create event). Edits need the code to be
## regenerated: tools/gml2gd/target/release/gml2gd gen extracted godot
@export_multiline var creation_code := ""

const NEW_ID_BASE := 1_000_000_000

var _tex: Texture2D
var _origin := Vector2.ZERO
var _invisible := false

func _validate_property(p: Dictionary) -> void:
	if p.name == "object" and Engine.is_editor_hint():
		p.hint = PROPERTY_HINT_ENUM_SUGGESTION
		p.hint_string = ",".join(GMRoomData.object_names())

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	# Added or duplicated in the editor: needs an id no other instance of this room uses.
	var room := get_parent()
	if gm_id == 0 or (room and _id_taken(room)):
		gm_id = NEW_ID_BASE + randi() % 1_000_000_000
		while room and _id_taken(room):
			gm_id = NEW_ID_BASE + randi() % 1_000_000_000
	_refresh()

func _id_taken(parent: Node) -> bool:
	for c in parent.get_children():
		if c != self and c is GMRoomInstance and c.gm_id == gm_id:
			return true
	return false

func _refresh() -> void:
	if not Engine.is_editor_hint():
		return
	var info := GMRoomData.object_info(object)
	_tex = null
	_invisible = not info.get("visible", true)
	var spr = info.get("sprite")
	if spr != null:
		var p := GMRoomData.sprite_preview(spr)
		if not p.is_empty():
			_tex = p[0]
			_origin = p[1]
	z_index = GMRoomData.depth_to_z(float(info.get("depth", 0)))
	queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if _tex:
		draw_texture(_tex, -_origin, Color(1, 1, 1, 0.45) if _invisible else Color.WHITE)
	else:
		draw_rect(Rect2(-4, -4, 8, 8), Color(1, 0.5, 0, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(6, 4), object, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)

## The instance as a room-JSON entry.
func to_dict() -> Dictionary:
	return {"object": object, "id": gm_id, "x": position.x, "y": position.y,
		"xscale": scale.x, "yscale": scale.y, "angle": -rotation_degrees,
		"blend": GMRoomData.color_to_blend(modulate), "creation_code": creation_code}

func from_dict(d: Dictionary) -> void:
	object = d.object
	gm_id = int(d.id)
	position = Vector2(float(d.x), float(d.y))
	scale = Vector2(float(d.xscale), float(d.yscale))
	rotation_degrees = -float(d.angle)
	modulate = GMRoomData.blend_to_color(int(d.blend))
	creation_code = d.creation_code
