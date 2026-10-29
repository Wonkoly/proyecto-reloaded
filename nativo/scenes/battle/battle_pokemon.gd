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
	_set_energia(_energia - move.costo_energia)
	_cooldown = move.cooldown
	_bloqueo = move.bloqueo_movimiento
	var proyectil: Proyectil = ESCENA_PROYECTIL.instantiate()
	# El original apunta al rival (point_direction al objetivo); sin rival, hacia donde mira.
	var dir: Vector2 = global_position.direction_to(objetivo.global_position) \
		if objetivo and not objetivo.esta_debilitado() else Vector2.RIGHT.rotated(MIRA_POR_SECTOR.find(mira) * PI / 4.0)
	# Con la precisión cambiada se desvía ± random(prec × 10) grados (CreateAttack).
	if etapa(6) != 0:
		dir = dir.rotated(deg_to_rad(randf() * absi(etapa(6)) * 10.0 * (1 if randf() < 0.5 else -1)))
	if move.modo == MoveData.Modo.ESTADO and not move.cambios_propios.is_empty():
		_cambiar_stats(move, self, move.cambios_propios)  # sobre sí mismo, sin proyectil
	proyectil.configurar(move, self, dir)
	proyectil.global_position = global_position
	get_parent().add_child(proyectil)
	_actualizar_animacion()
	ataco.emit(move)
	return true


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
	if move.drenaje > 0 and danio > 0:
		atacante.curar(ceili(float(danio) / move.drenaje))


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
		quien.mensaje.emit(move.nombre + Textos.par(Textos.batalla(TEXTO_STAT[stat]),
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
				pokemon.estado = MoveData.Estado.NINGUNO  # Pokemon1StateFinish
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
