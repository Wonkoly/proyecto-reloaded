## Shared helpers for room scenes (res://rooms/*.tscn): where the game data lives, object and
## sprite info for the editor previews, and GM8 <-> Godot conversions used both when the scenes
## are generated and when the game reads them.
@tool
class_name GMRoomData
extends RefCounted

## Folder of the extracted game (the one with _internal/): GM_ROOT, or ../gamedata next to the project.
static func game_root() -> String:
	var r := OS.get_environment("GM_ROOT")
	if r == "":
		r = ProjectSettings.globalize_path("res://").path_join("../gamedata").simplify_path()
	return r

static func internal(rel: String) -> String:
	return game_root().path_join("_internal").path_join(rel)

static var _json_cache: Dictionary = {}

static func json(rel: String) -> Variant:
	if not _json_cache.has(rel):
		var txt := FileAccess.get_file_as_string(internal(rel))
		_json_cache[rel] = JSON.parse_string(txt) if txt != "" else null
	return _json_cache[rel]

## Same file-name mangling as GMAssets._file_name (asset names -> folder/file names).
static func file_name(n: String) -> String:
	var out := ""
	for c in n:
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c == "_" or c == "-") else "_"
	return out

static func object_names() -> Array:
	var idx = json("index.json")
	return idx.objects.filter(func(n): return n != null) if idx else []

## {sprite, depth, visible} of an object, or {} if unknown.
static func object_info(obj: String) -> Dictionary:
	if obj == "":
		return {}
	var o = json("objects/%s.json" % file_name(obj))
	return o if o is Dictionary else {}

## Frame 0 of a sprite with its origin: [Texture2D, Vector2 origin], or [] if it has none.
static var _sprite_cache: Dictionary = {}

static func sprite_preview(spr: String) -> Array:
	if _sprite_cache.has(spr):
		return _sprite_cache[spr]
	var out := []
	var dir := internal("sprites").path_join(file_name(spr))
	var m = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))
	if m is Dictionary and int(m.get("frames", 0)) > 0:
		var img := Image.load_from_file(dir.path_join("0.png"))
		if img:
			out = [ImageTexture.create_from_image(img), Vector2(float(m.origin_x), float(m.origin_y))]
	_sprite_cache[spr] = out
	return out

## Background image for the editor (imported copy in res://rooms/backgrounds/, made by the generator).
static func background_texture(bg: String) -> Texture2D:
	var p := "res://rooms/backgrounds/%s.png" % file_name(bg)
	return load(p) if ResourceLoader.exists(p) else null

## GM8 blend (0xAABBGGRR as stored in rooms) <-> Godot modulate.
static func blend_to_color(blend: int) -> Color:
	return Color8(blend & 0xFF, (blend >> 8) & 0xFF, (blend >> 16) & 0xFF, (blend >> 24) & 0xFF)

static func color_to_blend(c: Color) -> int:
	return c.r8 | (c.g8 << 8) | (c.b8 << 16) | (c.a8 << 24)

## Editor draw order for a GM depth (bigger depth = further back), compressed into z_index range.
static func depth_to_z(depth: float) -> int:
	var z := log(1.0 + absf(depth)) / log(2.0) * 100.0
	return clampi(int(-signf(depth) * z), -4000, 4000)
