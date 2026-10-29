class_name Jugador
extends CharacterBody2D
## El protagonista en el overworld (obj_Prota: ProtaMovimiento, ProtaSetSprite). Movimiento libre
## por píxel en 8 direcciones (en diagonal, velocidad / √2), a 90 px/s andando, 120 corriendo y 60
## lento; quieto deja el frame 1 sin animar.

const VELOCIDAD_ANDAR: float = 90.0     # 3 px/step
const VELOCIDAD_CORRER: float = 120.0   # 4 px/step
const VELOCIDAD_LENTO: float = 60.0     # 2 px/step
## image_speed (frames por step) × 30.
const FPS_ANDAR: float = 6.0
const FPS_CORRER: float = 7.5
const FPS_LENTO: float = 4.5
## Vista del original: 320×180 y la sigue con un borde horizontal de 120 px (hborder).
const BORDE_VISTA: float = 120.0
## Capa de física de las zonas (hierba).
const CAPA_ZONAS: int = 32
## Steps del original por segundo (room_speed).
const STEPS_POR_SEGUNDO: float = 30.0
## Paredes (capa 1), agua (capa 7: sin Surf no se pisa) y lava (capa 8: Ola Lava, pendiente).
const CAPAS_CHOQUE: int = 1 | 64 | 128
const CAPA_AGUA: int = 64
const VECTOR_MIRA: Dictionary[int, Vector2] = {2: Vector2.DOWN, 8: Vector2.UP, 4: Vector2.LEFT, 6: Vector2.RIGHT,
	1: Vector2(-1, 1), 3: Vector2(1, 1), 7: Vector2(-1, -1), 9: Vector2(1, -1)}

@export var sprite_abajo: SpriteOriginal
@export var sprite_arriba: SpriteOriginal
@export var sprite_derecha: SpriteOriginal

## Notación de teclado numérico, como mira en el original.
var mira: int = 2
var _frame: float = 1.0
var _moviendose: bool = false
## Saltando al agua al empezar a surfear: no se mueve ni deja el surf mientras dura.
var _entrando_agua: bool = false
## Salidas que ya tocaba en el frame anterior (las de "al entrar" se activan al llegar, no al aparecer).
var _salidas_dentro: Array[Salida] = []
var _primer_frame: bool = true
var _tabla: TablaEncuentros
## El salto que se está cruzando y su dirección (fija mientras dura, como global.wait = 3).
var _salto: Salto
var _empuje: Vector2 = Vector2.ZERO
var _empuje_restante: float = 0.0
var _dir_salto: Vector2 = Vector2.ZERO

@onready var camara: Camera2D = $Camera2D


func _ready() -> void:
	_aplicar_personaje()
	var mapa: Mapa = _mapa()
	if mapa:
		_tabla = TablaEncuentros.de_mapa(mapa.nombre_original)
		camara.limit_left = 0
		camara.limit_top = 0
		camara.limit_right = mapa.tamano.x
		camara.limit_bottom = mapa.tamano.y
	camara.drag_left_margin = 1.0 - BORDE_VISTA / 160.0
	camara.drag_right_margin = camara.drag_left_margin
	camara.reset_smoothing()


func _algun_entrenador_viene() -> bool:
	for npc: Npc in get_tree().get_nodes_in_group("npcs"):
		if npc._yendo == self or ((npc.entrenador != 0 or npc.vigila) and npc._hablando):
			return true
	return false


## Z (interactuar): el primer NPC que responde (lo mira de frente o lo toca) habla.
func _unhandled_input(evento: InputEvent) -> void:
	# O (key_menu_mochila): la mochila.
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.physical_keycode == KEY_O \
			and not SceneManager.en_transicion and not Eventos.en_curso and quieto():
		get_viewport().set_input_as_handled()
		Mochila.abrir(self)
		return
	if SceneManager.en_transicion or _salto or Eventos.en_curso or evento.is_echo():
		return
	# Obstáculos de MO (KeyActionsCorte...): con Z o con la tecla de su MO (1 Corte, 4 Fuerza, 6 Golpe Roca).
	var tecla_mo: Key = (evento as InputEventKey).physical_keycode if evento is InputEventKey and evento.pressed else KEY_NONE
	# 2 (key_ex_mo2_vuelo): la pantalla de Vuelo.
	if tecla_mo == KEY_2 and quieto():
		get_viewport().set_input_as_handled()
		Vuelo.intentar(self)
		return
	# 3 (key_ex_mo3_surf): de cara al agua, a surfear.
	if tecla_mo == KEY_3 and quieto():
		get_viewport().set_input_as_handled()
		intentar_surf()
		return
	if evento.is_action_pressed("interactuar") or tecla_mo in [KEY_1, KEY_4, KEY_6]:
		var mapa_obs: Mapa = _mapa()
		if mapa_obs and quieto():
			for n: Node in mapa_obs.get_node("Objetos").get_children():
				var obs: Obstaculo = n as Obstaculo
				if obs and obs.visible and (tecla_mo not in [KEY_1, KEY_4, KEY_6] or tecla_mo == obs.tecla()) \
						and obs.frente_a(global_position, mira):
					get_viewport().set_input_as_handled()
					obs.usar(self)
					return
	if not evento.is_action_pressed("interactuar"):
		return
	for npc: Npc in get_tree().get_nodes_in_group("npcs"):
		if not npc.visible or npc.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var giro: int = npc.responde_a(self)
		if giro != 0:
			get_viewport().set_input_as_handled()
			npc.hablar(giro)
			return
	# PCKeyActions: de cara al PC (mirando arriba, centrado y justo debajo) se enciende.
	var mapa: Mapa = _mapa()
	if mapa and mira == 8:
		for n: Node in mapa.get_node("Objetos").get_children():
			if n.name.begins_with("obj_PC_") and n is Node2D:
				var pc: Vector2 = (n as Node2D).position
				if absf(global_position.x - (pc.x + 8.0)) < 10.0 and global_position.y > pc.y + 24.0 \
						and global_position.y < pc.y + 44.0:
					get_viewport().set_input_as_handled()
					CajaPC.usar(self)
					return


## Quieto, sin cruzar un salto y dentro del mapa (lo que pide el original para guardar).
func quieto() -> bool:
	var mapa: Mapa = _mapa()
	var dentro: bool = mapa == null or Rect2(Vector2.ZERO, Vector2(mapa.tamano)).has_point(global_position)
	return not _moviendose and _salto == null and dentro


## Lo mueve solo en `dir` a `velocidad` px/s durante `segundos` (NoPassMueveProta: un NPC lo hace
## retroceder). Mientras dura, el teclado no lo mueve.
func empujar(dir: Vector2, velocidad: float, segundos: float) -> void:
	_empuje = dir * velocidad
	_empuje_restante = segundos
	mira = {Vector2(0, 1): 2, Vector2(0, -1): 8, Vector2(-1, 0): 4, Vector2(1, 0): 6}.get(dir, mira)


## Mira hacia un punto (en 8 direcciones, como Refresh_Mira).
func mirar_a(punto: Vector2) -> void:
	var angulo: float = fposmod(rad_to_deg(-(punto - global_position).angle()), 360.0)
	mira = [6, 9, 8, 7, 4, 1, 2, 3][int(fposmod(angulo + 22.5, 360.0) / 45.0) % 8]
	_frame = 1.0
	queue_redraw()


## Se queda quieto (un entrenador lo vio).
func detener() -> void:
	_moviendose = false
	_frame = 1.0
	velocity = Vector2.ZERO
	queue_redraw()


func _physics_process(delta: float) -> void:
	if SceneManager.en_transicion:
		return
	if Eventos.en_curso or _algun_entrenador_viene() or _entrando_agua:
		detener()
		return
	collision_mask = 0 if GameState.dev_noclip else (CAPAS_CHOQUE & ~CAPA_AGUA if surfeando() else CAPAS_CHOQUE)
	_actualizar_montura()
	if _empuje_restante > 0.0:
		_empuje_restante -= delta
		var frames_empuje: int = _sprite().frames.size() if _sprite() else 1
		_frame = fmod(_frame + 9.0 * delta, frames_empuje)  # image_speed 0.3
		_moviendose = true
		move_and_collide(_empuje * delta)
		if _empuje_restante <= 0.0:
			_frame = 1.0
			_moviendose = false
		queue_redraw()
		return
	var x: float = Input.get_axis("mover_izquierda", "mover_derecha")
	var y: float = Input.get_axis("mover_arriba", "mover_abajo")
	var dir: Vector2 = Vector2(signf(x) if absf(x) > 0.3 else 0.0, signf(y) if absf(y) > 0.3 else 0.0)
	var velocidad: float = VELOCIDAD_ANDAR
	var fps: float = FPS_ANDAR
	if Input.is_action_pressed("correr"):
		velocidad = VELOCIDAD_CORRER
		fps = FPS_CORRER
	elif Input.is_action_pressed("andar_lento"):
		velocidad = VELOCIDAD_LENTO
		fps = FPS_LENTO
	_moviendose = dir != Vector2.ZERO
	if _moviendose:
		mira = {Vector2(0, 1): 2, Vector2(0, -1): 8, Vector2(-1, 0): 4, Vector2(1, 0): 6,
			Vector2(1, 1): 3, Vector2(-1, 1): 1, Vector2(1, -1): 9, Vector2(-1, -1): 7}[dir]
		var frames: int = _sprite().frames.size() if _sprite() else 1
		_frame = fmod(_frame + fps * delta, frames)
	else:
		_frame = 1.0
	velocity = dir.normalized() * velocidad
	var antes: Vector2 = global_position
	move_and_slide()
	# EmpujeFuerza: caminando recto contra una roca redonda con Fuerza activa, la empuja.
	if dir.x == 0.0 or dir.y == 0.0:
		for k: int in get_slide_collision_count():
			var obstaculo: Obstaculo = get_slide_collision(k).get_collider() as Obstaculo
			if obstaculo and obstaculo.empujar(dir):
				break
	_saltar(velocidad, delta)
	# ProtaMovimiento: al dejar el agua termina el surf solo.
	if surfeando() and not sobre_agua(global_position):
		terminar_surf()
	queue_redraw()
	_revisar_salidas()
	_revisar_encuentro(delta, global_position != antes)


## Sobre un salto lo empuja en su dirección a su velocidad + 1 px/step (ProtaSaltos).
## La dirección se decide al empezar a tocarlo y no cambia hasta salir (en el original el salto es
## una animación que congela SENTIDO).
func _saltar(velocidad: float, delta: float) -> void:
	var tocado: Salto = null
	for nodo: Node in get_tree().get_nodes_in_group("saltos"):
		var s: Salto = nodo as Salto
		if s and s.overlaps_body(self):
			tocado = s
			break
	if tocado == null:
		_salto = null
		return
	# Una fila de saltos se cruza de una vez: la dirección se fija con el primero que se toca.
	if _salto == null:
		_salto = tocado
		_dir_salto = tocado.direccion_para(global_position)
	move_and_collide(_dir_salto * (velocidad + 30.0) * delta)


## Está en la hierba si su máscara la toca en su posición y 8 px más abajo (ProtaCheckHierba).
func en_hierba() -> bool:
	return metodo_actual() == SubtablaEncuentros.Metodo.HIERBA


## El método de encuentro donde está, como ProtaCheckHierba decide global.hierba: hierba invisible
## (place_meeting); hierba (en su posición y 8 px más abajo); barro; y si no, las zonas de cuevas
## de ActivacionSalvajes (salvajes sin hierba, con la tabla de hierba). -1 si ninguno.
func metodo_actual() -> int:
	if surfeando():
		return SubtablaEncuentros.Metodo.SURF  # global.hierba = 2
	var aqui: Array[int] = _metodos_en(Vector2.ZERO)
	if SubtablaEncuentros.Metodo.HIERBA_INVISIBLE in aqui:
		return SubtablaEncuentros.Metodo.HIERBA_INVISIBLE
	if SubtablaEncuentros.Metodo.HIERBA in aqui and SubtablaEncuentros.Metodo.HIERBA in _metodos_en(Vector2(0, 8)):
		return SubtablaEncuentros.Metodo.HIERBA
	if SubtablaEncuentros.Metodo.BARRO in aqui:
		return SubtablaEncuentros.Metodo.BARRO
	if _tabla and _tabla.en_sin_hierba(global_position):
		return SubtablaEncuentros.Metodo.HIERBA
	return -1


## La subtabla que vale ahora en su posición (método, hora, historia, zona), o null.
func subtabla_actual() -> SubtablaEncuentros:
	var metodo: int = metodo_actual()
	if _tabla == null or metodo < 0:
		return null
	return _tabla.subtabla(metodo as SubtablaEncuentros.Metodo, Reloj.es_de_dia(), global_position, _mapa().cumple)


## ExplorerSalvajes tira el dado en cada step en que el jugador se movió ((18).moving: la posición
## cambió desde el step anterior), 30 por segundo, con probabilidad 1/frecuencia (FrequencySalvajes).
## Aquí: la probabilidad de al menos un acierto en los steps que caben en `delta`, así no depende de
## los FPS y correr o ir en bici cubren más distancia con la misma tasa por segundo, como en el original.
func _revisar_encuentro(delta: float, se_movio: bool) -> void:
	if _tabla == null or not se_movio or SceneManager.en_transicion or not GameState.dev_encuentros:
		return
	var sub: SubtablaEncuentros = subtabla_actual()
	if sub == null:
		return
	if randf() < 1.0 - pow(1.0 - 1.0 / maxf(sub.frecuencia, 1.0), STEPS_POR_SEGUNDO * delta) \
			and GameState.pokemon_para_combatir() != null:
		var salvaje: PokemonInstance = crear_salvaje(sub.sortear(_mapa().cumple))
		if salvaje:
			SceneManager.ir_a_batalla(salvaje, self)


## IniciaSalvaje: IV y ntv al azar y los ataques por nivel (PokemonInstance.crear). null si el sorteo
## cayó en el resto (no sale nada) o la especie no está extraída.
static func crear_salvaje(e: EncuentroSalvaje) -> PokemonInstance:
	var especie: PokemonData = Datos.especie(e.id_especie) if e else null
	return PokemonInstance.crear(especie, randi_range(e.nivel_min, e.nivel_max)) if especie else null


func _metodos_en(desplazamiento: Vector2) -> Array[int]:
	var forma: CollisionShape2D = $CollisionShape2D
	var consulta := PhysicsShapeQueryParameters2D.new()
	consulta.shape = forma.shape
	consulta.transform = Transform2D(0.0, global_position + forma.position + desplazamiento)
	consulta.collision_mask = CAPA_ZONAS
	consulta.collide_with_areas = true
	consulta.collide_with_bodies = false
	var out: Array[int] = []
	for r: Dictionary in get_world_2d().direct_space_state.intersect_shape(consulta, 8):
		var zona: ZonaHierba = r["collider"] as ZonaHierba
		if zona and zona.metodo not in out:
			out.append(zona.metodo)
	return out


## Bordes y escaleras se activan al entrar; las puertas pulsando arriba y la salida de los interiores
## pulsando abajo (DoorStepActions, OutDoorStepActions).
func _revisar_salidas() -> void:
	var dentro: Array[Salida] = []
	for nodo: Node in get_tree().get_nodes_in_group("salidas"):
		var s: Salida = nodo as Salida
		if s and s.contiene(self):
			dentro.append(s)
	if _primer_frame:
		_primer_frame = false
		_salidas_dentro = dentro
		return
	for s: Salida in dentro:
		var activar: bool = false
		match s.activacion:
			Salida.Activacion.AL_ENTRAR:
				activar = s not in _salidas_dentro
			Salida.Activacion.ARRIBA:
				activar = Input.is_action_pressed("mover_arriba")
			Salida.Activacion.ABAJO:
				activar = Input.is_action_pressed("mover_abajo")
		if activar and SceneManager.existe_mapa(s.destino if not s.volver else GameState.mapa_salida):
			if s.activacion == Salida.Activacion.ARRIBA and s.sprite:
				s.abrir()
			SceneManager.usar_salida(s, self)
			break
	_salidas_dentro = dentro


## Sprites del personaje elegido (código Q/CARA): data/extraido/personajes.json.
func _aplicar_personaje() -> void:
	if GameState.personaje == 0 and sprite_abajo:
		return
	var f: FileAccess = FileAccess.open("res://data/extraido/personajes.json", FileAccess.READ)
	if f == null:
		return
	var tabla: Dictionary = JSON.parse_string(f.get_as_text())
	var nombres: Variant = tabla["entrenadores"].get(str(GameState.personaje_entrenador)) if GameState.personaje == 10 \
		else tabla["protagonistas"].get(str(GameState.personaje))
	if nombres is Array and (nombres as Array).size() == 3:
		var cargar: Callable = func(n: String) -> SpriteOriginal: return load("res://assets/extraido/sprites/overworld/%s.tres" % n)
		sprite_abajo = cargar.call(nombres[0])
		sprite_arriba = cargar.call(nombres[1])
		sprite_derecha = cargar.call(nombres[2])


func _sprite() -> SpriteOriginal:
	if mira == 2:
		return sprite_abajo
	if mira == 8:
		return sprite_arriba
	return sprite_derecha


func surfeando() -> bool:
	return GameState.surfer != 0


func sobre_agua(pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var consulta := PhysicsPointQueryParameters2D.new()
	consulta.position = pos
	consulta.collision_mask = CAPA_AGUA
	return not get_world_2d().direct_space_state.intersect_point(consulta, 1).is_empty()


## KeyActionsProta + ProtaSurf: con agua justo enfrente, la medalla 6 y un Pokémon con la habilidad
## Surf (si no hay: TextDialog 2393), salta al agua sobre ese Pokémon.
func intentar_surf() -> void:
	var v: Vector2 = VECTOR_MIRA.get(mira, Vector2.DOWN)
	# ProtaSurf: agua a menos de 7 px del borde del jugador (distance_to_object), en la dirección en que mira.
	var distancia: float = -1.0
	for d: float in [8.0, 12.0, 16.0, 20.0]:
		if sobre_agua(global_position + v * d):
			distancia = d
			break
	if surfeando() or distancia < 0.0 or not GameState.tiene_medalla(6):
		return
	var p: PokemonInstance = GameState.con_habilidad_campo(2)
	if p == null:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 2393))
		return
	GameState.surfer = p.especie.id_original
	_entrando_agua = true
	_actualizar_montura()
	var t: Tween = create_tween()
	t.tween_property(self, "global_position", global_position + v * (distancia + 6.0), 0.2)
	await t.finished
	_entrando_agua = false


## Baja del Pokémon (ProtaMovimiento: global.surfer = false al no tocar agua).
func terminar_surf() -> void:
	GameState.surfer = 0
	_actualizar_montura()


## obj_pkmn_surf: el Pokémon que lleva al jugador por el agua, con sus sprites de movimiento.
func _actualizar_montura() -> void:
	var montura: AnimatedSprite2D = get_node_or_null("Montura")
	if not surfeando():
		if montura:
			montura.queue_free()
		return
	if montura == null:
		montura = AnimatedSprite2D.new()
		montura.name = "Montura"
		montura.show_behind_parent = true
		montura.position = Vector2(0, 6)
		var especie: PokemonData = Datos.especie(GameState.surfer)
		montura.sprite_frames = especie.cargar_sprite_frames() if especie else null
		add_child(montura)
	if montura.sprite_frames == null:
		return
	var propia: String = "mover_%d" % mira
	var espejo: Dictionary[int, int] = {1: 3, 4: 6, 7: 9}
	var anim: String = propia
	montura.flip_h = false
	if not montura.sprite_frames.has_animation(propia) and mira in espejo:
		anim = "mover_%d" % espejo[mira]
		montura.flip_h = true
	if montura.sprite_frames.has_animation(anim) and montura.animation != anim:
		montura.play(anim)


func _draw() -> void:
	var s: SpriteOriginal = _sprite()
	if s:
		# Izquierda (1, 4, 7): el sprite de la derecha volteado (ProtaSetSprite).
		# Surfeando va montado sobre el Pokémon (obj_pkmn_surf se dibuja debajo).
		s.dibujar(self, int(_frame), Vector2(0, -6 if surfeando() else 0), Vector2(-1 if mira in [1, 4, 7] else 1, 1))


func _mapa() -> Mapa:
	var n: Node = get_parent()
	while n and not n is Mapa:
		n = n.get_parent()
	return n as Mapa
