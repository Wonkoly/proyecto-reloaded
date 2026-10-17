## In-game developer console (main thread), drawn over the game with its own dialog font.
## F1 or º/` opens and closes it; while open it takes the keyboard. Commands go to GMDev.
extends Node2D

const FONT := "FuenteDialogo"
const LINE_H := 11
const SHOWN := 9 # output lines above the prompt

var is_open := false
var _text := ""
var _history: PackedStringArray = []
var _hist_i := 0
var _lines: PackedStringArray = [] # wrapped output
var _cursor := 0
var _scroll := 0
var _blink := 0.0
var _glyphs: Dictionary = {}
var _tex: Texture2D

func _ready() -> void:
	z_index = 100

func _load_font() -> bool:
	if _tex:
		return true
	var fi := GMAssets.names_lookup("fonts", FONT) if not GMAssets.index.is_empty() else -1
	if fi < 0 or fi >= GMAssets.fonts.size() or GMAssets.fonts[fi] == null or GMAssets.fonts[fi].path == "":
		return false
	var f = GMAssets.fonts[fi]
	_glyphs = f.glyphs
	_tex = ImageTexture.create_from_image(Image.load_from_file(f.path))
	return true

## Returns true when the event was used by the console and must not reach the game.
func handle_key(e: InputEventKey) -> bool:
	# F1, or the key left of 1 (º on Spanish keyboards, ` on US ones).
	if e.pressed and not e.echo and (e.keycode == KEY_F1 or e.physical_keycode == KEY_QUOTELEFT):
		is_open = not is_open
		queue_redraw()
		return true
	if not is_open:
		return false
	if not e.pressed:
		return false # let releases through so keys held before opening don't stick in the game
	match e.keycode:
		KEY_ESCAPE:
			is_open = false
		KEY_ENTER, KEY_KP_ENTER:
			if _text.strip_edges() != "":
				_history.append(_text)
				GMDev.push(_text)
			_hist_i = _history.size()
			_text = ""
			_scroll = 0
		KEY_BACKSPACE:
			_text = _text.left(-1)
		KEY_UP:
			if not _history.is_empty():
				_hist_i = maxi(_hist_i - 1, 0)
				_text = _history[_hist_i]
		KEY_DOWN:
			_hist_i = mini(_hist_i + 1, _history.size())
			_text = _history[_hist_i] if _hist_i < _history.size() else ""
		KEY_PAGEUP:
			_scroll = mini(_scroll + SHOWN - 1, maxi(_lines.size() - SHOWN, 0))
		KEY_PAGEDOWN:
			_scroll = maxi(_scroll - (SHOWN - 1), 0)
		KEY_TAB:
			_complete()
		_:
			if e.unicode >= 32:
				_text += String.chr(e.unicode)
	_blink = 0.0
	queue_redraw()
	return true

func _complete() -> void:
	var c := GMDev.complete(_text)
	if c.size() == 1:
		_text = c[0]
	elif c.size() > 1:
		var p := c[0]
		for s in c:
			while not s.to_lower().begins_with(p.to_lower()):
				p = p.left(-1)
		if p.length() > _text.length():
			_text = p
		else:
			var names := []
			for s in c.slice(0, 40):
				names.append(s.get_slice(" ", 1) if " " in s.strip_edges() else s.strip_edges())
			_add_line(", ".join(names) + (" …(%d)" % c.size() if c.size() > 40 else ""))

func _process(delta: float) -> void:
	var r := GMDev.lines_since(_cursor)
	_cursor = r[1]
	for l in r[0]:
		_add_line(l)
	if is_open:
		_blink += delta
		queue_redraw()

func _add_line(s: String) -> void:
	if not _load_font():
		_lines.append(s)
		return
	var width := get_viewport_rect().size.x - 8
	var cur := ""
	var w := 0.0
	for ch in s:
		var cw := _char_w(ch)
		if w + cw > width and cur != "":
			_lines.append(cur)
			cur = "  "
			w = _char_w(" ") * 2
		cur += ch
		w += cw
	_lines.append(cur)
	if _lines.size() > 600:
		_lines = _lines.slice(_lines.size() - 600)

func _glyph(ch: String) -> Variant:
	var gl = _glyphs.get(ch.unicode_at(0))
	return gl if gl != null else _glyphs.get(63) # '?'

func _char_w(ch: String) -> float:
	var gl = _glyph(ch)
	return float(gl[4]) if gl != null else 6.0

func _text_at(s: String, x: float, y: float, col: Color) -> void:
	for ch in s:
		var gl = _glyph(ch)
		if gl == null:
			continue
		if gl[2] > 0 and gl[3] > 0:
			draw_texture_rect_region(_tex, Rect2(x + gl[5], y, gl[2], gl[3]), Rect2(gl[0], gl[1], gl[2], gl[3]), col)
		x += gl[4]

func _draw() -> void:
	if not is_open or not _load_font():
		return
	var size := get_viewport_rect().size
	var top := size.y - (SHOWN + 1) * LINE_H - 6
	draw_rect(Rect2(0, top, size.x, size.y - top), Color(0, 0, 0, 0.82))
	draw_line(Vector2(0, top), Vector2(size.x, top), Color(0.4, 0.7, 1.0, 0.9))
	var last := _lines.size() - _scroll
	var first := maxi(last - SHOWN, 0)
	var y := top + 2
	for i in range(first, last):
		var l := _lines[i]
		_text_at(l, 4, y, Color(1, 1, 0.55) if l.begins_with("> ") else Color(0.9, 0.9, 0.9))
		y += LINE_H
	var prompt := "> " + _text + ("_" if fmod(_blink, 1.0) < 0.5 else "")
	# Keep the end of a long line visible.
	while prompt.length() > 1 and _measure(prompt) > size.x - 8:
		prompt = prompt.substr(1)
	_text_at(prompt, 4, size.y - LINE_H - 2, Color(0.55, 1, 0.6))

func _measure(s: String) -> float:
	var w := 0.0
	for ch in s:
		w += _char_w(ch)
	return w
