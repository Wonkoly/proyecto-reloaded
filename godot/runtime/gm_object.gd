## Object definition: properties, parent chain and resolved event callables.
class_name GMObject
extends RefCounted

var index := 0
var name := ""
var sprite_index := -1.0
var mask_index := -1.0
var solid := false
var visible := true
var depth := 0.0
var persistent := false
var parent := -1
## This object and all its ancestors, nearest first.
var ancestors: Array[int] = []
## This object and all its descendants.
var children: Array[int] = []
## Generated event script (static functions e_<event>), loaded on first use.
var code: Script
## Event name -> owner object index (compiled event) or Callable (object_event_add),
## including events inherited from parents.
var events: Dictionary = {}
## Same, for events defined on this object only.
var own_events: Dictionary = {}
## Event name -> Callable cache for this object's compiled events.
var callables: Dictionary = {}
## Events added at runtime with object_event_add: event name -> code string.
var dynamic_events: Dictionary = {}

func has_draw() -> bool:
	return events.has("draw")
