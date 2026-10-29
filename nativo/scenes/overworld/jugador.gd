class_name Jugador
extends CharacterBody2D
## El protagonista en el overworld (obj_Prota: ProtaMovimiento, ProtaSetSprite). Movimiento libre
## por píxel en 8 direcciones (en diagonal, velocidad / √2), a 90 px/s andando, 120 corriendo y 60
## lento (en bici 180, 210 y 90); quieto deja el frame 1 sin animar.

const VELOCIDAD_ANDAR: float = 90.0     # 3 px/step
const VELOCIDAD_CORRER: float = 120.0   # 4 px/step
const VELOCIDAD_LENTO: float = 60.0     # 2 px/step
## image_speed (frames por step) × 30.
const FPS_ANDAR: float = 6.0
const FPS_CORRER: float = 7.5
const FPS_LENTO: float = 4.5
## En bici (ProtaMovimiento con global.ciclista): 6 px/step, 7 corriendo y 3 lento.
const VELOCIDAD_BICI: float = 180.0
const VELOCIDAD_BICI_CORRER: float = 210.0
const VELOCIDAD_BICI_LENTO: float = 90.0
## Las cañas (Caña Vieja, Buena y Súper) y su subtabla de encuentros (Pescando).
const CANAS: Dictionary[int, SubtablaEncuentros.Metodo] = {181: SubtablaEncuentros.Metodo.CANA_VIEJA,
	182: SubtablaEncuentros.Metodo.CANA_BUENA, 183: SubtablaEncuentros.Metodo.SUPERCANA}
const OBJETO_BICI: int = 184
## Rooms de las que no se baja de la bici (Ciclovía: TextDialog 2434).
const SIN_BAJAR_DE_BICI: Array[String] = ["Ruta_13_1", "Ruta_14", "CarrilBicis", "CarrilBicis_2", "CarrilBicis_3"]
## Vista del original: 320×180 y la sigue con un borde horizontal de 120 px (hborder).
const BORDE_VISTA: float = 120.0
## Capa de física de las zonas (hierba).
const CAPA_ZONAS: int = 32
## Steps del original por segundo (room_speed).
const STEPS_POR_SEGUNDO: float = 30.0
## Paredes (capa 1), agua (capa 7: sin Surf no se pisa) y lava (capa 8: Ola Lava, pendiente).
const CAPAS_CHOQUE: int = 1 | 64 | 128
const CAPA_AGUA: int = 64
const CAPA_LAVA: int = 128
const VECTOR_MIRA: Dictionary[int, Vector2] = {2: Vector2.DOWN, 8: Vector2.UP, 4: Vector2.LEFT, 6: Vector2.RIGHT,
	1: Vector2(-1, 1), 3: Vector2(1, 1), 7: Vector2(-1, -1), 9: Vector2(1, -1)}

@export var sprite_abajo: SpriteOriginal
@export var sprite_arriba: SpriteOriginal
@export var sprite_derecha: SpriteOriginal
## En bici (sprDB/UB/RB) y pescando (sprDP/UP/RP): abajo, arriba, derecha (data/extraido/personajes.json).
var sprites_bici: Array[SpriteOriginal] = []
var sprites_pesca: Array[SpriteOriginal] = []
## PESCA: con la caña echada (90 steps).
var _pescando: bool = false

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
## (14).CASCADA: Cascada activada en este mapa (DefineProta la apaga al entrar a otro).
var _cascada: bool = false
## (14).TREPARROCA: trepando hacia abajo (2) o hacia arriba (8); 0 = no. Mientras, la pared trepable
## no choca (object_set_parent(obj_rocatrepable, -1)).
var _trepando: int = 0
var _pasos_trepa: float = 0.0
## Los decorados del mapa por prefijo de nombre (los que se tocan con place_meeting).
var _decorados: Dictionary[String, Array] = {}

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
	# V (key_ex_bicicleta): subir o bajar de la bici (también en marcha).
	if tecla_mo == KEY_V:
		get_viewport().set_input_as_handled()
		alternar_bici()
		return
	# C (key_ex_pescar): con una caña, de cara al agua.
	if tecla_mo == KEY_C and quieto() and not _pescando:
		get_viewport().set_input_as_handled()
		pescar()
		return
	# 5 (key_ex_mo5_destello): en una cueva oscura, Destello.
	if tecla_mo == KEY_5 and quieto() and _mapa() and _mapa().has_node("Oscuridad"):
		get_viewport().set_input_as_handled()
		(_mapa().get_node("Oscuridad") as Oscuridad).usar_destello(self)
		return
	# 7 (key_ex_mo7_buceo): sumergirse en agua buceable o salir a la superficie.
	if tecla_mo == KEY_7 and quieto():
		get_viewport().set_input_as_handled()
		intentar_buceo()
		return
	# ProtaStartsCascada: Z surfeando junto a una cascada (medalla 8) pregunta si se sube.
	if evento.is_action_pressed("interactuar") and surfeando() and not GameState.surf_lava and not _cascada and quieto() \
			and GameState.tiene_medalla(8) and _toca(CASCADAS, Vector2.ZERO, 5.0):
		get_viewport().set_input_as_handled()
		intentar_cascada()
		return
	# ProtaTreparrocas: Z mirando arriba o abajo junto a una pared trepable (medalla 7).
	if evento.is_action_pressed("interactuar") and quieto() and not surfeando() and mira in [2, 8] \
			and GameState.tiene_medalla(7) and _roca_trepable() != null:
		get_viewport().set_input_as_handled()
		intentar_treparrocas()
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
	collision_mask = 0 if GameState.dev_noclip or _trepando else (CAPAS_CHOQUE & ~_capa_surf() if surfeando() else CAPAS_CHOQUE)
	_actualizar_montura()
	if _trepando:
		_paso_trepar(delta)
		return
	if _pescando:  # image_speed 0.2 con la caña echada
		_frame = fmod(_frame + 6.0 * delta, maxf(_sprite().frames.size() if _sprite() else 1, 1))
		queue_redraw()
		return
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
	var velocidad: float = VELOCIDAD_BICI if GameState.ciclista else VELOCIDAD_ANDAR
	var fps: float = FPS_ANDAR
	if Input.is_action_pressed("correr"):
		velocidad = VELOCIDAD_BICI_CORRER if GameState.ciclista else VELOCIDAD_CORRER
		fps = FPS_CORRER
	elif Input.is_action_pressed("andar_lento"):
		velocidad = VELOCIDAD_BICI_LENTO if GameState.ciclista else VELOCIDAD_LENTO
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
	_corriente_cascada(velocidad, delta)
	# ProtaMovimiento: al dejar el agua termina el surf solo (bajo el agua se sigue sobre el Pokémon).
	if surfeando() and not GameState.buceando and not sobre_agua(global_position, _capa_surf()):
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
		# global.hierba = 2 (sobre la lava, su propia subtabla).
		return SubtablaEncuentros.Metodo.LAVA if GameState.surf_lava else SubtablaEncuentros.Metodo.SURF
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
	var f: FileAccess = FileAccess.open("res://data/extraido/personajes.json", FileAccess.READ)
	if f == null:
		return
	var tabla: Dictionary = JSON.parse_string(f.get_as_text())
	var nombres: Variant = tabla["entrenadores"].get(str(GameState.personaje_entrenador)) if GameState.personaje == 10 \
		else tabla["protagonistas"].get(str(GameState.personaje))
	if not nombres is Array or (nombres as Array).size() < 3:
		return
	var cargar: Callable = func(n: String) -> SpriteOriginal: return load("res://assets/extraido/sprites/overworld/%s.tres" % n)
	if GameState.personaje != 0 or sprite_abajo == null:
		sprite_abajo = cargar.call(nombres[0])
		sprite_arriba = cargar.call(nombres[1])
		sprite_derecha = cargar.call(nombres[2])
	if (nombres as Array).size() == 9:
		sprites_bici.assign([cargar.call(nombres[3]), cargar.call(nombres[4]), cargar.call(nombres[5])])
		sprites_pesca.assign([cargar.call(nombres[6]), cargar.call(nombres[7]), cargar.call(nombres[8])])


func _sprite() -> SpriteOriginal:
	var trio: Array[SpriteOriginal] = [sprite_abajo, sprite_arriba, sprite_derecha]
	if _pescando and sprites_pesca.size() == 3:
		trio = sprites_pesca
	elif GameState.ciclista and not surfeando() and sprites_bici.size() == 3:
		trio = sprites_bici
	return trio[0] if mira == 2 else trio[1] if mira == 8 else trio[2]


## KeyActionsProta (V): con la Bicicleta y sin surfear, sube o baja. En un interior solo en las cuevas
## (obj_cueva; si no, TextDialog 2435) y en la Ciclovía no se baja (2434).
func alternar_bici() -> void:
	if surfeando():
		return
	if not GameState.objetos.has(OBJETO_BICI):
		GameState.ciclista = false
		return
	var mapa: Mapa = _mapa()
	if GameState.mapa_salida != "" and not _es_cueva(mapa):
		await CajaDialogo.decir(self, Textos.linea("txt_dialog", 2435))
		return
	if GameState.ciclista and mapa and mapa.nombre_original in SIN_BAJAR_DE_BICI:
		await CajaDialogo.decir(self, Textos.linea("txt_dialog", 2434))
		return
	GameState.ciclista = not GameState.ciclista
	queue_redraw()


static func _es_cueva(mapa: Mapa) -> bool:
	return mapa != null and mapa.get_node("Marcadores").get_children().any(
		func(n: Node) -> bool: return n.get_meta("objeto", "") == "obj_cueva")


## KeyActionsProta (C) + ProtaPesca + Pescando: con una caña (si hay varias se elige; TextDialog
## 2416-2419) y el agua justo enfrente, se echa (2420) y a los 90 steps pica la mitad de las veces
## (si no, 72): sale un salvaje de la subtabla de esa caña (73) o, si no hay, 71.
func pescar() -> void:
	var canas: Array[int] = []
	for c: int in CANAS:
		if GameState.objetos.has(c):
			canas.append(c)
	if canas.is_empty() or not sobre_agua(global_position + VECTOR_MIRA.get(mira, Vector2.DOWN) * 10.0):
		return
	if GameState.bandera("historia_manaphy") >= 5:
		await CajaDialogo.decir(self, Textos.linea("txt_dialog", 2411))
		return
	var cana: int = canas[0]
	if canas.size() > 1:
		# Vieja + Buena 2416, Vieja + Súper 2417, Buena + Súper 2418, las tres 2419.
		var texto: int = 2419 if canas.size() == 3 else {363: 2416, 364: 2417, 365: 2418}[canas[0] + canas[1]]
		var sel: int = await MenuLista.elegir(self, Textos.linea("txt_dialog", texto),
			canas.map(func(c: int) -> Dictionary: return {"texto": Inventario.nombre(c)}))
		if sel < 0:
			return
		cana = canas[sel]
	await CajaDialogo.decir(self, Textos.par(Textos.linea("txt_dialog", 2420), Inventario.nombre(cana)))
	_pescando = true
	_frame = 0.0
	await get_tree().create_timer(90.0 / STEPS_POR_SEGUNDO, false).timeout
	_pescando = false
	_frame = 1.0
	queue_redraw()
	if randi_range(1, 2) == 2:
		await CajaDialogo.decir(self, Textos.linea("txt_dialog", 72))
		return
	var sub: SubtablaEncuentros = _tabla.subtabla(CANAS[cana], Reloj.es_de_dia(), global_position, _mapa().cumple) if _tabla else null
	var salvaje: PokemonInstance = crear_salvaje(sub.sortear(_mapa().cumple)) if sub else null
	if salvaje == null:
		await CajaDialogo.decir(self, Textos.linea("txt_dialog", 71))
		return
	await CajaDialogo.decir(self, Textos.linea("txt_dialog", 73))
	SceneManager.ir_a_batalla(salvaje, self)


func surfeando() -> bool:
	return GameState.surfer != 0


func sobre_agua(pos: Vector2, capa: int = CAPA_AGUA) -> bool:
	if not is_inside_tree():
		return false
	var consulta := PhysicsPointQueryParameters2D.new()
	consulta.position = pos
	consulta.collision_mask = capa
	return not get_world_2d().direct_space_state.intersect_point(consulta, 1).is_empty()


## KeyActionsProta + ProtaSurf: con agua justo enfrente, la medalla 6 y un Pokémon con la habilidad
## Surf (si no hay: TextDialog 2393), salta al agua sobre ese Pokémon.
func intentar_surf() -> void:
	var v: Vector2 = VECTOR_MIRA.get(mira, Vector2.DOWN)
	# ProtaSurf: agua a menos de 7 px del borde del jugador (distance_to_object), en la dirección en que mira.
	# Si lo que hay es lava (obj_lava), ProtaOlaLava: medalla 8 y la habilidad Ola Lava (si no, 2394).
	var distancia: float = -1.0
	var lava: bool = false
	for d: float in [8.0, 12.0, 16.0, 20.0]:
		if sobre_agua(global_position + v * d) or sobre_agua(global_position + v * d, CAPA_LAVA):
			distancia = d
			lava = not sobre_agua(global_position + v * d)
			break
	if surfeando() or distancia < 0.0 or not GameState.tiene_medalla(8 if lava else 6):
		return
	var p: PokemonInstance = GameState.con_habilidad_campo(16 if lava else 2)
	if p == null:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 2394 if lava else 2393))
		return
	GameState.surf_lava = lava
	GameState.ciclista = false
	GameState.surfer = p.especie.id_original
	_entrando_agua = true
	_actualizar_montura()
	var t: Tween = create_tween()
	t.tween_property(self, "global_position", global_position + v * (distancia + 6.0), 0.2)
	await t.finished
	_entrando_agua = false


## place_meeting(x + d.x, y + d.y, obj) con los decorados cuyo nombre empieza por algún prefijo;
## `margen` agranda la caja (distance_to_object < margen).
func _toca(prefijos: Array[String], d: Vector2 = Vector2.ZERO, margen: float = 0.0) -> bool:
	var forma: CollisionShape2D = $CollisionShape2D
	var tam: Vector2 = (forma.shape as RectangleShape2D).size if forma.shape is RectangleShape2D else Vector2(12, 12)
	var mia := Rect2(global_position + forma.position + d - tam / 2.0, tam).grow(margen)
	for n: Decorado in _decorados_con(prefijos):
		if n.visible and mia.intersects(n.caja()):
			return true
	return false


func _decorados_con(prefijos: Array[String]) -> Array:
	var clave: String = ",".join(prefijos)
	if clave not in _decorados:
		var lista: Array = []
		var mapa: Mapa = _mapa()
		if mapa:
			for n: Node in mapa.get_node("Objetos").get_children():
				if n is Decorado and prefijos.any(func(p: String) -> bool: return n.name.begins_with(p)) \
						and not n.name.begins_with("obj_cascadaLava"):
					lista.append(n)
		_decorados[clave] = lista
	return _decorados[clave]


## Las paredes trepables (obj_rocatrepable y obj_rocatrepablesimple).
const ROCAS_TREPABLES: Array[String] = ["obj_rocatrepable"]


## KeyActionsRocaTrepable: la pared trepable que el jugador tiene delante (alineado en x, mirando hacia
## ella y a menos de 10 px), o null.
func _roca_trepable() -> Decorado:
	var forma: CollisionShape2D = $CollisionShape2D
	var tam: Vector2 = (forma.shape as RectangleShape2D).size if forma.shape is RectangleShape2D else Vector2(12, 12)
	var mia := Rect2(global_position + forma.position - tam / 2.0, tam).grow(10.0)
	for n: Decorado in _decorados_con(ROCAS_TREPABLES):
		var c: Rect2 = n.caja()
		var alineado: bool = absf(global_position.x - c.get_center().x) <= (10.0 if n.name.begins_with("obj_rocatrepablesimple") else 8.0)
		var hacia: bool = (mira == 8 and global_position.y > n.global_position.y) or (mira == 2 and global_position.y < n.global_position.y)
		if alineado and hacia and mia.intersects(c):
			return n
	return null


## ProtaTreparrocas: pregunta (2399) y, con un Pokémon con Treparrocas (si no, 2400), cruza la pared.
func intentar_treparrocas() -> void:
	var roca: Decorado = _roca_trepable()
	if roca == null or not await CuadroOriginal.preguntar(self, Textos.linea("txt_dialog", 2399)):
		return
	if GameState.con_habilidad_campo(13) == null:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 2400))
		return
	_trepando = mira
	global_position += Vector2(0, 8 if mira == 2 else -8)
	global_position.x = roca.global_position.x
	_pasos_trepa = 0.0


## Un step trepando: 4 px mientras siga sobre la pared (hacia arriba se mira 4 px más abajo).
func _paso_trepar(delta: float) -> void:
	_pasos_trepa += delta * 30.0
	while _pasos_trepa >= 1.0 and _trepando:
		_pasos_trepa -= 1.0
		if _toca(ROCAS_TREPABLES, Vector2(0, 0 if _trepando == 2 else 4)):
			global_position.y += 4.0 if _trepando == 2 else -4.0
			_frame = fmod(_frame + 0.3, maxf(_sprite().frames.size() if _sprite() else 1, 1))
		else:
			_trepando = 0
			_frame = 1.0
	queue_redraw()


## Lo que se cruza surfeando: el agua o, con Ola Lava, la lava.
func _capa_surf() -> int:
	return CAPA_LAVA if GameState.surf_lava else CAPA_AGUA


## Las cascadas que se suben con Cascada (TERRENO "surf+cascada" en tools/mapas_original.py).
const CASCADAS: Array[String] = ["obj_cascada"]


## ProtaStartsCascada: surfeando en una cascada (salvo en su borde de abajo) la corriente empuja hacia
## abajo a la velocidad del jugador, así que sin Cascada no se sube; con Cascada empuja 2 px/step.
func _corriente_cascada(velocidad: float, delta: float) -> void:
	if not surfeando() or not _toca(CASCADAS) or not _toca(CASCADAS, Vector2(0, 22)):
		return
	move_and_collide(Vector2(0, (60.0 if _cascada else velocidad) * delta))


## ProtaCascada (pregunta 2405): con un Pokémon con la habilidad Cascada se sube sobre él (y aprende a
## surfear: EstableceHabExt); si no hay, TextDialog 2395.
func intentar_cascada() -> void:
	if not await CuadroOriginal.preguntar(self, Textos.linea("txt_dialog", 2405)):
		return
	var p: PokemonInstance = GameState.con_habilidad_campo(9)
	if p == null:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 2395))
		return
	_cascada = true
	p.habilidades_campo |= 1 << 2
	if GameState.surfer != p.especie.id_original:
		GameState.surfer = p.especie.id_original
		var montura: Node = get_node_or_null("Montura")
		if montura:
			montura.free()
		_actualizar_montura()


## KeyActionsProta (tecla 7) + ProtaBuceo: con la medalla 7 y un Pokémon con Buceo (si no, 2412), sobre
## agua buceable pregunta si se sumerge (2413); bajo el agua, junto a la superficie, si sube (2414).
func intentar_buceo() -> void:
	if not GameState.tiene_medalla(7):
		return
	var buzo: PokemonInstance = GameState.con_habilidad_campo(6)
	if buzo == null:
		await CuadroOriginal.mensaje(self, Textos.linea("txt_dialog", 2412))
		return
	var superficie: Vector2 = _superficie_cercana()
	if surfeando() and not GameState.buceando and _toca(["obj_agua_buceable"]):
		if await CuadroOriginal.preguntar(self, Textos.linea("txt_dialog", 2413)):
			await _bucear("abajo", buzo, superficie)
	elif superficie != Vector2.INF and global_position.distance_to(superficie) < DISTANCIA_SUPERFICIE:
		if await CuadroOriginal.preguntar(self, Textos.linea("txt_dialog", 2414)):
			await _bucear("arriba", buzo, superficie)


## distance_to_object(obj_superficie) < 10: su caja (spr_hidro) mide 21×19 con el origen en el centro.
const DISTANCIA_SUPERFICIE: float = 20.0


## obj_superficie: marcadores del mapa.
func _superficie_cercana() -> Vector2:
	var mejor: Vector2 = Vector2.INF
	var mapa: Mapa = _mapa()
	if mapa == null:
		return mejor
	for n: Node in mapa.get_node("Marcadores").get_children():
		if n.get_meta("objeto", "") == "obj_superficie" and global_position.distance_to(n.global_position) < global_position.distance_to(mejor):
			mejor = (n as Node2D).global_position
	return mejor


## GoDiving: al otro mapa; abajo sobre el Pokémon con Buceo, arriba sobre uno con Surf (o el buzo, que
## aprende a surfear).
func _bucear(direccion: String, buzo: PokemonInstance, superficie: Vector2) -> void:
	var d: Dictionary = Buceo.destino(direccion, GameState.mapa_actual, GameState.indice_lugar, global_position,
		superficie if superficie != Vector2.INF else global_position)
	if d.is_empty():
		return
	var montura: PokemonInstance = buzo
	if direccion == "arriba":
		montura = GameState.con_habilidad_campo(2)
		if montura == null:
			montura = buzo
			buzo.habilidades_campo |= 1 << 2
	GameState.surfer = montura.especie.id_original
	GameState.buceando = direccion == "abajo"
	GameState.indice_lugar = d.indice
	if d.has("salida_mapa"):
		GameState.mapa_salida = d.salida_mapa
		GameState.posicion_salida = d.salida_posicion
	await SceneManager.ir_a_mapa(d.mapa, d.posicion, 2)


## Baja del Pokémon (ProtaMovimiento: global.surfer = false al no tocar agua).
func terminar_surf() -> void:
	GameState.surfer = 0
	GameState.surf_lava = false
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
