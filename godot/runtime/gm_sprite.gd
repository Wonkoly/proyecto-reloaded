## Sprite data: frames, origin, bounding box and collision masks. Textures load lazily.
class_name GMSprite
extends RefCounted

var name := ""
var frames := 0
var width := 0
var height := 0
var origin_x := 0
var origin_y := 0
var bbox_left := 0
var bbox_top := 0
var bbox_right := 0
var bbox_bottom := 0
var per_frame_colliders := false
## Each collider: {left, top, right, bottom, w, h, full, mask: PackedByteArray (1 byte per px)}
var colliders: Array = []
var textures: Array = []
## Where frames come from: a folder of N.png (internal sprites) or a strip PNG (sprite_add).
var _dir := ""
var _strip := ""
var _images: Array = []

func texture(frame: int) -> Texture2D:
	if frames == 0:
		return null
	frame = posmod(frame, frames)
	if textures.is_empty():
		_load()
	return textures[frame]

func image(frame: int) -> Image:
	if textures.is_empty():
		_load()
	return _images[posmod(frame, frames)] if frames > 0 else null

func _load() -> void:
	textures.resize(frames)
	_images.resize(frames)
	if _strip != "":
		var strip := Image.load_from_file(_strip)
		for i in frames:
			var img := strip.get_region(Rect2i(i * width, 0, width, height))
			_images[i] = img
			textures[i] = ImageTexture.create_from_image(img)
	elif _dir != "":
		for i in frames:
			var img := Image.load_from_file(_dir.path_join("%d.png" % i))
			_images[i] = img
			textures[i] = ImageTexture.create_from_image(img)

## Builds from images already in memory (sprite_add, sprite_duplicate...).
func set_images(imgs: Array, ox: int, oy: int, precise := true) -> void:
	_images = imgs
	frames = imgs.size()
	textures = []
	for img: Image in imgs:
		textures.append(ImageTexture.create_from_image(img))
	if frames > 0:
		width = imgs[0].get_width()
		height = imgs[0].get_height()
	origin_x = ox
	origin_y = oy
	compute_colliders_from_alpha(precise)

## GM8's sprite_add collision: union mask of opaque pixels over all frames.
func compute_colliders_from_alpha(precise: bool) -> void:
	colliders = []
	per_frame_colliders = false
	if frames == 0:
		return
	var mask := PackedByteArray()
	mask.resize(width * height)
	var l := width
	var t := height
	var r := -1
	var b := -1
	for img: Image in _images:
		for yy in mini(height, img.get_height()):
			for xx in mini(width, img.get_width()):
				if img.get_pixel(xx, yy).a > 0.0:
					mask[yy * width + xx] = 1
					l = mini(l, xx)
					t = mini(t, yy)
					r = maxi(r, xx)
					b = maxi(b, yy)
	if r < 0:
		l = 0
		t = 0
		r = width - 1
		b = height - 1
	colliders.append({"left": l, "top": t, "right": r, "bottom": b, "w": width, "h": height,
		"full": not precise, "mask": mask})
	bbox_left = l
	bbox_top = t
	bbox_right = r
	bbox_bottom = b

func collider(image_index: float) -> Dictionary:
	if colliders.is_empty():
		return {}
	if per_frame_colliders:
		return colliders[posmod(int(floorf(image_index)), colliders.size())]
	return colliders[0]

## Precise test of a world point against this sprite drawn with the given transform.
static func point_in_collider(c: Dictionary, px: int, py: int, ix: int, iy: int, ox: int, oy: int,
		xs: float, ys: float, sn: float, cs: float) -> bool:
	var lx := float(px - ix)
	var ly := float(py - iy)
	var rx := lx * cs - ly * sn
	var ry := lx * sn + ly * cs
	var mx := int(floorf(ox + rx / xs))
	var my := int(floorf(oy + ry / ys))
	if mx < c.left or my < c.top or mx > c.right or my > c.bottom:
		return false
	if c.full:
		return true
	var idx: int = my * c.w + mx
	var m: PackedByteArray = c.mask
	return idx >= 0 and idx < m.size() and m[idx] != 0
