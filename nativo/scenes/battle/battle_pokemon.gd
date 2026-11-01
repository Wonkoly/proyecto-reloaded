class_name BattlePokemon
extends CharacterBody2D
## Un Pokémon dentro de la batalla. No lee input: un BattleController hijo le manda la
## dirección (set_direccion) y las órdenes (atacar).

signal hp_cambiado(hp: int, hp_max: int)
signal energia_cambiada(energia: int, energia_max: int)
signal debilitado
## Usó un movimiento (para el panel de mensajes: "X usó Y.").
signal ataco(move: MoveData)
## Le pegó un ataque ("Y ha golpeado a X. Es muy efectivo.").
signal golpeado(move: MoveData, danio: int, eficacia: float)
signal movido(posicion: Vector2)
## Una línea para el panel de mensajes (AddTextToBuffer): estados y cambios de stats.
signal mensaje(texto: String)

const ESCENA_PROYECTIL: PackedScene = preload("res://scenes/battle/proyectil.tscn")
## Límites de velocidad del original (2-15 px/step).
const VELOCIDAD_MIN: float = 60.0
const VELOCIDAD_MAX: float = 450.0
## Recarga de energía: +1 por step (BattlePsPpOptimize).
const RECARGA_ENERGIA: float = 30.0
## Cuánto se ve la pose de herido al recibir un golpe (provisional, ver docs).
const DURACION_HERIDO: float = 0.2
## Dirección (teclado numérico) de cada sector de 45°: desde la derecha, en sentido horario.
const MIRA_POR_SECTOR: Array[int] = [6, 3, 2, 1, 4, 7, 8, 9]
## Sin dibujo propio, las direcciones de la izquierda usan las de la derecha volteadas.
const ESPEJO: Dictionary[int, int] = {1: 3, 4: 6, 7: 9}

## 1 = jugador, 2 = rival.
@export var lado: int = 1
## A quién apuntan sus ataques.
var objetivo: BattlePokemon
## (17).HAB1 / HAB2: la habilidad del Pokémon en combate.
var habilidad: int = 0

var pokemon: PokemonInstance
var hp_max: int = 1
var energia_max: int = 1
## px/s
var velocidad: float = 0.0
## Vector unitario en una de las 8 direcciones, o cero.
var direccion: Vector2 = Vector2.ZERO
## Hacia dónde mira, en notación de teclado numérico.
var mira: int = 2

## Energía con decimales (la recarga es continua); pokemon.energia_actual guarda la parte entera.
var _energia: float = 0.0
## Segundos que faltan para poder volver a atacar / moverse / dejar la pose de herido.
var _cooldown: float = 0.0
var _bloqueo: float = 0.0
## Despedido por el autogolpe de la confusión (velocidad que se frena sola).
var _retroceso: Vector2 = Vector2.ZERO
var _herido: float = 0.0
## Etapas de stats en este combate (Mod_At, Mod_Def... y prec): 1 At, 2 Def, 3 AtEsp, 4 DefEsp,
## 5 Vel, 6 Precisión.
var _etapas: Dictionary[int, int] = {}
## Segundos que le quedan a un estado con duración (dormido, congelado, confusión, enamorado).
var _estado_tiempo: float = 0.0
var _acum_estado: float = 0.0
## Restos (303): 1 entre _restos por step de curar; empieza en 80 y sube hasta 300 (EffectHabilityStep).
var _restos: int = 0
var _acum_objeto: float = 0.0

## TextBattle de "X sufre ..." por estado (STD) y de "- At. de X ..." por stat.
const TEXTO_ESTADO: Dictionary[int, int] = {1: 27, 2: 25, 3: 23, 4: 28, 5: 26, 6: 24, 7: 30, 8: 31, 9: 29}
const TEXTO_STAT: Dictionary[int, int] = {1: 32, 2: 34, 3: 33, 4: 35, 5: 36, 6: 37}
## EffectStatuses: tipos que no sufren cada estado (o se curan).
const INMUNE: Dictionary[int, Array] = {1: [Tipos.Tipo.ELECTRICO], 2: [Tipos.Tipo.FUEGO],
	4: [Tipos.Tipo.VENENO, Tipos.Tipo.ACERO], 5: [Tipos.Tipo.HIELO], 8: [Tipos.Tipo.NORMAL], 9: [Tipos.Tipo.PLANTA]}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	if pokemon:
		_aplicar_pokemon()


## Asigna el Pokémon que representa (antes o después de entrar al árbol).
func configurar(p: PokemonInstance) -> void:
	pokemon = p
	if is_node_ready():
		_aplicar_pokemon()


func set_direccion(dir: Vector2) -> void:
	if dir.length() < 0.2:
		direccion = Vector2.ZERO
	else:
		var sector: int = wrapi(roundi(dir.angle() / (PI / 4.0)), 0, 8)
		direccion = Vector2.RIGHT.rotated(sector * PI / 4.0)
		mira = MIRA_POR_SECTOR[sector]
	_actualizar_animacion()


## Gira hacia un punto sin moverse.
func mirar_hacia(punto: Vector2) -> void:
	var dir: Vector2 = global_position.direction_to(punto)
	if dir != Vector2.ZERO:
		mira = MIRA_POR_SECTOR[wrapi(roundi(dir.angle() / (PI / 4.0)), 0, 8)]
	_actualizar_animacion()


func esta_debilitado() -> bool:
	return pokemon == null or pokemon.hp_actual <= 0


func puede_moverse() -> bool:
	return not esta_debilitado() and _bloqueo <= 0.0 and not _inmovil()


## Dormido o congelado: no se mueve ni ataca (Pokemon1Movimiento, STD = 3 o 5).
func _inmovil() -> bool:
	return pokemon != null and pokemon.estado in [MoveData.Estado.DORMIDO, MoveData.Estado.CONGELADO]


func etapa(stat: int) -> int:
	return _etapas.get(stat, 0)


func puede_recibir_danio() -> bool:
	return not esta_debilitado()


## Si puede usar ya el movimiento: sin cooldown y con energía suficiente, o con la barra llena
## aunque no alcance (entonces queda negativa), como PossibleAttack del original.
func puede_atacar(indice: int) -> bool:
	if esta_debilitado() or _cooldown > 0.0 or indice < 0 or indice >= pokemon.movimientos.size() or _inmovil():
		return false
	var costo: int = pokemon.movimientos[indice].costo_energia
	return _energia >= costo or _energia >= energia_max


## Si tiene algún movimiento y no está en cooldown.
func movimientos_disponibles() -> bool:
	return not esta_debilitado() and _cooldown <= 0.0 and not pokemon.movimientos.is_empty()


## Usa el movimiento `indice` (0-3). Devuelve false si no pudo.
func atacar(indice: int) -> bool:
	if not puede_atacar(indice):
		return false
	var move: MoveData = pokemon.movimientos[indice]
	if _falla_por_estado(move):
		return false
	_set_energia(_energia - move.costo_energia)
	_cooldown = move.cooldown
	_bloqueo = move.bloqueo_movimiento
	if move.modo == MoveData.Modo.ESTADO and not move.cambios_propios.is_empty():
		_cambiar_stats(move, self, move.cambios_propios)  # sobre sí mismo, sin proyectil
	var total: int = move.golpes[randi() % move.golpes.size()] if not move.golpes.is_empty() else 1
	_lanzar(move, total, total)
	ataco.emit(move)
	return true


## EffectAtackDestroy: el siguiente golpe de un ataque múltiple (gasta la energía otra vez, "X usó Y.";
## en el último, "N golpes."). No ataca ni se mueve un momento (canshoot 15 steps, canmove 5).
func siguiente_golpe(move: MoveData, restantes: int, total: int) -> void:
	if esta_debilitado() or objetivo == null or objetivo.esta_debilitado():
		return
	_set_energia(_energia - move.costo_energia)
	_cooldown = maxf(_cooldown, 15.0 / 30.0)
	_bloqueo = maxf(_bloqueo, 5.0 / 30.0)
	var texto: String = Textos.par(Textos.batalla(195), Progreso.nombre(pokemon), move.nombre)
	if restantes == 1:
		texto += Textos.par(Textos.batalla(300), str(total))
	mensaje.emit(texto)
	_lanzar(move, restantes, total)


func _lanzar(move: MoveData, restantes: int, total: int) -> void:
	var proyectil: Proyectil = ESCENA_PROYECTIL.instantiate()
	# El original apunta al rival (point_direction al objetivo); sin rival, hacia donde mira.
	var dir: Vector2 = global_position.direction_to(objetivo.global_position) \
		if objetivo and not objetivo.esta_debilitado() else Vector2.RIGHT.rotated(MIRA_POR_SECTOR.find(mira) * PI / 4.0)
	# Con la precisión cambiada se desvía ± random(prec × 10) grados (CreateAttack).
	if etapa(6) != 0:
		dir = dir.rotated(deg_to_rad(randf() * absi(etapa(6)) * 10.0 * (1 if randf() < 0.5 else -1)))
	proyectil.configurar(move, self, dir)
	proyectil.golpes_restantes = restantes
	proyectil.golpes_total = total
	proyectil.global_position = global_position
	get_parent().add_child(proyectil)
	_actualizar_animacion()


## PossibleAttack: paralizado (1 de 3) o enamorado (1 de 3) no ataca, gasta la energía del ataque o 40,
## y queda quieto 10 steps; confuso (1 de 2) se golpea a sí mismo (Pokemon1AutoHit).
func _falla_por_estado(move: MoveData) -> bool:
	match pokemon.estado:
		MoveData.Estado.PARALISIS, MoveData.Estado.ENAMORADO:
			if randi_range(1, 3) != 3:
				return false
			var paralisis: bool = pokemon.estado == MoveData.Estado.PARALISIS
			_set_energia(_energia - (move.costo_energia if paralisis else 40))
			_bloqueo = 10.0 / 30.0
			mensaje.emit(Textos.par(Textos.batalla(169 if paralisis else 198), Progreso.nombre(pokemon)))
			_actualizar_animacion()
			return true
		MoveData.Estado.CONFUSION:
			if randi_range(1, 2) != 2:
				return false
			mensaje.emit(Textos.par(Textos.batalla(199), Progreso.nombre(pokemon)))
			autogolpe()
			return true
	return false


## Pokemon1AutoHit: un golpe de poder 40 con su Ataque contra su Defensa (con etapas), ×0.85 y ÷ PowDif;
## gasta 40 de energía y sale despedido en una dirección al azar (speed 4, friction 0.2) 10 steps.
func autogolpe() -> void:
	var stats: Dictionary = pokemon.calcular_stats()
	var at: float = stats["ataque"] * FormulasBatalla.factor_etapa(etapa(1))
	var df: float = maxf(stats["defensa"] * FormulasBatalla.factor_etapa(etapa(2)), 1.0)
	var danio: float = (((2.0 * pokemon.nivel / 5.0 + 2.0) * (at * 40.0 / df) / 50.0) + 2.0) * 0.85
	var dano: int = roundi(ceilf(danio / GameState.pow_dif(lado)))
	_set_energia(_energia - 40.0)
	golpeado.emit(null, dano, 1.0)
	recibir_danio(dano)
	_retroceso = Vector2.RIGHT.rotated(randf() * TAU) * 120.0
	_bloqueo = 10.0 / 30.0


## Habilidades que no tocan al Pokémon que pega (Intimidación) y las que bloquean la bajada (Ritmo
## Propio, Despiste, Cuerpo Puro, Corazón Audaz...: UsaIntimidacion).
const CONTRA_INTIMIDACION: Array[int] = [29, 52, 73, 220, 12, 290]
## Ataque2GolpeaPokemon1 / SecEffect: estado que provoca al atacante que hace contacto la habilidad del que
## recibe (1 de cada 3 × PowDif): Elec. Estática parálisis, Punto Tóxico veneno, Cuerpo Llama quemadura,
## Gran Encanto enamoramiento; y los tipos (del original) que lo evitan.
const CONTACTO: Dictionary[int, Array] = {9: [MoveData.Estado.PARALISIS, [5]], 38: [MoveData.Estado.ENVENENADO, [10, 14]],
	49: [MoveData.Estado.QUEMADO, [2]], 56: [MoveData.Estado.ENAMORADO, []]}
## Absorben un tipo (tipo del original → 1 recupera PS, 2 se lo come sin daño): Absorbe Elec. (10),
## Absorbe Agua y Piel Seca (11, 87), Absorbe Fuego (18), y la 284 con Tierra.
const ABSORBE: Dictionary[int, Array] = {10: [5, 1], 11: [3, 1], 87: [3, 1], 18: [2, 2], 284: [8, 1]}


## EffectHabilityCreate / UsaIntimidacion: lo que hacen algunas habilidades al salir al combate.
func al_entrar() -> void:
	match habilidad:
		22:  # Intimidación: −1 al Ataque del rival
			if objetivo and not objetivo.esta_debilitado():
				habilidad_actuo()
				if objetivo.habilidad in CONTRA_INTIMIDACION:
					objetivo.habilidad_actuo()
				else:
					_cambiar_stats(null, objetivo, {1: -1})
		26, 313:  # Levitación: no la tocan los ataques de Tierra (efecto 582)
			habilidad_actuo()
		14, 162:  # Ojo Compuesto: +4 a la precisión
			habilidad_actuo()
			_cambiar_stats(null, self, {6: 4})


func levita() -> bool:
	return habilidad in [26, 313]


## 0 si el ataque le hace daño normal; 1 si lo absorbe y recupera PS; 2 si se lo come sin daño.
func absorbe(move: MoveData) -> int:
	var a: Array = ABSORBE.get(habilidad, [])
	return int(a[1]) if not a.is_empty() and FormulasBatalla.TIPO_ORIGINAL[move.tipo] == int(a[0]) else 0


## hab_fugaz: el aviso de que actuó su habilidad (TextBattle 188: " (X actuó)").
func habilidad_actuo() -> void:
	mensaje.emit(Progreso.nombre(pokemon) + Textos.par(Textos.batalla(188), Habilidades.nombre(habilidad)))


## Lo alcanza un ataque: avisa (golpeado) y aplica el daño.
func recibir_golpe(move: MoveData, danio: int, eficacia: float) -> void:
	if esta_debilitado():
		return
	golpeado.emit(move, danio, eficacia)
	recibir_danio(danio)


## Ataque de contacto: el Pokémon va con el ataque (lo mueve el Proyectil) y no responde mientras.
func embestir(duracion: float) -> void:
	_bloqueo = maxf(_bloqueo, duracion)
	direccion = Vector2.ZERO
	_actualizar_animacion()


## SecEffect1: lo que hace un golpe además del daño (estado, stats del rival y del atacante,
## retroceso y drenaje).
func efectos_de_golpe(move: MoveData, atacante: BattlePokemon, danio: int) -> void:
	# Las habilidades de contacto del que recibe, 1 de cada 3 × PowDif de su lado.
	if move.contacto and habilidad in CONTACTO and atacante.pokemon.estado == MoveData.Estado.NINGUNO \
			and randi_range(1, 3 * GameState.pow_dif(lado)) == 3 * GameState.pow_dif(lado):
		var c: Array = CONTACTO[habilidad]
		var tipos_at: Array = atacante.pokemon.especie.tipos.map(func(t: Tipos.Tipo) -> int: return FormulasBatalla.TIPO_ORIGINAL[t])
		var evita: bool = (c[1] as Array).any(func(t: int) -> bool: return t in tipos_at)
		if habilidad == 56:
			evita = atacante.pokemon.sexo == pokemon.sexo
		elif habilidad == 49:
			evita = evita or atacante.habilidad in [200, 296]
		if not evita and atacante.aplicar_estado(c[0]):
			habilidad_actuo()
	if move.estado != MoveData.Estado.NINGUNO and randi_range(1, 100) <= move.prob_estado:
		aplicar_estado(move.estado, move)
	if (not move.cambios_rival.is_empty() or not move.cambios_propios.is_empty()) and randi_range(1, 100) <= move.prob_cambios:
		if not esta_debilitado():
			_cambiar_stats(move, self, move.cambios_rival)
		if move.modo != MoveData.Modo.ESTADO:
			_cambiar_stats(move, atacante, move.cambios_propios)
	# La gema se gasta al potenciar un golpe.
	if danio > 0 and FormulasBatalla.es_gema_de(atacante.pokemon.objeto, move):
		atacante.pokemon.objeto = 0
	# Vidasfera (377): el atacante pierde PS máximo / (10 × PowDif del otro lado).
	if atacante.pokemon.objeto == 377 and danio > 0:
		atacante.recibir_danio(ceili(atacante.hp_max / (10.0 * GameState.pow_dif(lado))))
	if move.retroceso > 0 and danio > 0:
		atacante.recibir_danio(ceili(float(danio) / move.retroceso))
	# SecEffect1: recupera floor(daño × drenaje), al menos 1; con Raíz Grande (370) ×1.3.
	if move.drenaje > 0.0 and danio > 0:
		var raiz: float = 1.3 if atacante.pokemon.objeto == 370 else 1.0
		atacante.curar(maxi(1, floori(danio * raiz * move.drenaje)))


## ModificaStat: etapas entre −12 y 12, con el mensaje "Ataque - At. de X bajó/subió mucho...".
static func _cambiar_stats(move: MoveData, quien: BattlePokemon, cambios: Dictionary[int, int]) -> void:
	for stat: int in cambios:
		var n: int = cambios[stat]
		var limite: int = 6 if stat == 6 else 12
		var antes: int = quien.etapa(stat)
		quien._etapas[stat] = clampi(antes + n, -limite, limite)
		var cambio: int = quien._etapas[stat] - antes
		var palabra: int
		if cambio == 0:
			palabra = 64 if n > 0 else 56
		else:
			palabra = (58 if n > 0 else 50) + clampi(absi(n), 1, 3) - 1
		quien.mensaje.emit((move.nombre if move else "") + Textos.par(Textos.batalla(TEXTO_STAT[stat]),
			Progreso.nombre(quien.pokemon), Textos.batalla(palabra)))
	quien.velocidad = quien._velocidad_actual()


## STD: un estado nuevo solo si no tiene otro y su tipo no lo evita. Dormido 150-300 steps,
## congelado 200-400, confusión y enamorado 150-350 (EffectStatuses).
func aplicar_estado(nuevo: MoveData.Estado, move: MoveData = null) -> bool:
	if esta_debilitado() or pokemon.estado != MoveData.Estado.NINGUNO:
		return false
	for t: Tipos.Tipo in INMUNE.get(nuevo, []):
		if t in pokemon.especie.tipos:
			return false
	pokemon.estado = nuevo
	_empezar_estado()
	mensaje.emit((move.nombre + " - " if move else "") + Textos.par(Textos.batalla(TEXTO_ESTADO[nuevo]), Progreso.nombre(pokemon)))
	velocidad = _velocidad_actual()
	_actualizar_animacion()
	return true


func _empezar_estado() -> void:
	match pokemon.estado:
		MoveData.Estado.DORMIDO: _estado_tiempo = (150 + randi_range(1, 150)) / 30.0
		MoveData.Estado.CONGELADO: _estado_tiempo = (200 + randi_range(1, 200)) / 30.0
		MoveData.Estado.CONFUSION, MoveData.Estado.ENAMORADO: _estado_tiempo = (150 + randi_range(1, 200)) / 30.0
		_: _estado_tiempo = 0.0


func curar(cantidad: int) -> void:
	if esta_debilitado() or cantidad <= 0:
		return
	pokemon.hp_actual = mini(hp_max, pokemon.hp_actual + cantidad)
	hp_cambiado.emit(pokemon.hp_actual, hp_max)


## EffectStatuses, cada step: veneno y quemado 1/100 de perder 3.125 % del PS máximo; maldición 1/150
## de perder 6.25 %; infección 1/150 de perder 3.125 % (el rival recupera la mitad). Los estados con
## duración se pasan solos.
func _step_estado() -> void:
	match pokemon.estado:
		MoveData.Estado.ENVENENADO, MoveData.Estado.QUEMADO:
			if randi_range(1, 100) == 100:
				recibir_danio(ceili(hp_max * 3.125 / 100.0))
		MoveData.Estado.MALDICION:
			if randi_range(1, 150) == 150:
				recibir_danio(ceili(hp_max * 6.25 / 100.0))
		MoveData.Estado.INFECCION:
			if randi_range(1, 150) == 150:
				var dre: int = ceili(hp_max * 3.125 / 100.0)
				recibir_danio(dre)
				if objetivo:
					objetivo.curar(ceili(dre / 2.0))


## Restos: cura 3.125 % del PS máximo con probabilidad 1/_restos por step, cada vez menos seguido.
func _step_restos() -> void:
	if _restos == 0:
		_restos = 80
	if _restos < 300 and randi_range(1, 10) == 10:
		_restos += 1
	if randi_range(1, _restos) == _restos and pokemon.hp_actual < hp_max:
		curar(ceili(hp_max * 3.125 / 100.0))


## Velocidad con sus etapas (0.25 px/step cada una) y parálisis (÷ 1.125), entre 60 y 450 px/s.
func _velocidad_actual() -> float:
	var v: float = pokemon.calcular_velocidad_batalla() + 7.5 * etapa(5)
	if pokemon.estado == MoveData.Estado.PARALISIS:
		v /= 1.125
	return clampf(v, VELOCIDAD_MIN, VELOCIDAD_MAX)


func recibir_danio(cantidad: int) -> void:
	if esta_debilitado() or cantidad <= 0 or (lado == 1 and GameState.dev_god):
		return
	pokemon.hp_actual = maxi(0, pokemon.hp_actual - cantidad)
	_herido = DURACION_HERIDO
	hp_cambiado.emit(pokemon.hp_actual, hp_max)
	if pokemon.hp_actual == 0:
		direccion = Vector2.ZERO
		debilitado.emit()
	_actualizar_animacion()


func _physics_process(delta: float) -> void:
	var estaba_bloqueado: bool = _bloqueo > 0.0 or _herido > 0.0
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloqueo = maxf(0.0, _bloqueo - delta)
	_herido = maxf(0.0, _herido - delta)
	if lado == 1 and GameState.dev_energia_infinita:
		_set_energia(energia_max)
	if not esta_debilitado() and pokemon.estado != MoveData.Estado.NINGUNO:
		_acum_estado += delta
		while _acum_estado >= 1.0 / 30.0 and not esta_debilitado():
			_acum_estado -= 1.0 / 30.0
			_step_estado()
		if _estado_tiempo > 0.0:
			_estado_tiempo -= delta
			if _estado_tiempo <= 0.0:
				# Pokemon1StateFinish: se despertó, ya no sufre confusión / congelación, volvió a la normalidad.
				var fin: int = {MoveData.Estado.DORMIDO: 184, MoveData.Estado.CONFUSION: 185,
					MoveData.Estado.CONGELADO: 186, MoveData.Estado.ENAMORADO: 187}.get(pokemon.estado, 0)
				if fin:
					mensaje.emit(Textos.par(Textos.batalla(fin), Progreso.nombre(pokemon)))
				pokemon.estado = MoveData.Estado.NINGUNO
				velocidad = _velocidad_actual()
				_actualizar_animacion()
	if not esta_debilitado() and pokemon.objeto == 303:
		_acum_objeto += delta
		while _acum_objeto >= 1.0 / 30.0:
			_acum_objeto -= 1.0 / 30.0
			_step_restos()
	if puede_moverse() and _energia < energia_max:
		_set_energia(minf(_energia + RECARGA_ENERGIA * delta, energia_max))
	if estaba_bloqueado and _bloqueo <= 0.0 and _herido <= 0.0:
		_actualizar_animacion()
	velocity = direccion * velocidad if puede_moverse() else Vector2.ZERO
	if _retroceso != Vector2.ZERO:  # despedido (friction 0.2 px/step por step)
		velocity = _retroceso
		_retroceso = _retroceso.move_toward(Vector2.ZERO, 180.0 * delta)
	var antes: Vector2 = position
	move_and_slide()
	if position != antes:
		movido.emit(position)


func _set_energia(valor: float) -> void:
	var antes: int = floori(_energia)
	_energia = valor
	pokemon.energia_actual = floori(_energia)
	if pokemon.energia_actual != antes:
		energia_cambiada.emit(pokemon.energia_actual, energia_max)


func _aplicar_pokemon() -> void:
	habilidad = pokemon.habilidad()
	hp_max = pokemon.calcular_stats()["hp"]
	energia_max = pokemon.calcular_energia_maxima()
	_etapas.clear()
	velocidad = _velocidad_actual()
	_empezar_estado()
	_energia = pokemon.energia_actual
	sprite.sprite_frames = pokemon.especie.cargar_sprite_frames()
	_actualizar_animacion()
	hp_cambiado.emit(pokemon.hp_actual, hp_max)
	energia_cambiada.emit(pokemon.energia_actual, energia_max)


func _actualizar_animacion() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if esta_debilitado() or _herido > 0.0:
		_pose("herido")
	elif pokemon.estado == MoveData.Estado.DORMIDO and sprite.sprite_frames.has_animation("dormido"):
		sprite.flip_h = false
		sprite.play("dormido")  # sprS a 0.05 por step
	elif _inmovil():
		_pose("herido")  # sin sprS, o congelado: el frame de herido
	elif _bloqueo > 0.0:
		_pose("ataque")
	else:
		var anim: String = _animacion("mover")
		if sprite.animation != anim:
			sprite.animation = anim
		if direccion != Vector2.ZERO:
			sprite.play()
		else:
			# Quieto: el original deja el frame 1 sin animar (Pokemon1Movimiento).
			sprite.stop()
			sprite.frame = mini(1, sprite.sprite_frames.get_frame_count(anim) - 1)


## Poses de un frame por dirección (ataque_<mira>, herido_<mira>).
func _pose(base: String) -> void:
	var anim: String = _animacion(base)
	sprite.animation = anim if sprite.sprite_frames.has_animation(anim) else _animacion("mover")
	sprite.stop()
	sprite.frame = 0


## Nombre de la animación "<base>_<mira>" que existe; pone flip_h si usa la de la derecha volteada.
func _animacion(base: String) -> String:
	var propia: String = "%s_%d" % [base, mira]
	sprite.flip_h = false
	if sprite.sprite_frames.has_animation(propia):
		return propia
	if mira in ESPEJO:
		sprite.flip_h = true
		return "%s_%d" % [base, ESPEJO[mira]]
	return "%s_2" % base
