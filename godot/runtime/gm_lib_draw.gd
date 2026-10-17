## Drawing: builds a frame of draw commands on the game thread and hands it to the main
## thread (gm_screen.gd). Follows OpenGMK's draw()/draw_view() ordering.
class_name GMLibDraw
extends GMCore

enum { OP_TEX, OP_POLY, OP_LINE, OP_STATE, OP_PRIM, OP_SYSTEXT }

static var draw_color := 0.0
static var draw_alpha := 1.0
static var draw_font := -1.0
static var draw_halign := 0
static var draw_valign := 0
static var fog_on := false
static var fog_color := Color.WHITE

## Commands of the frame being built, and the transform of the view being drawn.
static var _cmds: Array = []
static var _view := Transform2D.IDENTITY
static var _last_frame: Array = []
static var _frame_mutex := Mutex.new()
static var _frame_out: Variant = null
static var _commands_out: Array = []
static var screen_w := 640
static var screen_h := 480

static func gm_color(c: float, alpha := 1.0) -> Color:
	var k := ri(c)
	return Color8(k & 0xFF, (k >> 8) & 0xFF, (k >> 16) & 0xFF, int(clampf(alpha, 0.0, 1.0) * 255.0))

# ------------------------------------------------------------------ frame exchange

## Main thread: takes the newest finished frame, if any.
static func take_frame() -> Variant:
	_frame_mutex.lock()
	var f = _frame_out
	_frame_out = null
	_frame_mutex.unlock()
	return f

## Main thread: takes queued system commands (window, audio...).
static func take_commands() -> Array:
	_frame_mutex.lock()
	var c := _commands_out
	_commands_out = []
	_frame_mutex.unlock()
	return c

static func post_command(cmd: Array) -> void:
	_frame_mutex.lock()
	_commands_out.append(cmd)
	_frame_mutex.unlock()

static func _publish(cmds: Array) -> void:
	_last_frame = cmds
	_frame_mutex.lock()
	_frame_out = {"w": screen_w, "h": screen_h, "cmds": cmds}
	_frame_mutex.unlock()

## GM window size: room size, or the extent of visible view ports.
static func screen_set_size() -> void:
	var w := int(_room_width)
	var h := int(_room_height)
	if t(view_enabled):
		var mw := 0
		var mh := 0
		var any := false
		for k in 8:
			if t(view_visible[k]):
				any = true
				mw = maxi(mw, int(view_xport[k] + view_wport[k]))
				mh = maxi(mh, int(view_yport[k] + view_hport[k]))
		if any:
			w = mw
			h = mh
	if w != screen_w or h != screen_h:
		screen_w = w
		screen_h = h

# ------------------------------------------------------------------ the draw pass

static func draw_frame() -> void:
	_cmds = []
	_cmds.append([OP_STATE, fog_on, fog_color])
	if t(view_enabled):
		_cmds.append([OP_POLY, _rect_pts(0, 0, screen_w, screen_h), _cols4(gm_color(background_color))])
		_follow_views()
		for k in 8:
			if t(view_visible[k]):
				view_current = float(k)
				_draw_view(view_xview[k], view_yview[k], view_wview[k], view_hview[k],
					view_xport[k], view_yport[k], view_wport[k], view_hport[k], view_angle[k])
		view_current = 0.0
	else:
		_draw_view(0, 0, _room_width, _room_height, 0, 0, _room_width, _room_height, 0)
	_view = Transform2D.IDENTITY
	_publish(_cmds)

static func _follow_views() -> void:
	for k in 8:
		if not t(view_visible[k]) or view_object[k] < 0:
			continue
		var target: GMInstance = null
		var vo := ri(view_object[k])
		if vo < 100000:
			var lst := identity_list(vo)
			target = lst[0] if not lst.is_empty() else null
		else:
			target = by_id.get(vo)
		if target == null or target.gone:
			continue
		var x := ri(target.x)
		var y := ri(target.y)
		var sx := int(view_xview[k])
		var sy := int(view_yview[k])
		var sw := int(view_wview[k])
		var sh := int(view_hview[k])
		var hb := int(view_hborder[k])
		var vb := int(view_vborder[k])
		var hs := int(view_hspeed[k])
		var vs := int(view_vspeed[k])
		if hb < sw / 2:
			var bl := x - hb
			var br := x + hb
			if bl < sx:
				sx = bl if hs < 0 else sx - mini(sx - bl, hs)
			elif br > sx + sw:
				sx = br - sw if hs < 0 else sx + mini(br - (sx + sw), hs)
		else:
			sx = x - sw / 2
		sx = mini(maxi(sx, 0), int(_room_width) - sw) if int(_room_width) - sw >= 0 else 0
		if vb < sh / 2:
			var bt := y - vb
			var bb := y + vb
			if bt < sy:
				sy = bt if vs < 0 else sy - mini(sy - bt, vs)
			elif bb > sy + sh:
				sy = bb - sh if vs < 0 else sy + mini(bb - (sy + sh), vs)
		else:
			sy = y - sh / 2
		sy = mini(maxi(sy, 0), int(_room_height) - sh) if int(_room_height) - sh >= 0 else 0
		view_xview[k] = float(sx)
		view_yview[k] = float(sy)

static func _draw_view(sx: float, sy: float, sw: float, sh: float, px: float, py: float, pw: float, ph: float, angle: float) -> void:
	var scale := Vector2(pw / maxf(sw, 1.0), ph / maxf(sh, 1.0))
	_view = Transform2D(0.0, scale, 0.0, Vector2(px, py)) * Transform2D(0.0, Vector2(-sx, -sy))
	if angle != 0.0:
		var c := Vector2(sx + sw / 2.0, sy + sh / 2.0)
		_view = _view * Transform2D(0.0, c) * Transform2D(deg_to_rad(-angle), Vector2.ZERO) * Transform2D(0.0, -c)
	if t(background_showcolor):
		_cmds.append([OP_POLY, _xf_pts(_rect_pts(sx, sy, sw, sh)), _cols4(gm_color(background_color))])

	# Backgrounds (not foreground)
	for k in 8:
		if t(background_visible[k]) and not t(background_foreground[k]):
			_draw_room_background(k, sx, sy, sw, sh)

	# Instances and tiles merged by depth (higher depth first); particles systems interleave.
	var insts := _active_snapshot()
	insts.sort_custom(func(a, b): return a.depth > b.depth)
	var tls := tiles.duplicate()
	tls.sort_custom(func(a, b): return a.depth > b.depth)
	var systems: Array = GM.particle_systems_by_depth()
	var ii := 0
	var ti := 0
	var pi := 0
	while ii < insts.size() or ti < tls.size() or pi < systems.size():
		var di: float = insts[ii].depth if ii < insts.size() else -INF
		var dt: float = tls[ti].depth if ti < tls.size() else -INF
		var dp: float = systems[pi].depth if pi < systems.size() else -INF
		if pi < systems.size() and dp >= di and dp >= dt:
			GM.particle_system_draw(systems[pi])
			pi += 1
		elif ti < tls.size() and dt > di:
			_draw_tile(tls[ti])
			ti += 1
		else:
			var inst: GMInstance = insts[ii]
			ii += 1
			if inst.gone or not inst.visible:
				continue
			if inst.obj and inst.obj.events.has("draw"):
				run_event(inst, "draw", inst)
			else:
				_draw_instance_default(inst)

	for k in 8:
		if t(background_visible[k]) and t(background_foreground[k]):
			_draw_room_background(k, sx, sy, sw, sh)

	if cursor_sprite >= 0:
		_draw_sprite_raw(GMAssets.sprite(cursor_sprite), 0, mouse_x, mouse_y, 1, 1, 0, 16777215, 1)

static func _draw_instance_default(inst: GMInstance) -> void:
	var spr := GMAssets.sprite(inst.sprite_index)
	if spr == null:
		return
	_draw_sprite_raw(spr, int(floorf(inst.image_index)), inst.x, inst.y, inst.image_xscale, inst.image_yscale,
		inst.image_angle, inst.image_blend, inst.image_alpha)

static func _draw_tile(td: Dictionary) -> void:
	if not td.visible:
		return
	var bg := GMAssets.background(td.bg)
	if bg == null:
		return
	var tex := bg.texture()
	if tex == null:
		return
	var xf := _view * Transform2D(0.0, Vector2(td.xscale, td.yscale), 0.0, Vector2(td.x, td.y))
	_tex(tex, Rect2(td.tx, td.ty, td.w, td.h), xf, gm_color(td.blend, td.alpha))

static func _draw_room_background(k: int, sx: float, sy: float, sw: float, sh: float) -> void:
	var bg := GMAssets.background(background_index[k])
	if bg == null:
		return
	var tex := bg.texture()
	if tex == null:
		return
	var w: float = bg.width * background_xscale[k]
	var h: float = bg.height * background_yscale[k]
	if w <= 0 or h <= 0:
		return
	var col := gm_color(background_blend[k], background_alpha[k])
	var x0: float = background_x[k]
	var y0: float = background_y[k]
	var xs := [x0]
	var ys := [y0]
	if t(background_htiled[k]):
		xs = []
		var start: float = x0 - ceilf((x0 - sx) / w) * w
		var xx := start
		while xx < sx + sw:
			xs.append(xx)
			xx += w
	if t(background_vtiled[k]):
		ys = []
		var start: float = y0 - ceilf((y0 - sy) / h) * h
		var yy := start
		while yy < sy + sh:
			ys.append(yy)
			yy += h
	for yy in ys:
		for xx in xs:
			var xf := _view * Transform2D(0.0, Vector2(background_xscale[k], background_yscale[k]), 0.0, Vector2(xx, yy))
			_tex(tex, Rect2(0, 0, bg.width, bg.height), xf, col)

# ------------------------------------------------------------------ command helpers

static func _tex(tex: Texture2D, src: Rect2, xf: Transform2D, col: Color) -> void:
	_cmds.append([OP_TEX, tex, src, xf, col])

static func _rect_pts(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

static func _xf_pts(pts: PackedVector2Array) -> PackedVector2Array:
	return _view * pts

static func _cols4(c: Color) -> PackedColorArray:
	return PackedColorArray([c, c, c, c])

static func _set_fog(on: bool, col: Color) -> void:
	fog_on = on
	fog_color = col
	_cmds.append([OP_STATE, on, col])

static func _draw_sprite_raw(spr: GMSprite, frame: int, x: float, y: float, xs: float, ys: float, rot: float, blend: float, alpha: float) -> void:
	if spr == null or spr.frames == 0:
		return
	var tex := spr.texture(frame)
	if tex == null:
		return
	var xf := _view * Transform2D(deg_to_rad(-rot), Vector2(xs, ys), 0.0, Vector2(x, y)) \
		* Transform2D(0.0, Vector2(-spr.origin_x, -spr.origin_y))
	_tex(tex, Rect2(0, 0, spr.width, spr.height), xf, gm_color(blend, alpha))

## subimg -1 means the calling instance's current image_index.
static func _frame_of(s: GMInstance, subimg: Variant) -> int:
	if ri(subimg) < 0 or (subimg is float and subimg < 0.0):
		return int(floorf(s.image_index)) if s else 0
	return int(floorf(subimg))

# ------------------------------------------------------------------ GML draw functions

static func f_draw_sprite(s: GMInstance, spr: Variant, subimg: Variant, x: Variant, y: Variant) -> float:
	_draw_sprite_raw(GMAssets.sprite(spr), _frame_of(s, subimg), x, y, 1, 1, 0, 16777215, draw_alpha)
	return 0.0

static func f_draw_sprite_ext(s: GMInstance, spr: Variant, subimg: Variant, x: Variant, y: Variant, xs: Variant, ys: Variant, rot: Variant, col: Variant, alpha: Variant) -> float:
	_draw_sprite_raw(GMAssets.sprite(spr), _frame_of(s, subimg), x, y, xs, ys, rot, col, alpha)
	return 0.0

static func f_draw_sprite_part(s: GMInstance, spr: Variant, subimg: Variant, l: Variant, tp: Variant, w: Variant, h: Variant, x: Variant, y: Variant) -> float:
	return f_draw_sprite_part_ext(s, spr, subimg, l, tp, w, h, x, y, 1.0, 1.0, 16777215.0, draw_alpha)

static func f_draw_sprite_part_ext(s: GMInstance, spr: Variant, subimg: Variant, l: Variant, tp: Variant, w: Variant, h: Variant, x: Variant, y: Variant, xs: Variant, ys: Variant, col: Variant, alpha: Variant) -> float:
	var sp := GMAssets.sprite(spr)
	if sp == null or sp.frames == 0:
		return 0.0
	var tex := sp.texture(_frame_of(s, subimg))
	var src := Rect2(l, tp, w, h).intersection(Rect2(0, 0, sp.width, sp.height))
	if src.size.x <= 0 or src.size.y <= 0:
		return 0.0
	# Clipping the source shifts the drawn origin the same amount.
	var off := (src.position - Vector2(l, tp)) * Vector2(xs, ys)
	var xf := _view * Transform2D(0.0, Vector2(xs, ys), 0.0, Vector2(x, y) + off)
	_tex(tex, src, xf, gm_color(col, alpha))
	return 0.0

static func f_draw_background_ext(s: GMInstance, bgi: Variant, x: Variant, y: Variant, xs: Variant, ys: Variant, rot: Variant, col: Variant, alpha: Variant) -> float:
	var bg := GMAssets.background(bgi)
	if bg == null or bg.texture() == null:
		return 0.0
	var xf := _view * Transform2D(deg_to_rad(-float(rot)), Vector2(xs, ys), 0.0, Vector2(x, y))
	_tex(bg.texture(), Rect2(0, 0, bg.width, bg.height), xf, gm_color(col, alpha))
	return 0.0

static func f_draw_set_color(s: GMInstance, c: Variant) -> float:
	draw_color = c
	return 0.0

static func f_draw_set_alpha(s: GMInstance, a: Variant) -> float:
	draw_alpha = a
	return 0.0

static func f_draw_get_alpha(s: GMInstance) -> float:
	return draw_alpha

static func f_draw_set_font(s: GMInstance, f: Variant) -> float:
	draw_font = f
	return 0.0

static func f_draw_set_halign(s: GMInstance, a: Variant) -> float:
	draw_halign = ri(a)
	return 0.0

static func f_draw_set_valign(s: GMInstance, a: Variant) -> float:
	draw_valign = ri(a)
	return 0.0

static func f_d3d_set_fog(s: GMInstance, enable: Variant, col: Variant, _start: Variant, _end: Variant) -> float:
	_set_fog(t(enable), gm_color(col))
	return 0.0

static func f_make_color_rgb(s: GMInstance, r: Variant, gg: Variant, b: Variant) -> float:
	return float((clampi(ri(r), 0, 255)) | (clampi(ri(gg), 0, 255) << 8) | (clampi(ri(b), 0, 255) << 16))

static func f_make_color_hsv(s: GMInstance, h: Variant, sat: Variant, v: Variant) -> float:
	var c := Color.from_hsv(fposmod(float(h), 256.0) / 255.0, clampf(float(sat) / 255.0, 0, 1), clampf(float(v) / 255.0, 0, 1))
	return float(int(round(c.r * 255)) | (int(round(c.g * 255)) << 8) | (int(round(c.b * 255)) << 16))

static func f_merge_color(s: GMInstance, c1: Variant, c2: Variant, amount: Variant) -> float:
	var a := ri(c1)
	var b := ri(c2)
	var m := clampf(float(amount), 0.0, 1.0)
	var out := 0
	for sh: int in [0, 8, 16]:
		var ca := (a >> sh) & 0xFF
		var cb := (b >> sh) & 0xFF
		out |= (int(ca * (1.0 - m) + cb * m) & 0xFF) << sh
	return float(out)

static func f_color_get_red(s: GMInstance, c: Variant) -> float:
	return float(ri(c) & 0xFF)

static func f_color_get_green(s: GMInstance, c: Variant) -> float:
	return float((ri(c) >> 8) & 0xFF)

static func f_color_get_blue(s: GMInstance, c: Variant) -> float:
	return float((ri(c) >> 16) & 0xFF)

# --- primitives

static func f_draw_rectangle(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant, outline: Variant) -> float:
	var c := gm_color(draw_color, draw_alpha)
	return _rect(x1, y1, x2, y2, outline, c, c, c, c)

static func f_draw_rectangle_color(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant, c1: Variant, c2: Variant, c3: Variant, c4: Variant, outline: Variant) -> float:
	return _rect(x1, y1, x2, y2, outline, gm_color(c1, draw_alpha), gm_color(c2, draw_alpha),
		gm_color(c3, draw_alpha), gm_color(c4, draw_alpha))

static func _rect(x1: float, y1: float, x2: float, y2: float, outline: Variant, c1: Color, c2: Color, c3: Color, c4: Color) -> float:
	var l := minf(x1, x2)
	var r := maxf(x1, x2)
	var tp := minf(y1, y2)
	var b := maxf(y1, y2)
	if t(outline):
		_line(l, tp, r, tp, c1, c2, 1)
		_line(r, tp, r, b, c2, c3, 1)
		_line(r, b, l, b, c3, c4, 1)
		_line(l, b, l, tp, c4, c1, 1)
	else:
		# GM rectangles include the far edge pixel.
		_cmds.append([OP_POLY, _xf_pts(_rect_pts(l, tp, r - l + 1, b - tp + 1)), PackedColorArray([c1, c2, c3, c4])])
	return 0.0

static func _line(x1: float, y1: float, x2: float, y2: float, c1: Color, c2: Color, w: float) -> void:
	var a := _view * Vector2(x1 + 0.5, y1 + 0.5)
	var b := _view * Vector2(x2 + 0.5, y2 + 0.5)
	_cmds.append([OP_LINE, a, b, c1, c2, w * _view.get_scale().x])

static func f_draw_line(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant) -> float:
	var c := gm_color(draw_color, draw_alpha)
	_line(x1, y1, x2, y2, c, c, 1)
	return 0.0

static func f_draw_line_color(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant, c1: Variant, c2: Variant) -> float:
	_line(x1, y1, x2, y2, gm_color(c1, draw_alpha), gm_color(c2, draw_alpha), 1)
	return 0.0

static func f_draw_ellipse_color(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant, c1: Variant, c2: Variant, outline: Variant) -> float:
	var cx := (float(x1) + float(x2)) / 2.0
	var cy := (float(y1) + float(y2)) / 2.0
	var rx := absf(float(x2) - float(x1)) / 2.0
	var ry := absf(float(y2) - float(y1)) / 2.0
	var ci := gm_color(c1, draw_alpha)
	var co := gm_color(c2, draw_alpha)
	var n := 24
	if t(outline):
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			_line(cx + cos(a0) * rx, cy + sin(a0) * ry, cx + cos(a1) * rx, cy + sin(a1) * ry, co, co, 1)
	else:
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var pts := PackedVector2Array([Vector2(cx, cy), Vector2(cx + cos(a0) * rx, cy + sin(a0) * ry),
				Vector2(cx + cos(a1) * rx, cy + sin(a1) * ry)])
			_cmds.append([OP_POLY, _xf_pts(pts), PackedColorArray([ci, co, co])])
	return 0.0

# --- text (port of OpenGMK's LineIterator / draw_string)

static func _font() -> GMAssets.FontAsset:
	var f := GMAssets.font(draw_font)
	return f if f and not f.glyphs.is_empty() else null

## Splits GM text into [line_codes: PackedInt32Array, width] pairs.
static func _split_lines(text: String, f: GMAssets.FontAsset) -> Array:
	var lines := []
	var cur := PackedInt32Array()
	var w := 0
	var n := text.length()
	var i := 0
	var first_adv := 0
	if f:
		var fg = f.glyphs.get(32, f.glyphs.values()[0])
		first_adv = fg[4]
	while i < n:
		var c := text.unicode_at(i)
		i += 1
		if c == 35 or c == 13 or c == 10: # '#', CR, LF
			if c == 13 and i < n and text.unicode_at(i) == 10:
				i += 1
			lines.append([cur, w])
			cur = PackedInt32Array()
			w = 0
			continue
		if c == 92 and i < n and text.unicode_at(i) == 35: # '\#'
			c = 35
			i += 1
		if f:
			var gl = f.glyphs.get(c)
			if gl == null:
				c = 32
				gl = f.glyphs.get(32)
				w += gl[4] if gl else first_adv
			else:
				w += gl[4]
		else:
			w += _sys_char_width(c)
		cur.append(c)
	if not cur.is_empty() or lines.is_empty():
		lines.append([cur, w])
	return lines

static func _sys_char_width(_c: int) -> int:
	return 7

static func _line_height(f: GMAssets.FontAsset) -> int:
	return f.line_height if f else 16

static func f_string_width(s: GMInstance, text: Variant) -> float:
	var mw := 0
	for l in _split_lines(str(text) if not (text is String) else text, _font()):
		mw = maxi(mw, l[1])
	return float(mw)

static func f_draw_text(s: GMInstance, x: Variant, y: Variant, text: Variant) -> float:
	var c := gm_color(draw_color, draw_alpha)
	_draw_text(float(x), float(y), _gm_str(text), [c, c, c, c], false)
	return 0.0

static func f_draw_text_color(s: GMInstance, x: Variant, y: Variant, text: Variant, c1: Variant, c2: Variant, c3: Variant, c4: Variant, alpha: Variant) -> float:
	var a := float(alpha)
	_draw_text(float(x), float(y), _gm_str(text),
		[gm_color(c1, a), gm_color(c2, a), gm_color(c3, a), gm_color(c4, a)], true)
	return 0.0

## GM converts reals passed to draw_text with string().
static func _gm_str(v: Variant) -> String:
	if v is String:
		return v
	return GM.f_string(null, v)

static func _draw_text(x: float, y: float, text: String, cols: Array, gradient: bool) -> void:
	var f := _font()
	var lines := _split_lines(text, f)
	var lh := _line_height(f)
	var cy := 0
	if draw_valign == 1:
		cy = -(lines.size() * lh) / 2
	elif draw_valign == 2:
		cy = -lines.size() * lh
	if f == null:
		for l in lines:
			var lx := 0
			if draw_halign == 1:
				lx = -l[1] / 2
			elif draw_halign == 2:
				lx = -l[1]
			var s := ""
			for code in l[0]:
				s += String.chr(code)
			_cmds.append([OP_SYSTEXT, s, _view * Vector2(x + lx, y + cy + 12), cols[0], 12])
			cy += lh
		return
	var tex := f.texture()
	if tex == null:
		return
	for l in lines:
		var width: int = l[1]
		var left := 0
		if draw_halign == 1:
			left = -width / 2
		elif draw_halign == 2:
			left = -width
		var cx := left
		for code in l[0]:
			var gl = f.glyphs.get(code)
			if gl == null:
				continue
			var gx: float = x + gl[5] + cx
			var gy: float = y + cy
			if gl[2] > 0 and gl[3] > 0:
				var src := Rect2(gl[0], gl[1], gl[2], gl[3])
				if gradient and width > 0:
					var r0 := float(cx - left) / width
					var r1 := float(cx - left + gl[4]) / width
					var ca: Color = cols[0].lerp(cols[1], r0)
					var cb: Color = cols[0].lerp(cols[1], r1)
					var cc: Color = cols[3].lerp(cols[2], r1)
					var cd: Color = cols[3].lerp(cols[2], r0)
					var pts := _xf_pts(_rect_pts(gx, gy, gl[2], gl[3]))
					var tsz := tex.get_size()
					var uvs := PackedVector2Array([src.position / tsz, Vector2(src.end.x, src.position.y) / tsz,
						src.end / tsz, Vector2(src.position.x, src.end.y) / tsz])
					_cmds.append([OP_PRIM, tex, pts, uvs, PackedColorArray([ca, cb, cc, cd])])
				else:
					_tex(tex, src, _view * Transform2D(0.0, Vector2(gx, gy)), cols[0])
			cx += gl[4]
		cy += lh

# --- screen

static func f_screen_redraw(s: GMInstance) -> float:
	draw_frame()
	return 0.0

static func f_screen_refresh(s: GMInstance) -> float:
	_publish(_last_frame)
	return 0.0

static func f_screen_save(s: GMInstance, fname: Variant) -> float:
	post_command(["screenshot", GM.real_path(fname)])
	return 0.0
