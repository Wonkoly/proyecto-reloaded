extends SceneTree
## Efectos en combate: confusión (se golpea a sí mismo), parálisis (pierde el turno), drenaje y
## ataques múltiples, con dos Pokémon frente a frente.
##   ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/prueba_efectos.gd

var _fallas: int = 0
var _golpes: int = 0
var _mensajes: Array[String] = []


func _initialize() -> void:
	await process_frame
	var arena := Node2D.new()
	root.add_child(arena)
	var a = _pokemon(arena, 1, 68, Vector2(100, 160))  # Machamp
	var b = _pokemon(arena, 2, 143, Vector2(220, 160))  # Snorlax
	a.objetivo = b
	b.objetivo = a
	b.golpeado.connect(func(_m, _d, _e) -> void: _golpes += 1)
	a.mensaje.connect(func(t: String) -> void: _mensajes.append(t))
	await physics_frame
	var bofeton: Resource = load("res://data/extraido/moves/0025_doble_bofeton.tres")
	var gigadrenado: Resource = load("res://data/extraido/moves/0252_gigadrenado.tres")
	a.pokemon.movimientos.assign([bofeton, gigadrenado])

	# Confusión: con el dado a favor se golpea a sí mismo y no lanza nada.
	a.pokemon.estado = 6  # CONFUSION
	var autogolpes: int = 0
	for i: int in 20:
		a._cooldown = 0.0
		a._set_energia(a.energia_max)
		var hp: int = a.pokemon.hp_actual
		if not a.atacar(0) and a.pokemon.hp_actual < hp:
			autogolpes += 1
	_ok(autogolpes >= 4 and autogolpes <= 16, "confuso se golpea a sí mismo cerca de la mitad de las veces (%d de 20)" % autogolpes)
	_ok(_mensajes.any(func(t: String) -> bool: return "a sí mismo" in t), "avisa \"se hiere a sí mismo\"")

	# Parálisis: 1 de cada 3 no ataca.
	a.pokemon.estado = 1  # PARALISIS
	var fallos: int = 0
	for i: int in 30:
		a._cooldown = 0.0
		a._set_energia(a.energia_max)
		if not a.atacar(0):
			fallos += 1
	_ok(fallos >= 3 and fallos <= 18, "paralizado falla cerca de 1 de cada 3 (%d de 30)" % fallos)
	arena.free()

	# Ataque múltiple: Doble bofetón golpea de 2 a 5 veces (en una arena nueva).
	arena = Node2D.new()
	root.add_child(arena)
	a = _pokemon(arena, 1, 68, Vector2(100, 160))
	b = _pokemon(arena, 2, 143, Vector2(160, 160))
	a.objetivo = b
	b.objetivo = a
	b.golpeado.connect(func(_m, _d, _e) -> void: _golpes += 1)
	a.mensaje.connect(func(t: String) -> void: _mensajes.append(t))
	a.pokemon.movimientos.assign([bofeton, gigadrenado])
	await physics_frame
	_golpes = 0
	_mensajes.clear()
	a.atacar(0)
	await create_timer(4.0).timeout
	_ok(_golpes >= 2 and _golpes <= 5, "Doble bofetón golpea de 2 a 5 veces (%d)" % _golpes)
	_ok(_mensajes.any(func(t: String) -> bool: return "golpes" in t), "al final dice cuántos golpes: %s" % str(_mensajes))

	# Drenaje: Gigadrenado recupera la mitad del daño.
	a.pokemon.hp_actual = 1
	b.pokemon.hp_actual = b.hp_max
	a._cooldown = 0.0
	a._set_energia(a.energia_max)
	a.global_position = Vector2(100, 160)
	a.atacar(1)
	await create_timer(3.0).timeout
	var hecho: int = b.hp_max - b.pokemon.hp_actual
	_ok(hecho > 0 and a.pokemon.hp_actual - 1 == maxi(1, hecho / 2), "Gigadrenado recupera la mitad del daño (hizo %d, recuperó %d)" % [hecho, a.pokemon.hp_actual - 1])
	print("RESULTADO: ", "todo bien" if _fallas == 0 else "%d fallas" % _fallas)
	quit(_fallas)


func _pokemon(arena: Node2D, lado: int, especie: int, pos: Vector2) -> Node:
	var bp: Node = load("res://scenes/battle/battle_pokemon.tscn").instantiate()
	bp.lado = lado
	bp.position = pos
	bp.configurar(load("res://scripts/resources/pokemon_instance.gd").crear(load("res://scripts/datos.gd").especie(especie), 50))
	arena.add_child(bp)
	return bp


func _ok(c: bool, que: String) -> void:
	print(("PASA  " if c else "FALLA ") + que)
	if not c:
		_fallas += 1
