## Frame-time profiler (dev `perf` command, or GM_PERF=1): once a second prints the game's frame
## rate and the min/avg/max of each measured phase, to find what makes the frame rate uneven.
class_name GMPerf
extends RefCounted

static var enabled := false
static var scripts := false ## GM_PERF_SCRIPTS: also time every generated script
static var _mutex := Mutex.new()
static var _acc: Dictionary = {} # name -> [count, sum, max, min] (microseconds)
static var _last := {}           # name -> last timestamp, for intervals
static var _t0 := 0

## Records a duration in microseconds.
static func add(name: String, usec: int) -> void:
	if not enabled:
		return
	_mutex.lock()
	var a: Array = _acc.get(name, [0, 0, 0, 1 << 62])
	a[0] += 1
	a[1] += usec
	a[2] = maxi(a[2], usec)
	a[3] = mini(a[3], usec)
	_acc[name] = a
	_mutex.unlock()

static var _objs: Dictionary = {} # "event obj" -> total usec, for the top list

## Accumulates the time an object's instances spent in an event.
static func add_obj(ev: String, obj: int, usec: int, label := "") -> void:
	var k := "%s %s" % [ev, label if label != "" else GMAssets.index.objects[obj]]
	_mutex.lock()
	_objs[k] = _objs.get(k, 0) + usec
	_mutex.unlock()

## Records the time since the previous mark with the same name (frame-to-frame interval).
static func mark(name: String) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var prev: int = _last.get(name, 0)
	_last[name] = now
	if prev > 0:
		add(name, now - prev)

## Main thread, every frame: prints the report once a second.
static func report() -> String:
	if not enabled:
		return ""
	var now := Time.get_ticks_usec()
	if _t0 == 0:
		_t0 = now
	if now - _t0 < 1000000:
		return ""
	_t0 = now
	_mutex.lock()
	var acc := _acc
	_acc = {}
	var objs := _objs
	_objs = {}
	_mutex.unlock()
	var parts := []
	for name in acc.keys():
		var a: Array = acc[name]
		parts.append("%s %d× %.1f/%.1f/%.1f" % [name, a[0], a[3] / 1000.0, a[1] / 1000.0 / a[0], a[2] / 1000.0])
	parts.sort()
	var top := objs.keys()
	top.sort_custom(func(a, b): return objs[a] > objs[b])
	var tops := []
	for k in top.slice(0, 25 if scripts else 12):
		tops.append("%s %.1f" % [k, objs[k] / 1000.0])
	return "perf (ms min/avg/max): " + "  ".join(parts) + ("\n  más costosos (ms/s): " + ", ".join(tops) if not tops.is_empty() else "")
