## Main-thread host: starts the game thread, renders its frames with RenderingServer,
## forwards input and plays audio.
extends Node2D

## Folder holding `_internal/` and `data/`. Empty = next to the executable (exported game)
## or ../gamedata (running from the editor).
@export var game_root := ""

var _thread: Thread
var _items: Array[RID] = []
var _materials: Dictionary = {}
var _fog_shader: Shader
var _frame_size := Vector2i(640, 480)
var _audio: Node

const VK := {
	KEY_BACKSPACE: 8, KEY_TAB: 9, KEY_ENTER: 13, KEY_KP_ENTER: 13, KEY_SHIFT: 16, KEY_CTRL: 17,
	KEY_ALT: 18, KEY_PAUSE: 19, KEY_CAPSLOCK: 20, KEY_ESCAPE: 27, KEY_SPACE: 32, KEY_PAGEUP: 33,
	KEY_PAGEDOWN: 34, KEY_END: 35, KEY_HOME: 36, KEY_LEFT: 37, KEY_UP: 38, KEY_RIGHT: 39, KEY_DOWN: 40,
	KEY_PRINT: 44, KEY_INSERT: 45, KEY_DELETE: 46, KEY_KP_0: 96, KEY_KP_1: 97, KEY_KP_2: 98,
	KEY_KP_3: 99, KEY_KP_4: 100, KEY_KP_5: 101, KEY_KP_6: 102, KEY_KP_7: 103, KEY_KP_8: 104,
	KEY_KP_9: 105, KEY_KP_MULTIPLY: 106, KEY_KP_ADD: 107, KEY_KP_SUBTRACT: 109, KEY_KP_PERIOD: 110,
	KEY_KP_DIVIDE: 111, KEY_F1: 112, KEY_F2: 113, KEY_F3: 114, KEY_F4: 115, KEY_F5: 116, KEY_F6: 117,
	KEY_F7: 118, KEY_F8: 119, KEY_F9: 120, KEY_F10: 121, KEY_F11: 122, KEY_F12: 123,
	KEY_SEMICOLON: 186, KEY_EQUAL: 187, KEY_COMMA: 188, KEY_MINUS: 189, KEY_PERIOD: 190,
	KEY_SLASH: 191, KEY_QUOTELEFT: 192, KEY_BRACKETLEFT: 219, KEY_BACKSLASH: 220,
	KEY_BRACKETRIGHT: 221, KEY_APOSTROPHE: 222,
}

func _ready() -> void:
	_fog_shader = Shader.new()
	_fog_shader.code = """
shader_type canvas_item;
uniform vec4 fog_color : source_color;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(fog_color.rgb, t.a * COLOR.a);
}
"""
	_setup_snapshots()
	_setup_input_script()
	_audio = preload("res://runtime/gm_audio.gd").new()
	add_child(_audio)
	var root := game_root
	if root == "":
		if OS.has_feature("editor"):
			root = ProjectSettings.globalize_path("res://").path_join("../gamedata").simplify_path()
		else:
			root = OS.get_executable_path().get_base_dir()
	_thread = Thread.new()
	_thread.start(GM.run.bind(root))

func _exit_tree() -> void:
	GM.running = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	if GM._preloader and GM._preloader.is_started():
		GM._preloader.wait_to_finish()

## Debug: GM_SNAPSHOTS="dir:interval_s:count" saves numbered screenshots, then quits.
var _snap_dir := ""
var _snap_every := 0.0
var _snap_left := 0
var _snap_t := 0.0
var _snap_i := 0

func _setup_snapshots() -> void:
	var spec := OS.get_environment("GM_SNAPSHOTS")
	if spec == "":
		return
	var parts := spec.split(":")
	_snap_dir = parts[0]
	_snap_every = float(parts[1]) if parts.size() > 1 else 2.0
	_snap_left = int(parts[2]) if parts.size() > 2 else 10
	DirAccess.make_dir_recursive_absolute(_snap_dir)

## Debug: GM_INPUT="t:vk,t:vk,..." taps virtual key vk at t seconds (held 0.15 s).
var _script_keys: Array = []
var _script_t := 0.0

func _setup_input_script() -> void:
	for item in OS.get_environment("GM_INPUT").split(",", false):
		var kv := item.split(":")
		_script_keys.append([float(kv[0]), int(kv[1]), false])

func _input_script(delta: float) -> void:
	_script_t += delta
	for k in _script_keys:
		if not k[2] and _script_t >= k[0]:
			GM.push_input(["down", k[1]])
			k[2] = true
		elif k[2] and k[0] >= 0.0 and _script_t >= k[0] + 0.15:
			GM.push_input(["up", k[1]])
			k[0] = -1.0

func _snapshots(delta: float) -> void:
	if _snap_dir == "":
		return
	_snap_t += delta
	if _snap_t >= _snap_every:
		_snap_t = 0.0
		get_viewport().get_texture().get_image().save_png(_snap_dir.path_join("snap_%03d.png" % _snap_i))
		_snap_i += 1
		_snap_left -= 1
		if _snap_left <= 0:
			get_tree().quit()

func _process(_delta: float) -> void:
	_snapshots(_delta)
	_input_script(_delta)
	for cmd in GM.take_commands():
		_system_command(cmd)
	var f = GM.take_frame()
	if f != null:
		_render(f)
	var win := get_window()
	GM.window_state.fullscreen = win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	GM.window_state.w = win.size.x
	GM.window_state.h = win.size.y
	GM.window_state.x = win.position.x
	GM.window_state.y = win.position.y
	var dm := DisplayServer.mouse_get_position()
	GM.window_state.dmx = dm.x
	GM.window_state.dmy = dm.y
	# Scripted test runs keep the real mouse out of the game.
	GM.push_input(["mouse", Vector2(-1000, -1000) if not _script_keys.is_empty() else get_local_mouse_position()])
	GM.set_sound_playing(_audio.playing_state())

# ------------------------------------------------------------------ rendering

func _material(fog: bool, col: Color) -> RID:
	if not fog:
		return RID()
	var key := col.to_html()
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = _fog_shader
		m.set_shader_parameter("fog_color", col)
		_materials[key] = m
	return _materials[key].get_rid()

func _item(i: int) -> RID:
	while _items.size() <= i:
		var it := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(it, get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(it, _items.size())
		RenderingServer.canvas_item_set_default_texture_filter(it, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
		_items.append(it)
	return _items[i]

func _render(f: Dictionary) -> void:
	var size := Vector2i(f.w, f.h)
	if size != _frame_size:
		_frame_size = size
		get_window().content_scale_size = size
	for it in _items:
		RenderingServer.canvas_item_clear(it)
	var idx := -1
	var it := RID()
	var xf_set := false
	for c in f.cmds:
		match c[0]:
			GMLibDraw.OP_STATE:
				idx += 1
				it = _item(idx)
				RenderingServer.canvas_item_set_material(it, _material(c[1], c[2]))
				xf_set = false
			GMLibDraw.OP_TEX:
				var tex: Texture2D = c[1]
				var src: Rect2 = c[2]
				RenderingServer.canvas_item_add_set_transform(it, c[3])
				RenderingServer.canvas_item_add_texture_rect_region(it, Rect2(Vector2.ZERO, src.size), tex.get_rid(), src, c[4])
				xf_set = true
			GMLibDraw.OP_POLY:
				if xf_set:
					RenderingServer.canvas_item_add_set_transform(it, Transform2D.IDENTITY)
					xf_set = false
				RenderingServer.canvas_item_add_polygon(it, c[1], c[2])
			GMLibDraw.OP_LINE:
				if xf_set:
					RenderingServer.canvas_item_add_set_transform(it, Transform2D.IDENTITY)
					xf_set = false
				RenderingServer.canvas_item_add_line(it, c[1], c[2], c[3], c[5])
			GMLibDraw.OP_PRIM:
				if xf_set:
					RenderingServer.canvas_item_add_set_transform(it, Transform2D.IDENTITY)
					xf_set = false
				RenderingServer.canvas_item_add_primitive(it, c[2], c[4], c[3], c[1].get_rid())
			GMLibDraw.OP_SYSTEXT:
				if xf_set:
					RenderingServer.canvas_item_add_set_transform(it, Transform2D.IDENTITY)
					xf_set = false
				ThemeDB.fallback_font.draw_string(it, c[2], c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, c[4], c[3])

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.echo:
			if event.pressed and event.unicode > 0:
				GM.push_input(["char", String.chr(event.unicode)])
			return
		var vk := _vk(event)
		if vk > 0:
			GM.push_input(["down" if event.pressed else "up", vk])
			# Windows also reports left/right specific modifier codes.
			match event.keycode:
				KEY_SHIFT:
					GM.push_input(["down" if event.pressed else "up", 160 if event.location != KEY_LOCATION_RIGHT else 161])
				KEY_CTRL:
					GM.push_input(["down" if event.pressed else "up", 162 if event.location != KEY_LOCATION_RIGHT else 163])
				KEY_ALT:
					GM.push_input(["down" if event.pressed else "up", 164 if event.location != KEY_LOCATION_RIGHT else 165])
		if event.pressed:
			if event.keycode == KEY_BACKSPACE:
				GM.push_input(["char", "\b"])
			elif event.unicode > 0:
				GM.push_input(["char", String.chr(event.unicode)])
	elif event is InputEventMouseButton:
		var b := 0
		match event.button_index:
			MOUSE_BUTTON_LEFT: b = 1
			MOUSE_BUTTON_RIGHT: b = 2
			MOUSE_BUTTON_MIDDLE: b = 3
		if b > 0:
			GM.push_input(["mdown" if event.pressed else "mup", b])

func _vk(e: InputEventKey) -> int:
	var k := e.keycode
	if k >= KEY_A and k <= KEY_Z:
		return k
	if k >= KEY_0 and k <= KEY_9:
		return k
	return VK.get(k, 0)

# ------------------------------------------------------------------ system commands

func _system_command(cmd: Array) -> void:
	match cmd[0]:
		"quit":
			get_tree().quit()
		"fullscreen":
			get_window().mode = Window.MODE_FULLSCREEN if cmd[1] else Window.MODE_WINDOWED
		"cursor":
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if cmd[1] == -1 else Input.MOUSE_MODE_VISIBLE
		"region_scale":
			if get_window().mode == Window.MODE_WINDOWED and cmd[1] > 0:
				get_window().size = Vector2i(_frame_size * cmd[1])
		"window_rect":
			get_window().position = cmd[1].position
			get_window().size = cmd[1].size
		"warp_mouse":
			get_viewport().warp_mouse(cmd[1])
		"warp_mouse_display":
			DisplayServer.warp_mouse(Vector2i(cmd[1]))
		"clipboard":
			DisplayServer.clipboard_set(cmd[1])
		"screenshot":
			get_viewport().get_texture().get_image().save_png(cmd[1])
		_:
			if String(cmd[0]).begins_with("snd_"):
				_audio.command(cmd)
