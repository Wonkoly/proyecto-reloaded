## Math, strings and file I/O. Strings are treated as GM8 byte strings: every character is
## a code point 0-255 (files are read/written as Latin-1).
class_name GMLibData
extends GMLibInst

# ------------------------------------------------------------------ math

static func f_random(s: GMInstance, n: Variant) -> float:
	return rng.randf() * float(n)

static func f_choose(s: GMInstance, args: Array) -> Variant:
	if args.is_empty():
		return 0.0
	return args[rng.randi_range(0, args.size() - 1)]

static func f_round(s: GMInstance, x: Variant) -> float:
	return rf(x)

static func f_floor(s: GMInstance, x: Variant) -> float:
	return floorf(x)

static func f_ceil(s: GMInstance, x: Variant) -> float:
	return ceilf(x)

static func f_abs(s: GMInstance, x: Variant) -> float:
	return absf(x)

static func f_sign(s: GMInstance, x: Variant) -> float:
	if x >= EPS:
		return 1.0
	if x <= -EPS:
		return -1.0
	return 0.0

static func f_frac(s: GMInstance, x: Variant) -> float:
	var f: float = x
	return f - (floorf(f) if f >= 0.0 else ceilf(f))

static func f_sqrt(s: GMInstance, x: Variant) -> float:
	return sqrt(x)

static func f_power(s: GMInstance, x: Variant, n: Variant) -> float:
	return pow(x, n)

static func f_max(s: GMInstance, args: Array) -> Variant:
	if args.is_empty():
		return 0.0
	var best = args[0]
	for v in args:
		if v is float and best is float:
			if v > best:
				best = v
		elif v is String and not (best is String):
			if best < 0.0:
				best = v
		elif v is String and best is String and v > best:
			best = v
	return best

static func f_min(s: GMInstance, args: Array) -> Variant:
	if args.is_empty():
		return 0.0
	var best = args[0]
	for v in args:
		if v is float and best is float and v < best:
			best = v
	return best

static func f_point_direction(s: GMInstance, x1: Variant, y1: Variant, x2: Variant, y2: Variant) -> float:
	return fposmod(rad_to_deg(atan2(float(y1) - float(y2), float(x2) - float(x1))), 360.0)

static func f_lengthdir_x(s: GMInstance, len: Variant, dir: Variant) -> float:
	return cos(deg_to_rad(dir)) * float(len)

static func f_lengthdir_y(s: GMInstance, len: Variant, dir: Variant) -> float:
	return -sin(deg_to_rad(dir)) * float(len)

# ------------------------------------------------------------------ type / conversion

static func f_is_string(s: GMInstance, v: Variant) -> float:
	return 1.0 if v is String else 0.0

static func f_is_real(s: GMInstance, v: Variant) -> float:
	return 0.0 if v is String else 1.0

static func f_string(s: GMInstance, v: Variant) -> String:
	if v is String:
		return v
	if v is bool:
		return "1" if v else "0"
	var f := float(v)
	if f == floorf(f) and absf(f) < 1e18:
		return "%d" % int(f)
	return "%.2f" % f

static func f_real(s: GMInstance, v: Variant) -> float:
	if not (v is String):
		return float(v)
	var st: String = v.strip_edges()
	if st == "":
		return 0.0
	if st.is_valid_float() or st.is_valid_int():
		return st.to_float()
	_error("real(): can't convert \"%s\"" % st)
	return 0.0

static func f_chr(s: GMInstance, c: Variant) -> String:
	return String.chr(ri(c) & 0xFF)

static func f_ord(s: GMInstance, st: Variant) -> float:
	var t: String = st
	return float(t.unicode_at(0)) if t.length() > 0 else 0.0

# ------------------------------------------------------------------ strings

static func f_string_length(s: GMInstance, st: Variant) -> float:
	return float(_str(st).length())

static func _str(v: Variant) -> String:
	return v if v is String else f_string(null, v)

static func f_string_char_at(s: GMInstance, st: Variant, pos: Variant) -> String:
	var t := _str(st)
	var i := maxi(ri(pos) - 1, 0)
	return t.substr(i, 1) if i < t.length() else ""

static func f_string_copy(s: GMInstance, st: Variant, idx: Variant, count: Variant) -> String:
	var t := _str(st)
	var start := maxi(ri(idx) - 1, 0)
	var n := maxi(ri(count), 0)
	return t.substr(start, n) if start < t.length() else ""

static func f_string_pos(s: GMInstance, sub: Variant, st: Variant) -> float:
	var q := _str(sub)
	if q == "":
		return 0.0
	return float(_str(st).find(q) + 1)

static func f_string_delete(s: GMInstance, st: Variant, idx: Variant, count: Variant) -> String:
	var t := _str(st)
	var start := ri(idx) - 1
	var n := ri(count)
	if start < 0 or n <= 0:
		return t
	return t.substr(0, start) + t.substr(start + n)

static func f_string_replace(s: GMInstance, st: Variant, sub: Variant, rep: Variant) -> String:
	var t := _str(st)
	var q := _str(sub)
	var i := t.find(q) if q != "" else -1
	if i < 0:
		return t
	return t.substr(0, i) + _str(rep) + t.substr(i + q.length())

static func f_string_replace_all(s: GMInstance, st: Variant, sub: Variant, rep: Variant) -> String:
	var q := _str(sub)
	if q == "":
		return _str(st)
	return _str(st).replace(q, _str(rep))

static func f_string_count(s: GMInstance, sub: Variant, st: Variant) -> float:
	var q := _str(sub)
	if q == "":
		return 0.0
	return float(_str(st).count(q))

static func f_string_lower(s: GMInstance, st: Variant) -> String:
	# GM8 only maps ASCII letters.
	var t := _str(st)
	var out := ""
	for c in t:
		var u := c.unicode_at(0)
		out += String.chr(u + 32) if u >= 65 and u <= 90 else c
	return out

static func f_string_upper(s: GMInstance, st: Variant) -> String:
	var t := _str(st)
	var out := ""
	for c in t:
		var u := c.unicode_at(0)
		out += String.chr(u - 32) if u >= 97 and u <= 122 else c
	return out

static func f_string_letters(s: GMInstance, st: Variant) -> String:
	var out := ""
	for c in _str(st):
		var u := c.unicode_at(0)
		if (u >= 65 and u <= 90) or (u >= 97 and u <= 122):
			out += c
	return out

static func f_clipboard_set_text(s: GMInstance, st: Variant) -> float:
	post_command(["clipboard", _str(st)])
	return 0.0

# ------------------------------------------------------------------ paths

static var _path_cache: Dictionary = {}

## GM path (backslashes, relative to the game folder, Windows case-insensitive) -> real path.
## `.gif` resolves to the converted `.png` next to it.
static func real_path(p: Variant) -> String:
	var path := _str(p).replace("\\", "/")
	if path.length() > 1 and path[1] == ":":
		path = path.substr(2)
	if not path.begins_with("/") or not path.begins_with(working_directory):
		if path.begins_with("/") and not path.begins_with(working_directory):
			path = working_directory.path_join(path.substr(1))
		elif not path.begins_with("/"):
			path = working_directory.path_join(path)
	path = path.simplify_path()
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return path
	var ci := _case_insensitive(path)
	if ci != "":
		return ci
	if path.get_extension().to_lower() == "gif":
		var png := _case_insensitive(path.get_basename() + ".png")
		if png != "":
			return png
	return path

static func _case_insensitive(path: String) -> String:
	if _path_cache.has(path):
		return _path_cache[path]
	var parts := path.split("/", false)
	var cur := "/"
	for part in parts:
		var nxt := cur.path_join(part)
		if FileAccess.file_exists(nxt) or DirAccess.dir_exists_absolute(nxt):
			cur = nxt
			continue
		var found := ""
		var d := DirAccess.open(cur)
		if d == null:
			_path_cache[path] = ""
			return ""
		for n in d.get_files() + d.get_directories():
			if n.to_lower() == part.to_lower():
				found = n
				break
		if found == "":
			_path_cache[path] = ""
			return ""
		cur = cur.path_join(found)
	_path_cache[path] = cur
	return cur

# ------------------------------------------------------------------ files

static func f_file_exists(s: GMInstance, p: Variant) -> float:
	return 1.0 if FileAccess.file_exists(real_path(p)) else 0.0

static func f_directory_exists(s: GMInstance, p: Variant) -> float:
	return 1.0 if DirAccess.dir_exists_absolute(real_path(p)) else 0.0

static func f_file_delete(s: GMInstance, p: Variant) -> float:
	_path_cache.clear()
	return 1.0 if DirAccess.remove_absolute(real_path(p)) == OK else 0.0

static func f_file_rename(s: GMInstance, a: Variant, b: Variant) -> float:
	_path_cache.clear()
	return 1.0 if DirAccess.rename_absolute(real_path(a), real_path(b)) == OK else 0.0

static func f_file_copy(s: GMInstance, a: Variant, b: Variant) -> float:
	_path_cache.clear()
	return 1.0 if DirAccess.copy_absolute(real_path(a), real_path(b)) == OK else 0.0

## Open text files: handle -> {lines: PackedStringArray, pos, line_pos, write: FileAccess}
static var _text_files: Dictionary = {}
static var _next_handle := 1

static func _read_latin1(path: String) -> String:
	return latin1_decode(FileAccess.get_file_as_bytes(path))

## Latin-1 decode (one char per byte) via a UTF-32 buffer, much faster than concatenation.
static func latin1_decode(bytes: PackedByteArray) -> String:
	var n := bytes.size()
	var wide := PackedByteArray()
	wide.resize(n * 4)
	for i in n:
		wide[i * 4] = bytes[i]
	return wide.get_string_from_utf32()

static func _to_latin1(st: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(st.length())
	for i in st.length():
		out[i] = st.unicode_at(i) & 0xFF
	return out

static func f_file_text_open_read(s: GMInstance, p: Variant) -> float:
	var path := real_path(p)
	if not FileAccess.file_exists(path):
		return -1.0
	var h := _next_handle
	_next_handle += 1
	_text_files[h] = {"text": _read_latin1(path), "pos": 0, "write": null}
	return float(h)

static func _open_write(p: Variant, append: bool) -> float:
	var path := real_path(p)
	_path_cache.clear()
	var f: FileAccess
	if append and FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return -1.0
	var h := _next_handle
	_next_handle += 1
	_text_files[h] = {"text": "", "pos": 0, "write": f}
	return float(h)

static func f_file_text_open_write(s: GMInstance, p: Variant) -> float:
	return _open_write(p, false)

static func f_file_text_open_append(s: GMInstance, p: Variant) -> float:
	return _open_write(p, true)

static func f_file_text_close(s: GMInstance, h: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f and f.write:
		f.write.close()
	_text_files.erase(ri(h))
	return 0.0

static func f_file_text_write_string(s: GMInstance, h: Variant, st: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f and f.write:
		f.write.store_buffer(_to_latin1(_str(st)))
	return 0.0

static func f_file_text_write_real(s: GMInstance, h: Variant, v: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f and f.write:
		# GM writes reals with a leading space and 4 decimals.
		f.write.store_buffer(_to_latin1(" %.4f" % float(v)))
	return 0.0

static func f_file_text_writeln(s: GMInstance, h: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f and f.write:
		f.write.store_buffer(PackedByteArray([13, 10]))
	return 0.0

static func f_file_text_read_string(s: GMInstance, h: Variant) -> String:
	var f = _text_files.get(ri(h))
	if f == null:
		return ""
	var text: String = f.text
	var p: int = f.pos
	var end := p
	while end < text.length() and text.unicode_at(end) != 13 and text.unicode_at(end) != 10:
		end += 1
	f.pos = end
	return text.substr(p, end - p)

static func f_file_text_read_real(s: GMInstance, h: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f == null:
		return 0.0
	var text: String = f.text
	var p: int = f.pos
	while p < text.length() and text[p] in [" ", "\t"]:
		p += 1
	var st := p
	while p < text.length() and (text[p] in ["-", "+", ".", "e", "E"] or text[p].is_valid_int()):
		p += 1
	f.pos = p
	return text.substr(st, p - st).to_float()

static func f_file_text_readln(s: GMInstance, h: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f == null:
		return 0.0
	var text: String = f.text
	var p: int = f.pos
	while p < text.length() and text.unicode_at(p) != 10:
		p += 1
	f.pos = mini(p + 1, text.length())
	return 0.0

static func f_file_text_eof(s: GMInstance, h: Variant) -> float:
	var f = _text_files.get(ri(h))
	if f == null:
		return 1.0
	return 1.0 if f.pos >= f.text.length() else 0.0

## Binary files: handle -> FileAccess
static var _bin_files: Dictionary = {}

static func f_file_bin_open(s: GMInstance, p: Variant, mode: Variant) -> float:
	var path := real_path(p)
	_path_cache.clear()
	var m := ri(mode)
	var f: FileAccess
	match m:
		0:
			f = FileAccess.open(path, FileAccess.READ)
		1:
			f = FileAccess.open(path, FileAccess.WRITE)
		_:
			if FileAccess.file_exists(path):
				f = FileAccess.open(path, FileAccess.READ_WRITE)
			else:
				f = FileAccess.open(path, FileAccess.WRITE_READ)
	if f == null:
		return -1.0
	var h := _next_handle
	_next_handle += 1
	_bin_files[h] = {"f": f, "path": path}
	return float(h)

static func f_file_bin_close(s: GMInstance, h: Variant) -> float:
	var b = _bin_files.get(ri(h))
	if b:
		b.f.close()
	_bin_files.erase(ri(h))
	return 0.0

static func f_file_bin_read_byte(s: GMInstance, h: Variant) -> float:
	var b = _bin_files.get(ri(h))
	if b == null or b.f.eof_reached() or b.f.get_position() >= b.f.get_length():
		return 0.0
	return float(b.f.get_8())

static func f_file_bin_write_byte(s: GMInstance, h: Variant, v: Variant) -> float:
	var b = _bin_files.get(ri(h))
	if b:
		b.f.store_8(ri(v) & 0xFF)
	return 0.0

static func f_file_bin_seek(s: GMInstance, h: Variant, pos: Variant) -> float:
	var b = _bin_files.get(ri(h))
	if b:
		b.f.seek(ri(pos))
	return 0.0

static func f_file_bin_size(s: GMInstance, h: Variant) -> float:
	var b = _bin_files.get(ri(h))
	return float(b.f.get_length()) if b else 0.0

static func f_file_bin_rewrite(s: GMInstance, h: Variant) -> float:
	var b = _bin_files.get(ri(h))
	if b:
		b.f.close()
		b.f = FileAccess.open(b.path, FileAccess.WRITE_READ)
	return 0.0

static func f_get_open_filename(s: GMInstance, _filter: Variant, _fname: Variant) -> String:
	return ""
