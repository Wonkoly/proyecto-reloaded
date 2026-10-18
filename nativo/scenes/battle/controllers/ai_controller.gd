class_name AIController
extends BattleController
## IA del rival, según Pokemon2Movimiento, CreateAttack y BattleEstrategia del original.
## Las probabilidades del original son por step (30/s); aquí se convierten a tiempo real con
## _ocurre(), así no dependen de los FPS.

const STEPS_POR_SEGUNDO: float = 30.0

## Entrenador: elige el ataque con pesos (BattleEstrategia). Si no, al azar (salvaje).
@export var entrenador: bool = false
## "Crack" (EsUnCrack: líderes, rivales fuertes): arranca antes y prefiere ataques efectivos.
@export var crack: bool = false
## Maestro (MASTERTRAINER: legendarios, algunos líderes): persigue si tiene más energía.
@export var maestro: bool = false

var _moviendose: bool = false
var _direccion: Vector2 = Vector2.ZERO


func _controlar(delta: float) -> void:
	var rival: BattlePokemon = pokemon.objetivo
	if pokemon.esta_debilitado() or rival == null:
		pokemon.set_direccion(Vector2.ZERO)
		return
	_mover(delta, rival)
	_quizas_atacar(delta, rival)


## Probabilidad de que algo que en el original pasa con probabilidad 1/n por step ocurra en este frame.
func _ocurre(n: float, delta: float) -> bool:
	return randf() < 1.0 - pow(1.0 - 1.0 / maxf(n, 1.0), STEPS_POR_SEGUNDO * delta)


func _mover(delta: float, rival: BattlePokemon) -> void:
	var hay_ataque_rival: bool = _hay_proyectil_de(rival)
	var fisico: bool = pokemon.pokemon.movimientos.any(
		func(m: MoveData) -> bool: return m.categoria == MoveData.Categoria.FISICO)
	# Cambio de dirección al azar: 1/50 por step; quieto y "crack": 1/10, o ya si hay un ataque encima.
	var n: float = 50.0
	if not _moviendose and crack:
		n = 1.0 if hay_ataque_rival else 10.0
	if _ocurre(n, delta):
		_moviendose = true
		if fisico and not hay_ataque_rival and randi_range(1, 3) == 3:
			_direccion = pokemon.global_position.direction_to(rival.global_position)
		else:
			_direccion = Vector2.RIGHT.rotated(randf() * TAU)
	if maestro:
		if _con_ventaja(rival):
			# Persigue; a menos de 32 px se detiene.
			_moviendose = pokemon.global_position.distance_to(rival.global_position) > 32.0
			_direccion = pokemon.global_position.direction_to(rival.global_position)
		elif not _moviendose:
			_moviendose = true
			_direccion = Vector2.RIGHT.rotated(randf() * TAU)
	# Aproximación: el original no rebota en las paredes al caminar; aquí busca otra dirección.
	if _moviendose and pokemon.get_slide_collision_count() > 0:
		_direccion = Vector2.RIGHT.rotated(randf() * TAU)
	if _moviendose:
		pokemon.set_direccion(_direccion)
	else:
		pokemon.set_direccion(Vector2.ZERO)
		pokemon.mirar_hacia(rival.global_position)  # quieto mira al rival (Refresh_Mira)


func _quizas_atacar(delta: float, rival: BattlePokemon) -> void:
	if not pokemon.movimientos_disponibles():
		return
	# Ataca con probabilidad 1/F por step: F = 15 quieto, 30 en movimiento, 5 si persigue de cerca.
	var f: float = 30.0 if _moviendose else 15.0
	if maestro and _con_ventaja(rival) and pokemon.global_position.distance_to(rival.global_position) < 80.0:
		f = 5.0
	if GameState.dificultad == GameState.Dificultad.FACIL:
		f *= 2.0
	elif GameState.dificultad >= GameState.Dificultad.DIFICIL:
		f = ceilf(f / 2.0)
	if not _ocurre(f, delta):
		return
	var indice: int = _elegir_ataque(rival) if entrenador else randi_range(0, pokemon.pokemon.movimientos.size() - 1)
	if pokemon.atacar(indice):
		_moviendose = false  # el original pone speed = 0 al atacar


## BattleEstrategia: 25 de peso por movimiento; los "crack" multiplican por la efectividad.
## Faltan las reglas de movimientos concretos (ver docs).
func _elegir_ataque(rival: BattlePokemon) -> int:
	var movs: Array[MoveData] = pokemon.pokemon.movimientos
	var pesos: Array[float] = []
	for m: MoveData in movs:
		var peso: float = 25.0
		if m.poder > 0:
			var eff: float = Efectividad.multiplicador(m.tipo, rival.pokemon.especie.tipos)
			if eff == 0.0:
				peso = 0.0  # generaliza las reglas del original (eléctrico contra tierra...)
			elif crack:
				peso *= {4.0: 10.0, 2.0: 5.0, 0.5: 0.2, 0.25: 0.1}.get(eff, 1.0)
		pesos.append(peso)
	var total: float = 0.0
	for p: float in pesos:
		total += p
	if total <= 0.0:
		return randi_range(0, movs.size() - 1)
	var azar: float = randf() * total
	for i: int in pesos.size():
		azar -= pesos[i]
		if azar < 0.0:
			return i
	return pesos.size() - 1


func _con_ventaja(rival: BattlePokemon) -> bool:
	return pokemon.pokemon.energia_actual > rival.pokemon.energia_actual


func _hay_proyectil_de(rival: BattlePokemon) -> bool:
	for n: Node in pokemon.get_parent().get_children():
		if n is Proyectil and (n as Proyectil).duenio == rival:
			return true
	return false
