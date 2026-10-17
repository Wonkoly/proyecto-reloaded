## One GameMaker 8 instance. Built-in variables are real properties (with GM8's side effects);
## user variables live in `v`. Generated code accesses both directly.
class_name GMInstance
extends RefCounted

## User-defined variables.
var v: Dictionary = {}

var id: float = 0.0
var object_index: float = 0.0
## Cached GMObject for object_index.
var obj: GMObject
## True once destroyed or deactivated; `with` loops and iterators skip such instances.
var gone := false
var destroyed := false
var deactivated := false
## Whether bbox_* must be recomputed before use.
var bbox_stale := true
var _bbox := [0, 0, 0, 0] # left, top, right, bottom

var alarm: Array = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0]

var x := 0.0:
	set(val):
		x = val
		bbox_stale = true
var y := 0.0:
	set(val):
		y = val
		bbox_stale = true
var xprevious := 0.0
var yprevious := 0.0
var xstart := 0.0
var ystart := 0.0

# Motion: GM8 keeps (speed, direction) and (hspeed, vspeed) in sync; setting one pair
# recomputes the other. Backing fields let the coupling write without re-triggering setters.
var _hspeed := 0.0
var _vspeed := 0.0
var _speed := 0.0
var _direction := 0.0
var hspeed: float:
	get:
		return _hspeed
	set(val):
		if _hspeed != val:
			_hspeed = val
			_update_speed_direction()
var vspeed: float:
	get:
		return _vspeed
	set(val):
		if _vspeed != val:
			_vspeed = val
			_update_speed_direction()
var speed: float:
	get:
		return _speed
	set(val):
		_speed = val
		_update_hvspeed()
var direction: float:
	get:
		return _direction
	set(val):
		_direction = fposmod(val, 360.0)
		_update_hvspeed()
var friction := 0.0
var gravity := 0.0
var gravity_direction := 270.0

var solid := false
var visible := true
var persistent := false
var depth := 0.0

var sprite_index := -1.0:
	set(val):
		if sprite_index != val:
			sprite_index = val
			bbox_stale = true
var image_index := 0.0
var image_speed := 1.0
var image_xscale := 1.0:
	set(val):
		image_xscale = val
		bbox_stale = true
var image_yscale := 1.0:
	set(val):
		image_yscale = val
		bbox_stale = true
var image_angle := 0.0:
	set(val):
		image_angle = val
		bbox_stale = true
var image_alpha := 1.0
var image_blend := 16777215.0
var image_single := -1.0:
	set(val):
		image_single = val
		if val >= 0.0:
			image_index = val
			image_speed = 0.0
var mask_index := -1.0:
	set(val):
		if mask_index != val:
			mask_index = val
			bbox_stale = true

var path_index := -1.0
var path_position := 0.0
var path_positionprevious := 0.0
var path_speed := 0.0
var path_scale := 1.0
var path_orientation := 0.0
var path_endaction := 0.0
var path_xstart := 0.0
var path_ystart := 0.0

var timeline_index := -1.0
var timeline_position := 0.0
var timeline_speed := 1.0
var timeline_running := false
var timeline_loop := false

# --- read-only computed built-ins

var image_number: float:
	get:
		var spr := GMAssets.sprite(sprite_index)
		return float(spr.frames) if spr else 0.0
var sprite_width: float:
	get:
		var spr := GMAssets.sprite(sprite_index)
		return spr.width * image_xscale if spr else 0.0
var sprite_height: float:
	get:
		var spr := GMAssets.sprite(sprite_index)
		return spr.height * image_yscale if spr else 0.0
var sprite_xoffset: float:
	get:
		var spr := GMAssets.sprite(sprite_index)
		return spr.origin_x * image_xscale if spr else 0.0
var sprite_yoffset: float:
	get:
		var spr := GMAssets.sprite(sprite_index)
		return spr.origin_y * image_yscale if spr else 0.0
var bbox_left: float:
	get:
		update_bbox()
		return float(_bbox[0])
var bbox_top: float:
	get:
		update_bbox()
		return float(_bbox[1])
var bbox_right: float:
	get:
		update_bbox()
		return float(_bbox[2])
var bbox_bottom: float:
	get:
		update_bbox()
		return float(_bbox[3])

func _update_hvspeed() -> void:
	# GM8 snaps components within 0.0001 of an integer.
	var rad := deg_to_rad(_direction)
	var h := cos(rad) * _speed
	var vv := -sin(rad) * _speed
	var rh := roundf(h)
	var rv := roundf(vv)
	_hspeed = rh if absf(rh - h) < 0.0001 else h
	_vspeed = rv if absf(rv - vv) < 0.0001 else vv

func _update_speed_direction() -> void:
	var d := fposmod(rad_to_deg(atan2(-_vspeed, _hspeed)), 360.0)
	_direction = roundf(d) if absf(d - roundf(d)) < 0.0001 else d
	_speed = sqrt(_hspeed * _hspeed + _vspeed * _vspeed)

## Sets hspeed and vspeed together (motion_add etc.), updating speed/direction once.
func set_hvspeed(h: float, vv: float) -> void:
	if _hspeed != h or _vspeed != vv:
		_hspeed = h
		_vspeed = vv
		_update_speed_direction()

## Sets speed and direction together, updating hspeed/vspeed once.
func set_speed_direction(sp: float, dir: float) -> void:
	_speed = sp
	_direction = fposmod(dir, 360.0)
	_update_hvspeed()

## Updates bbox_* from the current mask/sprite, like GM8's lazy bbox.
func update_bbox() -> void:
	if not bbox_stale:
		return
	bbox_stale = false
	var spr := GMAssets.sprite(mask_index if mask_index >= 0.0 else sprite_index)
	if spr == null or spr.frames == 0:
		_bbox = [-100000, -100000, -100000, -100000]
		return
	var tlx := (x - spr.origin_x * image_xscale) + spr.bbox_left * image_xscale
	var tly := (y - spr.origin_y * image_yscale) + spr.bbox_top * image_yscale
	var brx := tlx + (spr.bbox_right + 1 - spr.bbox_left) * image_xscale - 1.0
	var bry := tly + (spr.bbox_bottom + 1 - spr.bbox_top) * image_yscale - 1.0
	if image_xscale <= 0.0:
		var t := tlx
		tlx = brx
		brx = t
	if image_yscale <= 0.0:
		var t := tly
		tly = bry
		bry = t
	if image_angle == 0.0:
		_bbox = [GM.ri(tlx), GM.ri(tly), GM.ri(brx), GM.ri(bry)]
		return
	var a := -deg_to_rad(image_angle)
	var sn := sin(a)
	var cs := cos(a)
	var pts := [Vector2(tlx, tly), Vector2(brx, tly), Vector2(tlx, bry), Vector2(brx, bry)]
	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in pts:
		var px: float = p.x - x
		var py: float = p.y - y
		var rx := px * cs - py * sn + x
		var ry := px * sn + py * cs + y
		minx = minf(minx, rx)
		maxx = maxf(maxx, rx)
		miny = minf(miny, ry)
		maxy = maxf(maxy, ry)
	_bbox = [GM.ri(minx), GM.ri(miny), GM.ri(maxx), GM.ri(maxy)]
