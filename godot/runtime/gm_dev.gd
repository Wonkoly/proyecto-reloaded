## Developer mode (`tools/dev.sh`, GM_DEV=1 or `-- --dev`): the in-game console (gm_console.gd)
## and the optional dev window (gm_dev_ui.gd) send text commands here. Commands that only touch
## flags run at once on the main thread; the rest run on the game thread between frames, when no
## GML is on the stack. The full list is in COMANDOS.md.
class_name GMDev
extends RefCounted

const G = preload("res://runtime/gm.gd")

## [name, aliases, usage, description]. Drives `ayuda` and Tab completion; keep COMANDOS.md in sync.
const COMMANDS := [
	["ayuda", ["help", "?"], "ayuda [comando]", "lista los comandos o explica uno"],
	["tp", ["ir", "teleport"], "tp <mapa> [x y]  |  tp <x> <y>", "va a otro mapa (sin x y: al centro) o mueve al protagonista dentro del mapa"],
	["mapas", ["rooms"], "mapas [filtro]", "lista los mapas (nombre e índice)"],
	["info", [], "info", "mapa, posición del protagonista, instancias y fps"],
	["guardar", ["save"], "guardar", "guarda ya, sin las restricciones del juego"],
	["cargar", ["load"], "cargar [slot]", "reinicia y carga la partida del slot, sin intro"],
	["turbo", [], "turbo [n]", "velocidad del juego (1 = normal, máx. 16); Tab mantenido = x4"],
	["atravesar", ["noclip"], "atravesar", "activa/desactiva atravesar paredes"],
	["sinencuentros", ["repel"], "sinencuentros", "activa/desactiva los Pokémon salvajes"],
	["dinero", ["money"], "dinero [cantidad]", "muestra o fija el dinero"],
	["objeto", ["item"], "objeto <id> [cantidad]", "añade objetos a la mochila"],
	["objetos", ["items"], "objetos [filtro]", "busca objetos por nombre y muestra su id"],
	["curar", ["heal"], "curar", "cura al equipo como en el Centro Pokémon"],
	["pokemon", ["pkmn"], "pokemon <id> [nivel]", "añade un Pokémon al equipo (como cuando el juego te da el inicial)"],
	["equipo", ["team"], "equipo", "muestra el equipo: nombre, nivel y PS"],
	["pokemons", [], "pokemons [filtro]", "busca Pokémon por nombre y muestra su id"],
	["batalla", ["battle"], "batalla <id> [nivel]", "empieza un combate contra un Pokémon salvaje"],
	["entrenador", ["trainer"], "entrenador <n>", "pone al entrenador n del juego junto a ti y empieza el combate (1 = rival, 2.. = otros)"],
	["perf", ["fps"], "perf", "activa/desactiva el informe de rendimiento (cada segundo, en la consola)"],
	["efecto", ["effect"], "efecto <0-11> [tamaño 0-2] [color]", "crea un efecto de partículas sobre el protagonista (0 explosión, 1 anillo, 4 humo, 6 estrella, 10 lluvia, 11 nieve…)"],
	["global", [], "global <nombre> [valor]", "lee/escribe una variable global del juego"],
	["var", [], "var <objeto> <campo> [valor]", "lee/escribe una variable de la primera instancia de un objeto"],
	["script", [], "script <Nombre> [args...]", "llama a un script del juego"],
	["tecla", ["key"], "tecla <vk>", "pulsa una tecla (código VK de Windows: 90 = Z, 13 = Enter)"],
	["ventana", ["window"], "ventana", "abre/cierra la ventana de developer"],
	["limpiar", ["cls", "clear"], "limpiar", "borra la consola"],
]

static var enabled := false
static var turbo := 1.0
static var noclip := false
static var no_encounters := false
## Set by the host: toggles the dev window (main thread).
static var toggle_window := Callable()

static var _mutex := Mutex.new()
static var _queue: Array = []
static var _log: PackedStringArray = []
static var _log_start := 0 # index of _log[0] in the whole history
static var _info := {}
static var _release: Array = [] # [vk, release time in ms] for `tecla` (main thread only)
static var _fps_t := 0
static var _fps_n := 0
static var _fps := 0.0

# ------------------------------------------------------------------ main thread

static func command_name(word: String) -> String:
	word = word.to_lower()
	for c in COMMANDS:
		if c[0] == word or word in c[1]:
			return c[0]
	return ""

static func push(cmd: String) -> void:
	var a := cmd.strip_edges().split(" ", false)
	if a.is_empty():
		return
	_print("> " + cmd.strip_edges())
	var name := command_name(a[0])
	# Flag-only commands apply at once: the game thread may be stuck in a blocking dialog loop.
	match name:
		"ayuda":
			_help(a[1] if a.size() > 1 else "")
		"turbo":
			turbo = clampf(float(a[1]) if a.size() > 1 else 1.0, 0.25, 16.0)
			_print("turbo x%s" % _fmt(turbo))
		"perf":
			GMPerf.enabled = not GMPerf.enabled
			_print("informe de rendimiento: " + ("sí" if GMPerf.enabled else "no"))
		"atravesar":
			noclip = not noclip
			_print("atravesar paredes: " + ("sí" if noclip else "no"))
		"sinencuentros":
			no_encounters = not no_encounters
			_print("Pokémon salvajes: " + ("no" if no_encounters else "sí"))
		"info":
			var d := info()
			if d.is_empty():
				_print("el juego aún no ha dibujado nada")
			else:
				var pos := "x=%d y=%d" % [d.x, d.y] if not is_nan(d.x) else "sin protagonista"
				_print("%s (%d)  %s  instancias=%d  %.0f fps  turbo x%s" % [
					d.room_name, d.room, pos, d.instances, d.fps, _fmt(turbo)])
		"mapas":
			var f := _norm(a[1]) if a.size() > 1 else ""
			var hits := []
			for i in GMAssets.room_names.size():
				var n = GMAssets.room_names[i]
				if n != null and (f == "" or _norm(str(n)).contains(f)):
					hits.append("%s(%d)" % [n, i])
			_print(", ".join(hits) if not hits.is_empty() else "ningún mapa contiene '%s'" % f)
		"tecla":
			if a.size() < 2 or not a[1].is_valid_int():
				_print("uso: tecla <vk>")
				return
			G.push_input(["down", int(a[1])])
			# Held for 100 ms so keyboard_check sees it; release_keys (main thread) lets go.
			_release.append([int(a[1]), Time.get_ticks_msec() + 100])
		"ventana":
			if toggle_window.is_valid():
				toggle_window.call()
		"limpiar":
			_mutex.lock()
			_log_start += _log.size()
			_log = []
			_mutex.unlock()
		"":
			_print("comando desconocido '%s' (escribe: ayuda)" % a[0])
		_:
			_mutex.lock()
			_queue.append(a)
			_mutex.unlock()

## Main thread, every frame: releases the keys pressed with `tecla` once their time is up.
static func release_keys() -> void:
	var now := Time.get_ticks_msec()
	for r in _release:
		if now >= r[1]:
			G.push_input(["up", r[0]])
	_release = _release.filter(func(r): return now < r[1])

## Console lines from `cursor` on (a running index), and the next cursor.
static func lines_since(cursor: int) -> Array:
	_mutex.lock()
	var from := maxi(cursor - _log_start, 0)
	var out := _log.slice(from)
	var next := _log_start + _log.size()
	_mutex.unlock()
	return [out, next]

static func info() -> Dictionary:
	_mutex.lock()
	var d := _info.duplicate()
	_mutex.unlock()
	return d

## Tab completion for the console: candidate full lines for `line`.
static func complete(line: String) -> PackedStringArray:
	var parts := line.split(" ")
	var out: PackedStringArray = []
	if parts.size() == 1:
		for c in COMMANDS:
			if c[0].begins_with(parts[0].to_lower()):
				out.append(c[0] + " ")
		return out
	if parts.size() == 2 and command_name(parts[0]) in ["tp", "mapas"]:
		var p := parts[1].to_lower()
		for n in GMAssets.room_names:
			if n != null and str(n).to_lower().begins_with(p):
				out.append("%s %s" % [parts[0], n])
	return out

static func _help(cmd: String) -> void:
	if cmd != "":
		var name := command_name(cmd)
		for c in COMMANDS:
			if c[0] == name:
				_print("%s — %s" % [c[2], c[3]])
				if not c[1].is_empty():
					_print("  también: " + ", ".join(c[1]))
				return
		_print("no existe el comando '%s'" % cmd)
		return
	_print("Comandos (ayuda <comando> para más; Tab completa; lista completa en COMANDOS.md):")
	for c in COMMANDS:
		_print("  " + c[2])

# ------------------------------------------------------------------ game thread

static func _print(s: String) -> void:
	print("[DEV] ", s)
	_mutex.lock()
	for line in s.split("\n"):
		_log.append(line)
	if _log.size() > 400:
		_log_start += _log.size() - 400
		_log = _log.slice(_log.size() - 400)
	_mutex.unlock()

## Adds a line to the console from the main thread.
static func log_line(s: String) -> void:
	_print(s)

## Called by the game loop after each frame.
static func step() -> void:
	_mutex.lock()
	var q := _queue
	_queue = []
	_mutex.unlock()
	for a in q:
		_run(a)
	if no_encounters:
		if not G.object_list(18).is_empty(): # variables: the repel step counter lives there
			var s := _self()
			G.fset(s, s, 18.0, "repelente", 9999.0)

## Called on every drawn frame (also inside the game's blocking loops).
static func publish_info() -> void:
	_fps_n += 1
	var now := Time.get_ticks_msec()
	if now - _fps_t >= 1000:
		_fps = _fps_n * 1000.0 / (now - _fps_t)
		_fps_n = 0
		_fps_t = now
	var p := _prota()
	var d := {
		"room": int(G.room), "room_name": _room_name(int(G.room)), "fps": _fps,
		"instances": G.instances.size(), "x": p.x if p else NAN, "y": p.y if p else NAN,
	}
	_mutex.lock()
	_info = d
	_mutex.unlock()

static func _prota() -> GMInstance:
	var l := G.object_list(14) # obj_Prota
	return l[0] if not l.is_empty() else null

## Some instance to run scripts as (the explorer controller when on the map).
static func _self() -> GMInstance:
	for oi in [16, 14, 18]: # EXPLORER, obj_Prota, variables
		var l := G.object_list(oi)
		if not l.is_empty():
			return l[0]
	var a := G._active_snapshot()
	return a[0] if not a.is_empty() else GMInstance.new()

static func _room_name(i: int) -> String:
	var names: Array = GMAssets.room_names
	return str(names[i]) if i >= 0 and i < names.size() and names[i] != null else "?"

static func _find_room(arg: String) -> int:
	var names: Array = GMAssets.room_names
	if arg.is_valid_int():
		var k := int(arg)
		return k if k >= 0 and k < names.size() and names[k] != null else -1
	for i in names.size():
		if names[i] != null and str(names[i]).to_lower() == arg.to_lower():
			return i
	return -1

## Lowercase without accents, for searches ("pocion" finds "Poción").
static func _norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"]]:
		s = s.replace(pair[0], pair[1])
	return s

## Values as the game would print them (whole reals without decimals).
static func _fmt(v: Variant) -> String:
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return str(int(v))
	return str(v)

static func _value(s: String) -> Variant:
	if s.is_valid_float():
		return float(s)
	if s.length() >= 2 and s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	return s

static func _call(script: String, args: Array = []) -> Variant:
	var id := GMAssets.script_id(script)
	if id < 0:
		_print("no existe el script '%s'" % script)
		return null
	var s := _self()
	var c := GMAssets.script_callable(id)
	var full := [s, s] + args
	while full.size() < c.get_argument_count():
		full.append(0.0)
	return c.callv(full.slice(0, c.get_argument_count()))

static func _need_prota() -> GMInstance:
	var p := _prota()
	if p == null:
		_print("solo funciona con el protagonista en un mapa")
	return p

static func _run(a: PackedStringArray) -> void:
	match command_name(a[0]):
		"guardar":
			_save()
		"cargar":
			var slot := int(a[1]) if a.size() > 1 and a[1].is_valid_int() else int(G.g.get("Slot", 1.0))
			if not FileAccess.file_exists(G.real_path("data\\partidas\\reloaded%d.savc" % slot)):
				_print("el slot %d no tiene partida guardada" % slot)
				return
			request_load(G.working_directory, slot)
			G.f_game_restart(_self())
		"tp":
			_tp(a)
		"dinero":
			if a.size() > 1:
				_call("SetDinero", [float(a[1])])
			_print("dinero: %s" % _fmt(G.g.get("dinero", 0.0)))
		"objeto":
			if a.size() < 2 or not a[1].is_valid_int():
				_print("uso: objeto <id> [cantidad]  (busca el id con: objetos <nombre>)")
				return
			var n := int(a[2]) if a.size() > 2 and a[2].is_valid_int() else 1
			var ok = _call("PillaObject", [float(a[1]), float(n)])
			_print("%s x%d %s" % [_call("NameObject", [float(a[1])]), n, "añadido" if G.t(ok) else "no se pudo añadir"])
		"objetos":
			var f := _norm(" ".join(a.slice(1)))
			var hits := []
			for i in range(1, 2100):
				var n = _call("NameObject", [float(i)])
				if n is String and n != "" and n != "0" and (f == "" or _norm(n).contains(f)):
					hits.append("%d %s" % [i, n])
			_print(", ".join(hits) if not hits.is_empty() else "ningún objeto contiene '%s'" % f)
		"curar":
			_call("CentroPokemon", [1.0])
			_print("equipo curado")
		"pokemon":
			_give_pokemon(a)
		"equipo":
			var lines := []
			for i in 6:
				var pk = G.aget(G.g, "pkmn1", i, 0)
				if _fmt(pk) == "0":
					continue
				lines.append("%d. %s nv %s  PS %s/%s" % [i + 1, _call("NamePokemon", [pk]), _fmt(G.aget(G.g, "nivel1", i, 0)),
					_fmt(G.aget(G.g, "PS_1", i, 0)), _fmt(G.aget(G.g, "MAX_PS_1", i, 0))])
			_print("\n".join(lines) if not lines.is_empty() else "el equipo está vacío")
		"pokemons":
			var f := _norm(" ".join(a.slice(1)))
			var hits := []
			for i in range(1, 2500):
				var n = _call("NamePokemon", [float(i)])
				if n is String and n != "" and n != "-" and (f == "" or _norm(n).contains(f)):
					hits.append("%d %s" % [i, n])
			_print(", ".join(hits) if not hits.is_empty() else "ningún Pokémon contiene '%s'" % f)
		"entrenador":
			var p := _need_prota()
			if p == null:
				return
			if a.size() < 2 or not a[1].is_valid_int():
				_print("uso: entrenador <n>")
				return
			if _fmt(G.aget(G.g, "pkmn1", 0, 0)) == "0":
				_print("no tienes Pokémon: usa primero  pokemon <id> [nivel]")
				return
			# Same setup as the map scripts (e.g. CreateBossPokemon), then make it talk.
			var s := _self()
			var zid: float = G.f_instance_create(s, p.x + 32.0, p.y, 94.0) # obj_Entrenador
			var z: GMInstance = G.by_id.get(int(zid))
			for kv in [["INDEX", float(a[1])], ["name", "Entrenador"], ["mirafijo", 4.0], ["mira", 4.0],
					["sprINDEX", 174.0], ["distancia", 80.0], ["str", "¡Combate de prueba!"]]:
				G.fset(s, s, zid, kv[0], kv[1])
			s.v["z"] = zid # TrainerPokemon fills the team of the caller's `z`
			_call("TrainerPokemon", [float(a[1])])
			z.alarm[0] = 3.0 # EntrenadorHabla, once EntrenadorInitialize has run
			_print("entrenador %s: %s" % [a[1], ", ".join(range(1, 7).map(func(i): return _fmt(G.fget(s, s, zid, "PK%d" % i))))])
		"batalla":
			if _need_prota() == null:
				return
			if a.size() < 2 or not a[1].is_valid_int():
				_print("uso: batalla <id> [nivel]  (busca el id con: pokemons <nombre>)")
				return
			if _fmt(G.aget(G.g, "pkmn1", 0, 0)) == "0":
				_print("no tienes Pokémon: usa primero  pokemon <id> [nivel]")
				return
			var nv := float(a[2]) if a.size() > 2 and a[2].is_valid_float() else 5.0
			# Same steps as a grass encounter (HierbasSalvajes).
			_call("ClearPkmn2")
			G.g["horda"] = 0.0
			_call("IniciaSalvaje", [float(a[1]), nv, 0.0])
			G.g["lugar"] = G.room
			G.f_instance_create(_self(), 0.0, 0.0, 386.0) # obj_BallGigante: the battle transition
			_print("combate contra %s nivel %s" % [_call("NamePokemon", [float(a[1])]), _fmt(nv)])
		"efecto":
			var p := _need_prota()
			if p == null or a.size() < 2 or not a[1].is_valid_int():
				if p:
					_print("uso: efecto <0-11> [tamaño 0-2] [color]")
				return
			var size := float(a[2]) if a.size() > 2 else 1.0
			var col := float(a[3]) if a.size() > 3 else 16777215.0
			G.f_effect_create_above(p, float(a[1]), p.x, p.y - 8.0, size, col)
		"global":
			if a.size() < 2:
				_print("uso: global <nombre> [valor]")
				return
			if a.size() > 2:
				G.g[a[1]] = _value(" ".join(a.slice(2)))
			_print("global.%s = %s" % [a[1], _fmt(G.g.get(a[1], "<no definida>"))])
		"var":
			if a.size() < 3:
				_print("uso: var <objeto> <campo> [valor]")
				return
			var oi := int(a[1]) if a[1].is_valid_int() else GMAssets.names_lookup("objects", a[1])
			if oi < 0 or G.identity_list(oi).is_empty():
				_print("no hay instancias de '%s'" % a[1])
				return
			var s := _self()
			if a.size() > 3:
				G.fset(s, s, float(oi), a[2], _value(" ".join(a.slice(3))))
			_print("%s.%s = %s" % [a[1], a[2], _fmt(G.fget(s, s, float(oi), a[2]))])
		"script":
			if a.size() < 2:
				_print("uso: script <Nombre> [args...]")
				return
			var args := []
			for v in a.slice(2):
				args.append(_value(v))
			_print("= %s" % _fmt(_call(a[1], args)))

static func _tp(a: PackedStringArray) -> void:
	if a.size() == 3 and a[1].is_valid_float() and a[2].is_valid_float():
		var p := _need_prota()
		if p:
			p.x = float(a[1])
			p.y = float(a[2])
		return
	if a.size() < 2:
		_print("uso: tp <mapa> [x y]  |  tp <x> <y>")
		return
	var r := _find_room(a[1])
	if r < 0:
		_print("no existe el mapa '%s' (prueba: mapas %s)" % [a[1], a[1]])
		return
	var rd = GMAssets.room(r)
	var x := float(a[2]) if a.size() > 3 else float(rd.width) / 2.0
	var y := float(a[3]) if a.size() > 3 else float(rd.height) / 2.0
	# AdjustmentsRoom creates obj_Prota at global.xx/yy on entering a map.
	G.g["xx"] = x
	G.g["yy"] = y
	G.f_room_goto(_self(), r)
	_print("-> %s (%d) en %d,%d" % [_room_name(r), r, x, y])

## Adds a Pokémon to the first free team slot, filling it the way StarterSelectorElige fills the starter.
static func _give_pokemon(a: PackedStringArray) -> void:
	if a.size() < 2 or not a[1].is_valid_int():
		_print("uso: pokemon <id> [nivel]  (busca el id con: pokemons <nombre>)")
		return
	var pk := float(a[1])
	var nv := clampf(float(a[2]) if a.size() > 2 and a[2].is_valid_float() else 5.0, 1.0, 100.0)
	var name = _call("NamePokemon", [pk])
	if not (name is String) or name == "" or name == "-":
		_print("no existe el Pokémon %s" % a[1])
		return
	var slot := -1
	for i in 6:
		if _fmt(G.aget(G.g, "pkmn1", i, 0)) == "0":
			slot = i
			break
	if slot < 0:
		_print("el equipo está lleno")
		return
	var srid = _call("GetSoftReset", [pk])
	if G.ri(srid) < 0:
		srid = _call("GenerateSoftReset", [pk])
	var sr: GMInstance = G.by_id.get(G.ri(srid))
	if sr == null:
		_print("no se pudo generar el Pokémon")
		return
	var s := _self()
	var sv := func(f: String) -> Variant: return G.fget(s, s, float(sr.id), f)
	var set1 := func(arr: String, v: Variant) -> void: G.aset(G.g, arr, slot, 0, v)
	var info := func(j: int, v: Variant) -> void: G.aset(G.g, "info", slot, j, v)
	_call("GetSecurityPK")
	_call("GetSecurityPK2")
	set1.call("pkmn1", pk)
	set1.call("nivel1", nv)
	set1.call("indexnivel", nv)
	set1.call("indexpkmn", pk)
	set1.call("extraInfo", 0.0)
	set1.call("exp1", _call("CrecimientoPokemon", [pk, nv]))
	set1.call("IV", sv.call("iv_generated"))
	set1.call("pkmnsex1", sv.call("sex_generated"))
	set1.call("selue_pk1", sv.call("selue_generated"))
	set1.call("objpoke1", 0.0)
	info.call(0, 0.0)
	info.call(1, nv)
	info.call(2, G.g.get("lugar", 0.0))
	info.call(3, 10.0)
	info.call(4, "")
	info.call(5, "") # no nickname (getMote would ask with a dialog), like the game's gifts
	info.call(6, sv.call("isep_generated"))
	info.call(7, _call("GetSecondsInterna"))
	info.call(8, _call("GetSecondsReal"))
	info.call(9, 0.0)
	info.call(10, _call("EstableceLogro", [0.0, 0.0, 1.0]))
	info.call(11, _call("ActualizaHabExt", [0.0, float(slot)]))
	info.call(12, 0.0)
	info.call(13, sv.call("isep_generated"))
	info.call(14, sv.call("selue_generated"))
	info.call(15, G.g.get("fy_001", 0.0))
	G.g["fy_001"] = G.g.get("fy_001", 0.0) + 1.0
	_call("SecurityPK")
	_call("SecurityPK2")
	_call("ColocaAtaquesPropio", [float(slot), pk, nv])
	_call("CentroPokemon", [1.0])
	var dex := G.ri(_call("GetOrdenDex", [pk]))
	G.aset(G.g, "pkdexV", dex, 0, 1.0)
	G.aset(G.g, "pkdexC", dex, 0, 1.0)
	_call("Destruye", [sr.id])
	_print("%s nivel %s añadido al equipo (posición %d)" % [name, _fmt(nv), slot + 1])

## Makes the next boot skip the intro and load `slot`, through the game's own `data/partidas/load`
## file (it uses it to reload after changing slot).
static func request_load(game_root: String, slot: int) -> void:
	var f := FileAccess.open(game_root.path_join("data/partidas/load"), FileAccess.WRITE)
	if f:
		f.store_string("%d\r\n" % slot)

## The F5 save without KeyActionsExplorer's restrictions (cutscene objects, obj_NO_SAVE, ...).
static func _save() -> void:
	var p := _need_prota()
	if p == null:
		return
	if not (p.x >= 0 and p.x <= G.gv_room_width() and p.y >= 0 and p.y <= G.gv_room_height()):
		_print("el protagonista está fuera del mapa")
		return
	# GuardarPartida also bails out while the player is moving.
	p.speed = 0.0
	_call("GuardarPartida", [1.0])
	_print("partida guardada en el slot %s" % _fmt(G.g.get("Slot", "?")))
